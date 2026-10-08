# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassMaps
extends RefCounted
## The grass maps: one RGBA8 image per Terrain3D region (GrassMapCodec), stored beside the region files
## (<data_directory>/<folder>/<Terrain3DUtil.location_to_filename(loc)>) and held here as one Texture2DArray with a
## layer per MAP, not per terrain layer: slot_table() says which of its layers holds the region in each of Terrain3D's
## layers (the region map's value - 1, with or without streaming). The blade and decoration compute and the far carpet
## read the array through that table. A region without a map grows the ground's grass (NEUTRAL): its entry is 0 and the
## shaders use the constant, fetching nothing, so a terrain with no map holds a 1x1x1 array.
## The array's size: as many layers as maps can be resident at once (the map files on disk, at most the terrain's layer
## count), allocated when the first map lands. A landing takes a free layer and a region leaving gives its layer back,
## so in the game a landing never reallocates. Only a map that was not on disk at the bind (painted in the editor,
## adopted) can find no free layer: the array then doubles, its maps sent again.
## Owned by GrassBlades. The grass keeps its maps itself, so it runs on any Terrain3D.

signal changed                     # the texture was rebuilt, a layer updated, or slot_table() changed

const NEUTRAL := Color(128.0 / 255.0, 0.0, 128.0 / 255.0, 1.0)   # x1, the ground decides, the authored height, not forced
const MAP_SIZE := 32               # Terrain3D's region map: MAP_SIZE^2 cells (REGION_MAP_SIZE)
## slot_table()'s length: every layer a terrain's region map can name (and the shaders' table length).
const MAP_CELLS := MAP_SIZE * MAP_SIZE
const QUERY_REGIONS := 8           # region maps kept for GrassBlades.sample() (the game holds none of its own)

var folder := "grass"
var keep_images := false           # the editor keeps each region's Image (painting, picking, saving)
var editor := false                # streaming follows the editor's own switch
var errors: PackedStringArray = []
var sync_loads := 0                # maps decoded on the main thread: a streamed region's never is
var _terrain: Object = null
var _tex: Texture2DArray = null
var _retired: Texture2DArray = null   # the array _build replaced, kept to the next poll() (GrassBlades re-points to the new one)
var _tex_size := 0                 # the region size _tex holds maps of (0: the 1x1x1 placeholder)
var _layers: Array = []            # terrain layer -> region location, or null (an unused streaming slot)
var _map_layer := {}               # location -> its layer of _tex: the resident regions that have a map
var _free: Array[int] = []         # layers of _tex no region holds (popped from the back: the lowest first)
var _cap := 0                      # map layers in _tex (0: the placeholder, which no slot points at)
var _want_cap := 0                 # the layers the first map's array gets: the map files on disk, at most the terrain's
var _table_gen := 0                # bumped whenever slot_table() changes
var _table := PackedInt32Array()   # slot_table() as last built, at _table_built
var _table_built := -1
var _warned_layers := false
var _images := {}                  # location -> Image (keep_images; adopted ones always)
var _mapped := {}                  # location -> true: its held Image is a map (a file's, adopted, painted), not a stand-in
var _adopted := {}                 # location -> true: given by adopt(), never loaded from a file
var _size := 0
var _pending := {}                 # location -> [task id, [Image]]: a streamed region's map, loading on a worker thread
var _q_images := {}                # location -> Image, or null (no file: NEUTRAL): the queries' own maps
var _q_order: Array[Vector2i] = [] # _q_images' keys, least recently used first
var _q_pending := {}               # location -> [task id, [Image]]: a query's map, loading on a worker thread
var _waited := {}                  # task id -> true: already waited (a second wait is "Invalid Task ID" spam)
var _lost_tasks := 0               # adds the pool refused (tid < 0) or ids that died un-waited
var _dirty := {}                   # location -> true: changed since the last save
var _removed := {}                 # location -> true: a region removed in the editor: its file goes on the save
var scene_path := ""               # the scene its GrassBlades is saved in (the quit prompt asks per scene)
static var _unsaved: Array = []    # WeakRef of every instance with unsaved changes


