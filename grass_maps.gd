# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassMaps
extends RefCounted
## The grass maps: one RGBA8 image per Terrain3D region (GrassMapCodec), stored beside the region files
## (<data_directory>/<folder>/<Terrain3DUtil.location_to_filename(loc)>) and held here as
## one Texture2DArray whose layers follow Terrain3D's own (the region map's value - 1, with or without streaming): the
## blade and decoration compute and the far carpet read it. A region without a file grows the ground's grass (NEUTRAL).
## Owned by GrassBlades. The grass keeps its maps itself, so it runs on any Terrain3D.

signal changed                     # the texture was rebuilt, or a layer updated

const NEUTRAL := Color(128.0 / 255.0, 0.0, 128.0 / 255.0, 1.0)   # x1, the ground decides, the authored height, not forced
const MAP_SIZE := 32               # Terrain3D's region map: MAP_SIZE^2 cells (REGION_MAP_SIZE)
const QUERY_REGIONS := 8           # region maps kept for GrassBlades.sample() (the game holds none of its own)

var folder := "grass"
var keep_images := false           # the editor keeps each region's Image (painting, picking, saving)
var editor := false                # streaming follows the editor's own switch
var errors: PackedStringArray = []
var sync_loads := 0                # maps decoded on the main thread: a streamed region's never is
var _terrain: Object = null
var _tex: Texture2DArray = null
var _layers: Array = []            # layer -> region location, or null (an unused streaming slot)
var _images := {}                  # location -> Image (keep_images; adopted ones always)
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


func layer_of(p_loc: Vector2i) -> int:
	return _layers.find(p_loc)


## layer -> region location for Terrain3D's region map (MAP_SIZE^2 cells, value = layer + 1), its window at `origin`: the
## inverse of grass_place_common.glsli vertex_texel.
static func layout(p_map: PackedInt32Array, p_origin: Vector2i) -> Dictionary:
	var out := {}
	for i in p_map.size():
		var v := p_map[i]
		if v > 0:
			out[v - 1] = Vector2i(i % MAP_SIZE, i / MAP_SIZE) - Vector2i(MAP_SIZE / 2, MAP_SIZE / 2) + p_origin
	return out


## Re-reads the region map: a new layer count (or `force`) rebuilds the texture, loading every map on the worker pool and
## waiting; a layer whose region changed (streaming) shows NEUTRAL while its map loads on a worker thread (poll()).
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
	if n == 0:
		_tex = null
		_layers = []
		changed.emit()
		return
	if p_force or _tex == null or n != _layers.size():
		_load_all(want)
		var imgs: Array[Image] = []
		for loc in want:
			imgs.append(_image_or_neutral(loc))
		_tex = Texture2DArray.new()
		_tex.create_from_images(imgs)
		_layers = want
		_forget()
		changed.emit()
		return
	var any := false
	for i in n:
		if want[i] != _layers[i]:
			_layers[i] = want[i]
			if want[i] != null and not _images.has(want[i]):
				_start_load(want[i])        # read on a worker thread; NEUTRAL until poll() lands it
			_tex.update_layer(_held_or_neutral(want[i]), i)
			any = true
	if any:
		_forget()
		changed.emit()


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


## A region's map in the editor (kept): its file's, adopted, or a new NEUTRAL one.
func image(p_loc: Vector2i) -> Image:
	if not _images.has(p_loc):
		_images[p_loc] = _load(p_loc)
	return _images[p_loc]


## Tests and tools: this image IS the region's map (no file is read for it); its layer updates now if mapped.
func adopt(p_loc: Vector2i, p_img: Image) -> void:
	var img := p_img
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	_images[p_loc] = img
	_adopted[p_loc] = true
	update_layer(p_loc)


## Re-sends a region's layer from its image (after painting).
func update_layer(p_loc: Vector2i) -> void:
	var i := layer_of(p_loc)
	if i >= 0 and _tex != null:
		_tex.update_layer(_image_or_neutral(p_loc), i)
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

## Every frame (GrassBlades): the streamed maps that finished loading reach their layers. A map loaded meanwhile on the
## main thread (painting, saving) wins; a region that streamed out before its map arrived is skipped.
func poll() -> void:
	for loc in _pending.keys():
		var tid: int = _pending[loc][0]
		if not _done(tid):
			continue
		var img: Image = _pending[loc][1][0]
		_pending.erase(loc)
		var i := layer_of(loc)
		if _images.has(loc) or i < 0 or _tex == null:
			continue
		img = _checked(img, loc)
		_tex.update_layer(img, i)
		if keep_images:
			_images[loc] = img
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


func _image_or_neutral(p_loc) -> Image:
	if p_loc == null:
		return _neutral()
	if not _images.has(p_loc):
		_images[p_loc] = _load(p_loc)
	return _images[p_loc]


## A held map or NEUTRAL; never reads a file (the streaming path).
func _held_or_neutral(p_loc) -> Image:
	return _images[p_loc] if p_loc != null and _images.has(p_loc) else _neutral()


## Every wanted region not yet held, loaded on the worker threads (a large map loads a hundred files or more).
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
			_images[locs[i]] = _checked(_read_path(paths[i]), locs[i])
		return
	WorkerThreadPool.wait_for_group_task_completion(tid)
	for i in locs.size():
		_images[locs[i]] = _checked(out[i], locs[i])


## A map read on the main thread (the editor's image() of a region not held yet): counted in sync_loads.
func _load(p_loc: Vector2i) -> Image:
	sync_loads += 1
	return _checked(_read_path(path_for(p_loc)), p_loc)


## A file's Image, or null (no file). Static: a worker thread calls it with a path read on the main thread.
static func _read_path(p_path: String) -> Image:
	if p_path == "" or not FileAccess.file_exists(p_path):
		return null
	return ResourceLoader.load(p_path, "Image", ResourceLoader.CACHE_MODE_IGNORE) as Image


## NEUTRAL for none; RGBA8 at region_size², converting (with an error) what is not.
func _checked(p_img: Image, p_loc: Vector2i) -> Image:
	if p_img == null:
		return _neutral()
	var img := p_img
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != _size or img.get_height() != _size:
		errors.append("%s is %dx%d, not %d²: resized" % [path_for(p_loc), img.get_width(), img.get_height(), _size])
		push_error("[GrassMaps] " + errors[errors.size() - 1])
		img.resize(_size, _size, Image.INTERPOLATE_NEAREST)
	return img


func _neutral() -> Image:
	var img := Image.create_empty(maxi(_size, 1), maxi(_size, 1), false, Image.FORMAT_RGBA8)
	img.fill(NEUTRAL)
	return img


## The game keeps no images after uploading them (VRAM only); adopted ones stay (tests, tools).
func _forget() -> void:
	if keep_images:
		return
	for loc in _images.keys():
		if not _adopted.has(loc):
			_images.erase(loc)