func bind(p_terrain: Object) -> void:
	_q_images.clear()
	_q_order.clear()
	_terrain = p_terrain
	refresh(true)


func texture() -> Texture2DArray:
	return _tex


func rid() -> RID:
	return _tex.get_rid() if _tex != null else RID()


func layers() -> Array:
	return _layers.duplicate()


## The terrain layer (slot) a region is resident in, -1 where it is not.
func layer_of(p_loc: Vector2i) -> int:
	return _layers.find(p_loc)


## The layer of texture() holding a region's map, -1 where it has none or is not resident (slot_table() - 1).
func map_layer_of(p_loc: Vector2i) -> int:
	return int(_map_layer.get(p_loc, -1))


## The map layers texture() has room for (0: the 1x1x1 placeholder: no map resident yet, or none at all).
func capacity() -> int:
	return _cap


## Bumped whenever slot_table() changes: a region landing or leaving, a map given a layer, the array rebuilt.
func table_version() -> int:
	return _table_gen


## Terrain3D's layer z -> 1 + the layer of texture() holding its region's map, 0 where that region has no map (the
## shaders read NEUTRAL there and fetch nothing). MAP_CELLS long: every layer a region map can name.
func slot_table() -> PackedInt32Array:
	if _table_built != _table_gen:
		_table = PackedInt32Array()
		_table.resize(MAP_CELLS)
		for i in mini(_layers.size(), MAP_CELLS):
			var loc = _layers[i]
			if loc != null and _map_layer.has(loc):
				_table[i] = int(_map_layer[loc]) + 1
		_table_built = _table_gen
	return _table


## layer -> region location for Terrain3D's region map (MAP_SIZE^2 cells, value = layer + 1), its window at `origin`: the
## inverse of grass_place_common.glsli vertex_texel.
static func layout(p_map: PackedInt32Array, p_origin: Vector2i) -> Dictionary:
	var out := {}
	for i in p_map.size():
		var v := p_map[i]
		if v > 0:
			out[v - 1] = Vector2i(i % MAP_SIZE, i / MAP_SIZE) - Vector2i(MAP_SIZE / 2, MAP_SIZE / 2) + p_origin
	return out


## Re-reads the region map. The first time (or `force`) builds the array, loading every resident map on the worker pool
## and waiting. After that a region landing reads NEUTRAL while its map loads on a worker thread (poll() gives it a free
## layer; no file: none at all), a region leaving gives its layer back, and a region moving to another slot (a terrain
## without streaming re-packs its layers) only changes slot_table(): no map is sent again.
func refresh(p_force := false) -> void:
	if _terrain == null:
		return
	var data: Object = _terrain.get("data")
	if data == null:
		return
	_size = int(_terrain.get("region_size"))
	var lay := layout(data.call("get_region_map"), GrassTerrainCaps.region_map_origin(data))
	var n := GrassTerrainCaps.layer_count(_terrain, editor)
	for k in lay:
		n = maxi(n, int(k) + 1)
	var want: Array = []
	want.resize(n)
	for k in lay:
		want[int(k)] = lay[k]
	# The editor without streaming (a region in the map is a region of the terrain): a new region's NEUTRAL map is to be
	# saved; a region gone from the map has its file deleted on the save, unless it comes back first (undo).
	if keep_images and not _layers.is_empty() and not GrassTerrainCaps.streaming_on(_terrain, editor):
		var had := {}
		for l in _layers:
			if l != null:
				had[l] = true
		for l in want:
			if l != null and not had.has(l):
				_removed.erase(l)
				if not FileAccess.file_exists(path_for(l)):
					_dirty[l] = true
		for l in had:
			if not want.has(l):
				_removed[l] = true
				_dirty.erase(l)
		if unsaved():
			_track()
	if n > MAP_CELLS and not _warned_layers:
		_warned_layers = true
		errors.append("the terrain has %d layers; the slot table holds %d, the rest read NEUTRAL" % [n, MAP_CELLS])
		push_error("[GrassMaps] " + errors[errors.size() - 1])
	if n == 0:
		_tex = null
		_tex_size = 0
		_cap = 0
		_layers = []
		_map_layer.clear()
		_free.clear()
		_table_gen += 1
		changed.emit()
		return
	if p_force or _tex == null or (_cap > 0 and _tex_size != _size):
		_rebuild(want)
		return
	if want == _layers:
		return
	var before := {}
	for l in _layers:
		if l != null:
			before[l] = true
	_layers = want
	var resident := {}
	for l in want:
		if l != null:
			resident[l] = true
	for loc in _map_layer.keys():
		if not resident.has(loc):
			_free.append(_map_layer[loc])  # left: its layer is free again (nothing sent)
			_map_layer.erase(loc)
	for loc in resident:
		if _map_layer.has(loc) or before.has(loc):
			continue                       # resident before: in its layer, or loading, or without a map
		if _images.has(loc):
			if _mapped.has(loc):
				_place(loc, _images[loc])  # a held map (the editor's, adopted) back in
		else:
			_start_load(loc)               # read on a worker thread; NEUTRAL until poll() places it
	_table_gen += 1
	changed.emit()


## The first build (and a forced one): every resident map loaded on the worker pool, then an array with room for every
## map on disk that can be resident at once, allocated now if any map is resident (else when the first one lands).
func _rebuild(p_want: Array) -> void:
	_load_all(p_want)
	_layers = p_want
	_want_cap = mini(_files_on_disk(), p_want.size())
	var maps := {}
	for loc in p_want:
		if loc != null and _images.has(loc) and _mapped.has(loc):
			maps[loc] = _images[loc]
	_build(maps, _want_cap)
	_forget()
	changed.emit()


## A new array holding `maps` (location -> region-sized RGBA8 Image) with room for `cap` maps in all; the 1x1x1
## placeholder when there are none. The spare layers repeat the first map (never read: no slot points at them).
func _build(p_maps: Dictionary, p_cap: int) -> void:
	_map_layer.clear()
	_free.clear()
	var imgs: Array[Image] = []
	if p_maps.is_empty():
		_cap = 0
		_tex_size = 0
		imgs.append(_placeholder())
	else:
		_cap = maxi(p_cap, p_maps.size())
		_tex_size = _size
		for loc in p_maps:
			_map_layer[loc] = imgs.size()
			imgs.append(p_maps[loc])
		var spare: Image = imgs[0]
		for i in range(imgs.size(), _cap):
			imgs.append(spare)
		for i in range(_cap - 1, p_maps.size() - 1, -1):
			_free.append(i)
	_retired = _tex                    # until the next poll(): the terrain material may still point at it for a frame
	_tex = Texture2DArray.new()
	_tex.create_from_images(imgs)
	_table_gen += 1


## A resident region's map into its layer: a free one when it has none yet, the array grown when none is free.
func _place(p_loc: Vector2i, p_img: Image) -> void:
	var l: int = _map_layer.get(p_loc, -1)
	if l >= 0:
		_tex.update_layer(p_img, l)
		return
	if _free.is_empty():
		_grow(p_loc, p_img)
		return
	l = _free.pop_back()
	_map_layer[p_loc] = l
	_tex.update_layer(p_img, l)
	_table_gen += 1


## No free layer for a new map (one not on disk at the bind: painted, adopted; or the first map to land): a new array
## with every resident map, at the bind's size or twice the old one, at most the terrain's layer count. Maps the game no
## longer holds are read again from their files, on the worker pool.
func _grow(p_loc: Vector2i, p_img: Image) -> void:
	var gone: Array = _map_layer.keys().filter(func(l): return not _images.has(l))
	if not gone.is_empty():
		_load_all(gone)
	var maps := {}
	for loc in _map_layer:
		if _images.has(loc):
			maps[loc] = _images[loc]
	maps[p_loc] = p_img
	_build(maps, mini(maxi(_want_cap, _cap * 2), maxi(_layers.size(), 1)))
	_forget()


## The map files in this folder: no more maps than these can ever be resident at once.
func _files_on_disk() -> int:
	var d := path_for(Vector2i.ZERO).get_base_dir()
	if d == "" or not DirAccess.dir_exists_absolute(d):
		return 0
	return Array(DirAccess.get_files_at(d)).filter(func(f: String) -> bool: return f.ends_with(".res")).size()


## A region's map changed (painted, undone, added): saved on the next save.
func mark_dirty(p_loc: Vector2i) -> void:
	_dirty[p_loc] = true
	_removed.erase(p_loc)
	_track()


func unsaved() -> bool:
	return not _dirty.is_empty() or not _removed.is_empty()


## Every live GrassMaps with unsaved changes, in any open scene tab (the save and the quit prompt use it).
static func unsaved_maps() -> Array:
	var out := []
	for w in _unsaved.duplicate():
		var m: GrassMaps = (w as WeakRef).get_ref()
		if m == null or not m.unsaved():
			_unsaved.erase(w)
		elif not out.has(m):
			out.append(m)
	return out


## Those of one scene ("": every scene, as when the editor quits).
static func unsaved_for(p_scene: String) -> Array:
	return unsaved_maps().filter(func(m: GrassMaps) -> bool: return p_scene == "" or m.scene_path == p_scene)


func _track() -> void:
	for w in _unsaved:
		if (w as WeakRef).get_ref() == self:
			return
	_unsaved.append(weakref(self))


## Writes every dirty map (the .res Image by the region's file name) and deletes removed regions' files: location -> Error.
## A failed write stays dirty (the next save retries).
func save_dirty() -> Dictionary:
	var out := {}
	for loc in _dirty.keys():
		var p := path_for(loc)
		if p == "":
			out[loc] = ERR_FILE_BAD_PATH
			continue
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var e := ResourceSaver.save(image(loc), p)
		out[loc] = e
		if e == OK:
			_dirty.erase(loc)
		else:
			push_error("[GrassMaps] could not write %s: %s" % [p, error_string(e)])
	for loc in _removed.keys():
		var p := path_for(loc)
		var e := OK
		if p != "" and FileAccess.file_exists(p):
			e = DirAccess.remove_absolute(p)
		out[loc] = e
		if e == OK:
			_removed.erase(loc)
	unsaved_maps()                   # prunes this instance when it is clean
	return out


func region_size() -> int:
	return _size


func vertex_spacing() -> float:
	return float(_terrain.get("vertex_spacing")) if _terrain != null else 1.0


func path_for(p_loc: Vector2i) -> String:
	var d := String(_terrain.get("data_directory")) if _terrain != null else ""
	return d.path_join(folder).path_join(Terrain3DUtil.location_to_filename(p_loc)) if d != "" else ""


## A region's map in the editor (kept): its file's, adopted, or a new NEUTRAL one (a map once painted: update_layer).
func image(p_loc: Vector2i) -> Image:
	if not _images.has(p_loc):
		_images[p_loc] = _load(p_loc)
	return _images[p_loc]


## Tests and tools: this image IS the region's map (no file is read for it); its layer updates now if resident.
func adopt(p_loc: Vector2i, p_img: Image) -> void:
	var img := p_img
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	_images[p_loc] = img
	_adopted[p_loc] = true
	update_layer(p_loc)


## Re-sends a region's layer from its image (after painting). Its image is a map from now on: a resident region that
## had none gets a layer (the array grows when none is free), one not resident gets it when it lands.
func update_layer(p_loc: Vector2i) -> void:
	if _images.has(p_loc):
		_mapped[p_loc] = true
	if layer_of(p_loc) < 0 or _tex == null:
		return
	var img := image(p_loc)
	_mapped[p_loc] = true
	_place(p_loc, img)
	changed.emit()


func location_of(p_pos: Vector3) -> Vector2i:
	var region_m := float(_size) * float(_terrain.get("vertex_spacing"))
	return Vector2i(floori(p_pos.x / region_m), floori(p_pos.z / region_m))


## The texel under a position (the picker): its region's map, NEUTRAL outside every map.
func pixel(p_pos: Vector3) -> Color:
	var loc := location_of(p_pos)
	if layer_of(loc) < 0 and not _images.has(loc):
		return NEUTRAL
	var vs := float(_terrain.get("vertex_spacing"))
	var px := Vector2i(floori(p_pos.x / vs), floori(p_pos.z / vs)) - loc * _size
	var img := image(loc)
	if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
		return NEUTRAL
	return img.get_pixelv(px)



## The map texel at Terrain3D vertex `v` for GrassBlades.sample(): a held map (the editor keeps them; adopted ones), else
## the queries' own cache of QUERY_REGIONS regions, each read from its file on a worker thread. NEUTRAL while a region
## loads (query_pending) and where it has no file.
func query_texel(v: Vector2i) -> Color:
	if _size <= 0:
		return NEUTRAL
	var loc := Vector2i(floori(float(v.x) / _size), floori(float(v.y) / _size))
	var img: Image = _images[loc] if _images.has(loc) else _query_image(loc)
	return img.get_pixelv(v - loc * _size) if img != null else NEUTRAL


## True while vertex `v`'s region map is still loading for the queries.
func query_pending(v: Vector2i) -> bool:
	if _size <= 0:
		return false
	return _q_pending.has(Vector2i(floori(float(v.x) / _size), floori(float(v.y) / _size)))


func _query_image(loc: Vector2i) -> Image:
	if _q_images.has(loc):
		_q_order.erase(loc)
		_q_order.append(loc)
		return _q_images[loc]
	if _q_pending.has(loc):
		var job: Array = _q_pending[loc]
		if not _done(job[0]):
			return null
		_q_pending.erase(loc)
		var got: Image = job[1][0]
		_q_keep(loc, _checked(got, loc) if got != null else null)
		return _q_images[loc]
	var path := path_for(loc)
	if path == "" or not FileAccess.file_exists(path):
		_q_keep(loc, null)
		return null
	var box := [null]
	var tid := WorkerThreadPool.add_task(func() -> void: box[0] = GrassMaps._read_path(path))
	if tid < 0:
		_lost_task("add_task refused a query read for %s; reading it synchronously" % str(loc))
		_q_keep(loc, _checked(_read_path(path), loc))
		return _q_images[loc]
	_q_pending[loc] = [tid, box]
	return null


## A task finished AND its id is still waitable. `is_task_completed` cannot distinguish
## a completed task from a dead id (a wait on the latter prints the C++ "Invalid Task
## ID" error), so waits are funneled here: the first wait lands, repeats are skipped,
## and an id that dies un-waited is counted and reported once.
func _done(tid: int) -> bool:
	if _waited.has(tid):
		return false
	if not WorkerThreadPool.is_task_completed(tid):
		return false
	WorkerThreadPool.wait_for_task_completion(tid)
	_waited[tid] = true
	if _waited.size() > 4096:
		_waited.clear()      # generation wrap; old ids cannot come back before this
	return true


func _lost_task(what: String) -> void:
	_lost_tasks += 1
	if _lost_tasks == 1 or _lost_tasks % 100 == 0:
		push_error("[GrassMaps] worker task lost (%d so far): %s" % [_lost_tasks, what])


func _q_keep(loc: Vector2i, img: Image) -> void:
	_q_images[loc] = img
	_q_order.erase(loc)
	_q_order.append(loc)
	while _q_order.size() > QUERY_REGIONS:
		_q_images.erase(_q_order.pop_front())

## Every frame (GrassBlades): the streamed maps that finished loading get a free layer. A map loaded meanwhile on the
## main thread (painting, saving) wins; a region that streamed out before its map arrived is skipped; a region without
## a file gets nothing (NEUTRAL: no image, no layer, nothing sent).
func poll() -> void:
	_retired = null
	for loc in _pending.keys():
		var tid: int = _pending[loc][0]
		if not _done(tid):
			continue
		var img: Image = _pending[loc][1][0]
		_pending.erase(loc)
		if layer_of(loc) < 0 or _tex == null:
			continue
		if _images.has(loc):
			if not _mapped.has(loc) or _map_layer.has(loc):
				continue                   # held already: in its layer, or a NEUTRAL stand-in not painted yet
			img = _images[loc]             # loaded meanwhile on the main thread: that one, still to be placed
		else:
			img = _checked(img, loc)
			if img == null:
				continue
			if keep_images:
				_images[loc] = img
				_mapped[loc] = true
		_place(loc, img)
		changed.emit()


## Streamed maps still loading.
func pending() -> int:
	return _pending.size()


func _start_load(p_loc: Vector2i) -> void:
	if _pending.has(p_loc):
		return
	var box := [null]
	var path := path_for(p_loc)                   # read here: the worker touches no node
	var tid := WorkerThreadPool.add_task(func() -> void: box[0] = GrassMaps._read_path(path))
	_pending[p_loc] = [tid, box]


func _notification(p_what: int) -> void:
	if p_what == NOTIFICATION_PREDELETE:
		for p in _pending.values():
			if not _waited.has(p[0]):
				WorkerThreadPool.wait_for_task_completion(p[0])
		for p in _q_pending.values():
			if not _waited.has(p[0]):
				WorkerThreadPool.wait_for_task_completion(p[0])


## Every wanted region not yet held, loaded on the worker threads (a large map loads a hundred files or more): the
## ones with a file are held as maps, the others hold nothing (NEUTRAL).
func _load_all(p_want: Array) -> void:
	var locs := p_want.filter(func(l): return l != null and not _images.has(l))
	if locs.is_empty():
		return
	var paths := locs.map(func(l): return path_for(l))      # read here: the workers touch no node
	var out: Array = []
	out.resize(locs.size())
	var tid := WorkerThreadPool.add_group_task(func(i: int) -> void: out[i] = GrassMaps._read_path(paths[i]), locs.size())
	if tid < 0:
		_lost_task("add_group_task refused the bulk load (%d regions); reading them synchronously" % locs.size())
		for i in locs.size():
			out[i] = _read_path(paths[i])
	else:
		WorkerThreadPool.wait_for_group_task_completion(tid)
	for i in locs.size():
		var img := _checked(out[i], locs[i])
		if img != null:
			_images[locs[i]] = img
			_mapped[locs[i]] = true


## A map read on the main thread (the editor's image() of a region not held yet): counted in sync_loads. A region
## without a file gets a new NEUTRAL image to paint, which is no map (no layer) until painted (update_layer).
func _load(p_loc: Vector2i) -> Image:
	sync_loads += 1
	var img := _checked(_read_path(path_for(p_loc)), p_loc)
	if img == null:
		return _neutral()
	_mapped[p_loc] = true
	return img


## A file's Image, or null (no file). Static: a worker thread calls it with a path read on the main thread.
static func _read_path(p_path: String) -> Image:
	if p_path == "" or not FileAccess.file_exists(p_path):
		return null
	return ResourceLoader.load(p_path, "Image", ResourceLoader.CACHE_MODE_IGNORE) as Image


## Null for none (no file); RGBA8 at region_size², converting (with an error) what is not.
func _checked(p_img: Image, p_loc: Vector2i) -> Image:
	if p_img == null:
		return null
	var img := p_img
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != _size or img.get_height() != _size:
		errors.append("%s is %dx%d, not %d²: resized" % [path_for(p_loc), img.get_width(), img.get_height(), _size])
		push_error("[GrassMaps] " + errors[errors.size() - 1])
		img.resize(_size, _size, Image.INTERPOLATE_NEAREST)
	return img


## A new region-sized NEUTRAL image: the editor's map of a region without a file, to paint. The only one made: no layer
## is ever filled with NEUTRAL (the shaders read the constant).
func _neutral() -> Image:
	var img := Image.create_empty(maxi(_size, 1), maxi(_size, 1), false, Image.FORMAT_RGBA8)
	img.fill(NEUTRAL)
	return img


## The array while no map is resident: one NEUTRAL texel no slot points at (a sampler needs a texture to bind).
static func _placeholder() -> Image:
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(NEUTRAL)
	return img


## The game keeps no images after uploading them (VRAM only); adopted ones stay (tests, tools).
func _forget() -> void:
	if keep_images:
		return
	for loc in _images.keys():
		if not _adopted.has(loc):
			_images.erase(loc)
			_mapped.erase(loc)
