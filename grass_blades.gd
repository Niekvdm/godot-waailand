# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@icon("res://addons/waailand/grass_blades_icon.svg")
@tool
class_name GrassBlades
extends Node3D
## GPU-driven grass blades. Each frame, blade_place.glsl turns the world grid cells around the
## camera into blade instances in three INDIRECT MultiMeshes (HIGH, LOW, SHADOW) and
## blade_finalize.glsl writes their draw counts. Nothing per blade runs on the CPU. The ground is
## Terrain3D's (its height and control arrays and its region map) and the grass maps are the
## addon's own (GrassMaps), all bound into both kernels.
##
## Indirect MultiMesh rules (from Godot 4.8's source): allocate(use_indirect) THEN set_mesh (only
## set_mesh creates the command buffer); a custom AABB every frame (without one the field is culled
## as a point at the origin); compute writes only command word 1; NEVER call the CPU-side MultiMesh
## API on these: per-instance accessors zero the buffer, and set_visible_instances(-1) writes
## 0xFFFFFFFF instances.

enum ShadowMode { NONE, SHADOW_BIN, HIGH_CASTS }

## The placement kernel.
const PLACE_SHADER := "res://addons/waailand/blade_place.glsl"
## The kernel that turns a frame's counts into the draw commands.
const FINALIZE_SHADER := "res://addons/waailand/blade_finalize.glsl"
## The params buffer's size in vec4s (P.v in grass_place_common.glsli).
const PARAM_VEC4 := 24
## Grid cells per side of one compute tile (one workgroup).
const TILE_CELLS := 16
## Floats per blade instance in the MultiMesh buffers.
const STRIDE := 20
## A feeder's process priority: just before the blades (1000), which dispatch after everything that moves the camera.
const FEED_PRIORITY := 999
## Every GrassBlades is in this group (GrassBlades.active()).
const GROUP := &"grass_blades"
## The downwash slots the shaders have (grass_downwash.gdshaderinc MAX_WASH).
const MAX_WASH := 2
## A swell's keys and their values when set_sea is not told them.
const DEFAULT_SWELL := {"dir": Vector2(0.0, 1.0), "height": 0.0, "k": 0.037, "omega": 0.602, "phase": 0.0}

@export_group("Field")

## Density: metres between two placement grid cells — at most one blade grows per cell.
## 0.1 = up to 100 blades per square metre. Smaller values are denser and cost more.
## Live: applies from the next dispatch.
@export_range(0.01, 4.0, 0.005, "suffix:m") var grid_pitch := 0.1

## Reach: how far from the camera the blades grow, in metres. The single biggest perf
## lever — instance demand grows with the SQUARE of this. The quality tiers set it at
## runtime; the value here is what the editor preview and a game without a feeder use.
## Live: applies from the next dispatch.
@export_range(4.0, 2000.0, 1.0, "suffix:m") var radius := 120.0

## Edge fade: over the last this many metres of the radius the field thins out to none,
## so the boundary never reads as a hard line. Live: applies from the next dispatch.
@export_range(0.0, 500.0, 0.5, "suffix:m") var edge_fade_m := 20.0

## Growth blend: metres of camera travel over which a blade grows in or shrinks away
## when it crosses a density threshold, so none pops in or out. Live.

@export_range(0.0, 20.0, 0.1, "suffix:m") var grow_m := 2.0

@export_group("Distance LOD")

## The distance where blades begin MORPHING from the detailed near shape toward the
## sparse far shape. Must stay below the switch distance. Live: applies next dispatch.
@export_range(0.0, 200.0, 0.5, "suffix:m") var d_morph := 6.0

## The LOD switch: past this distance (m) blades leave the detailed HIGH bin and only
## the thinned LOW field continues. Live: applies from the next dispatch.
@export_range(1.0, 500.0, 0.5, "suffix:m") var d_switch := 10.0

## Past the LOD switch, this share (0..1) of blades is kept; the survivors widen to
## cover for the missing ones. Live: applies from the next dispatch.
@export_range(0.0, 1.0, 0.01) var k_lo := 0.25

## How much the surviving blades widen as the field thins: width x keep^-width_exp.
## 1 keeps the ground coverage exactly; below 1 lets the far field thin visually.
## Live: applies from the next dispatch.
@export_range(0.0, 4.0, 0.05) var width_exp := 1.0

@export_group("Far Carpet")

## Past the far-carpet start the field keeps thinning toward this share (0..1) of the
## blades. Active only when the carpet fits inside the radius minus the edge fade;
## otherwise it switches itself off. Live: applies from the next dispatch.
@export_range(0.0, 1.0, 0.005) var k_far := 0.03

## Where the far carpet's thinning begins (m from the camera). Live.
@export_range(0.0, 2000.0, 1.0, "suffix:m") var d_far0 := 25.0

## Where the far carpet reaches its thinnest (m from the camera). Live.
@export_range(0.0, 4000.0, 1.0, "suffix:m") var d_far1 := 90.0

## The most a thinned-out blade may widen, times its own width — keeps blades from
## becoming ribbons. Live: applies from the next dispatch.
@export_range(1.0, 200.0, 1.0) var width_cap := 50.0

@export_group("Placement")

## No blades grow on ground steeper than this many degrees.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var max_slope_deg := 55.0

## How far each blade's root sits below the ground surface (m), so no blade floats
## above a bump in the terrain between height samples.
@export_range(0.0, 1.0, 0.005, "suffix:m") var root_sink := 0.03

## The ground's species grow in patches of this size (m): each patch grows ONE species
## of its ground slot's mix, so fields read as mottled populations, not confetti.
## Live: applies from the next dispatch.
@export_range(0.5, 50.0, 0.5, "suffix:m") var species_patch_m := 3.0

## Skip tiles and blades outside the camera's view frustum. Off: the whole radius
## dispatches every frame (for reflections, shadow views and debugging).
@export var cull_frustum := true

## Gather blades into Voronoi clumps that share their height, lean and colour, pulled
## toward their clump centre — the field reads as tussocks instead of uniform confetti.
## Live: applies from the next dispatch.
@export var clumping := true

@export_group("Buffers")

## The near (HIGH) bin's capacity in blades. A frame's overflow is DROPPED and flagged
## in `stats` — blades vanish in bands that follow the camera's facing.
## BINDS WHEN THE GPU BUFFERS ARE ALLOCATED: set it before the scene runs
## (a quality tier carries its own); a mid-session edit does nothing.
@export var cap_hi := 196608

## The far (LOW) bin's capacity in blades — the big one; size it to the radius
## (about 850000 for a 220 m radius on dense ground). Same allocation rule as cap_hi.
@export var cap_lo := 196608

## The shadow ring's capacity in blades (SHADOW_BIN mode only). Same allocation rule.
@export var cap_shadow := 65536

@export_group("Shadows")

## Extra metres added to the view-frustum test, so blades just outside the view still
## cast their shadows into it. Live: applies from the next dispatch.
@export_range(0.0, 50.0, 0.1, "suffix:m") var shadow_margin := 1.5

## Which blades cast shadows: NONE — none; SHADOW_BIN — a dedicated, thinned and
## widened set of near blades drawn into the shadow map only; HIGH_CASTS — the detailed
## near blades themselves. Live: the setter re-applies the instance cast flags.
@export var shadow_mode: ShadowMode = ShadowMode.NONE:
	set(value):
		if shadow_mode == value:
			return
		shadow_mode = value
		if _live and is_inside_tree():
			set_shadow_mode(value)

## SHADOW_BIN only: how far from the camera (m) blades cast into the shadow map.
@export_range(1.0, 200.0, 1.0, "suffix:m") var shadow_radius := 10.0

## SHADOW_BIN only: the share (0..1) of blades that cast; the casters widen to keep
## the shadow's coverage.
@export_range(0.0, 1.0, 0.01) var shadow_keep := 0.35

@export_group("Terrain & Wind")

## The far field in the terrain shader under this terrain (GrassFarField): past the
## blades, the carpet's measured brightness and grain and the canopy's light, on the
## texture's own colour. Off: the terrain renders exactly as without grass. Live.
@export var far_field := true

## This map's ground-rules file (which species each ground slot grows). Empty reads
## the default location beside the scene, and no file at all means the shared growth
## table. Changing it re-reads the rules live.
@export_file("*.json") var ground_rules_path := "":
	set(value):
		ground_rules_path = value
		if is_inside_tree():
			reload_rules()

## How fast the grass turns toward a new wind direction (1/s): slow enough that a
## veering gust does not flick the blades. Live.
@export_range(0.05, 4.0, 0.05) var wind_veer_rate := 0.4

## The grass remembers the air (GrassAirField): a gust or a rotor's wash lays it with a
## lag, a released patch rebounds past upright once, and grass a hovering rotor held
## flat creeps back up over seconds. Off: every plant leans to the air it stands in
## now, at once. Live.
@export var air_memory := true:
	set(v):
		air_memory = v
		air.enabled = v

## How far a plant floating on inland water bobs up and down (m); plants on the sea
## move with its swell instead. Live.
@export_range(0.0, 0.2, 0.005, "suffix:m") var water_bob_m := 0.01

@export_group("System & Diagnostics")

## Attach the project's feeder children (wind, weather, trails, downwash, ruts, roads,
## season, sea, quality — GrassBladesConfig.runtime_inputs and editor_inputs). Applies
## when the node enters the tree; tests turn it off so live weather cannot skew a
## measured look.
@export var inputs := true

## Measure each dispatch: its GPU time (compute_ms) and its main-thread parts
## (cpu_split), readable through the debug_timing stats. Live.
@export var debug_timing := false

# The sea level in metres (set_sea). NaN means no sea: every point is dry land and the sea species never grow.
var _sea_level := NAN
# The dominant swell, for the surge (grass_blade.gdshader): the direction it travels, crest-to-trough height (m),
# wavenumber (rad/m), angular frequency (rad/s) and phase (rad, -omega x the ocean's clock).
var _swell := {"dir": Vector2(0.0, 1.0), "height": 0.0, "k": 0.037, "omega": 0.602, "phase": 0.0}
var _wind_target := Vector2.ZERO
var _wind_follow := false        # set_wind was called: ease wind.dir toward _wind_target every frame
var _washes: Array[Vector4] = [] # this frame's add_wash calls: (x, z, radius, intensity)
var _wash_sent := 0              # how many the last flush sent (0: nothing to clear)

## The camera the blades grow around. Unset: the viewport's camera (in the editor, the one Terrain3D follows).
var camera: Camera3D
## For tools and tests: stand in for the editor (Engine.is_editor_hint() is false in a test run). Read once, in _ready.
var force_editor := false
## For tools and tests: the editor preview's "grow on every ground" (GrassEditorPreview.all_grounds): every corner
## forced (placement flag 8, the far carpet's far_all_grounds). Never set in a game.
var all_grounds := false:
	set(v):
		all_grounds = v
		_far_dirty = true
var _editor := false
## For tools and tests: stop dispatching; the blades stay as the last frame placed them.
var frozen := false
## For tools and tests: every blade in this bin (0 HIGH, 1 LOW, 2 SHADOW); -1: by distance.
var force_bin := -1
## For tools and tests: every blade at this morph (0 HIGH .. 1 LOW); -1: by distance.
var force_morph := -1.0
## For tools and tests: every blade facing this yaw (rad); -1: its own.
var force_yaw := -1.0
## For tools and tests: the type rows (GrassTypes) the kernels and the blade material read.
var types := GrassTypes.new()
# The day of the year the grass shows (set_date; 0 = 1 Jan). Changing it re-applies the type accents (and the
# decorations' bloom) on the next dispatch. Defaults to 15 Feb, a quiet date with nothing in bloom, so a world that
# sets no date grows blades only.
var _day_of_year := 45.0:
	set(v):
		_day_of_year = fposmod(v, GrassSeason.YEAR)
		_season_dirty = true
var _season_dirty := true
## The trail field the kernels read (crush and push; add_crush and add_push stamp it). The advanced layer: tools
## may read its state.
var interaction := GrassInteractionField.new()
## The grass's memory of the air (air_memory): a spring per patch around the camera whose lag, rebound and matting the
## shaders add to their stateless lean. The advanced layer: tools may read it (readback's "air").
var air := GrassAirField.new()
var _air_tex_state: Texture2DRD
var _air_tex_eq: Texture2DRD
var _air_bound := false
var _wash_frame := PackedVector4Array()     # the washes the shaders got last (the air field's too)
var _air_calm_seen := 0                     # the wind's calm_serial the air field last settled for
## For tools and tests: the blade material (grass_blade.gdshader).
var material: ShaderMaterial = null
## The wind state the shaders read (set_wind eases it). The advanced layer: tools may read its uniforms, or calm
## it at once.
var wind := GrassWindState.new()
## For tools and tests: the decoration streams, the flowers, plumes and spikes on their host types.
var decorations := DecorationStreams.new()
## For tools and tests: the far field in the terrain shader (GrassFarField), fed and switched while this runs.
var farfield := GrassFarField.new()
var _far_grain := {}            # GrassFarGrain.load_baked(): {} = no current bake, no grain
var _far_dirty := true          # the far field's static inputs need a push
var _overlay := 0               # the paint overlay the far field draws (GrassOverlay.Mode; the editor preview only)
var _sun_travel := Vector3(0.0, -1.0, 0.0)
var _gust_tex: ImageTexture
var _colour_tex: Texture2DArray
## For tools and tests: the HIGH blade mesh.
var mesh_hi: ArrayMesh
## For tools and tests: the LOW blade mesh.
var mesh_lo: ArrayMesh
## With debug_timing: the last dispatch's GPU time (ms).
var compute_ms := 0.0
## With debug_timing: the last dispatch's main-thread time per part, µs (the bench reads it).
## "rt" is the RenderingDevice recording, which runs INLINE on the main thread when rendering is
## single-threaded (the project default).
var cpu_split := {}
## The last counts read back: the HIGH, LOW and SHADOW blades drawn, then a bit mask of the bins that overflowed.
var stats := PackedInt32Array([0, 0, 0, 0])
## Whether the blades are shown (set_grass_visible).
var grass_visible := true
## For tools and tests: the shadow-casting settings last applied to the three bins.
var applied_casts := {}

## The Terrain3D node whose arrays the blades read. Found up the parent chain if not set.
var terrain: Node = null
var _ground_rids := [RID(), RID(), RID(), RID(), RID()]   # the RS height / grass / rut / control / water maps last bound
## What grows on which terrain texture (the growth table, GrassBladesConfig.growth_path): resolved against the
## terrain's own assets into 32 allowances and 32 species mixes by texture id, uploaded after the type rows.
## Call refresh_growth() after replacing it.
var growth := GrassTerrainGrowth.new()
## The grass maps (GrassMaps): the painted density, species, height and force per region.
var grass_maps := GrassMaps.new()
## The surface layer's grass maps (GrassMaps, the same codec: density, species override, height, force), in
## <maps_folder>_water beside the ground's.
var water_maps := GrassMaps.new()
## The water maps' folder is the ground maps' with this after it.
const WATER_FOLDER_SUFFIX := "_water"
var _warned_side_maps := false
## The map's ground rules (null: the shared growth table). The file it loads is the
## `ground_rules_path` export in the Terrain & Wind group.
var rules: GrassGroundRules = null
## The map's season settings (the calendar without rules).
var season := GrassSeasonPlan.new()
var _allow := PackedFloat32Array()
var _mix := PackedByteArray()
## The compute's type bytes and the blade material's per-type arrays are rebuilt only when something
## marks them (types_changed: new growth or colours, a season step, a test editing rows). The compute's copy goes
## out until the render thread confirms it
## (GrassUploadGate): a frame that returns before its upload sends it again. Likewise the wind, sea and
## edge uniforms go out only when they change.
var _types_up := GrassUploadGate.new()
var _types_bytes := PackedByteArray()
var _types_bytes_gen := 0        # the generation _types_bytes was packed from
var _types_mat_gen := 0          # the generation the blade material's arrays were set from
var _species_gen := GrassSpeciesCatalog.generation   # the active set `types` was built from (reload_species)
var _sent := {}                  # uniform -> the value last sent (the blade material, and the flowers')
var _slot_mixes := []            # per texture id {type slot: weight}: the far field's per-slot table
var _mix_f := PackedFloat32Array()   # _mix as floats, for the query
var _road_pack := {}                # the road pack last sent to the GPU (the query judges the same shapes)
var _query := GrassQuery.new()
var _height_type := 0               # Terrain3DRegion.TYPE_HEIGHT, looked up (no native constant is named here)
## The ground's colour under each blade: the blade material reads Terrain3D's region map,
## control and albedo arrays and slot tints, pushed when any of them changes.
var _ground_dirty := true
var _colour_rids := [RID(), RID()]      # the control and albedo arrays last pushed to the blade material
var _region_map_dirty := true
var _region_buf := RID()
## The region map's size in bytes (32 x 32 ints).
const REGION_MAP_BYTES := 32 * 32 * 4
## The live roads (GrassRoads): the kernels keep grass off them and grow verges beside them.
var roads := GrassRoads.new()
## The live water sources (GrassWater): the species measure their depth below the highest surface over them, and the
## surface layer floats on them.
var water := GrassWater.new()
## Floating roots sit this far above their surface (m), clear of the water's own mesh.
const SURFACE_LIFT_M := 0.01
var _water_dirty := true
var _water_origin := Vector2(INF, INF)
var _water_rev := -2
var _water_count := 0
var _water_pack := {}              # the water pack last sent to the GPU (the query and water_surface read the same)
var _water_index := {}             # lower-case water kind -> index (the growth table's water section)
var _sea_kind := -1                # the sea's water kind (GrassWater.SEA_KIND), -1: none
var _water_bytes := PackedByteArray()   # GrassTerrainGrowth.water_bytes: T.v[424..487]
var _clock := 0.0                  # seconds, wrapped every hour: the floating plants' bob
## The compute-state check in _rt_frame reports the TRANSITION into "broken" once and
## disables the grass — a mid-session rebuild can break state that was fine at the first
## frame (2026-09-27's world-entry spam did exactly that), so the check runs every frame.
var _was_broken := false
## Debug: print a marker per dispatched frame, to correlate the renderer's C++ error
## bursts with GrassBlades' compute list (or prove they belong to someone else).
@export var debug_dispatch_marker := false
## Wake DirectionalLight3D CONTACT shadows for the blades (Godot 4.8): the project's
## input feeder routes this to the world's active light (sun by day, moon by night, via
## SkyLightResolver) and clamps the quality mode to the engine's valid range. In
## 4.8-dev6 the pass initializes in a running game but renders nothing (editor viewport
## only) — the toggle is live and harmless, ready for a build that renders it.
## Editor-only: the wind speed (m/s) the preview grass answers to. The game's wind
## comes from the weather system; the editor has none, so this stands in for it.
## 0 = still air (the blades freeze). Live in the inspector.
@export_group("Editor Wind")
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var editor_wind_speed := 4.0:
	set(value):
		editor_wind_speed = value
		if _editor:
			apply_editor_wind()

@export_group("Contact Shadows")
@export var contact_shadows := false
## The engine's precompiled quality variant: 0 SHORT / 1 NORMAL / 2 LONG (32/64/128
## samples). Values above 2 are OUT OF RANGE and break the pass — the 2026-09-27 spam.
@export_range(0, 2, 1) var contact_shadow_mode := 2
## Bisection switches for a renderer-side null-pipeline spam inside this node's compute
## list (bind null -> push-constant size -> dispatch-no-pipeline, once per frame): turn
## ONE off at a time in the inspector; the switch whose flip stops the spam names the
## failing stage. Each guard is the stage's own validity check, so this is safe to leave on.
@export var debug_skip_interaction := false
@export var debug_skip_deco := false
@export var debug_skip_surface_layer := false
var _water_idx := RID()
var _water_shapes := RID()
var _road_origin := Vector2(INF, INF)
var _road_count := 0
var _road_dirty := true
var _road_idx := RID()
var _road_shapes := RID()
var _dummy_rut: ImageTexture
var _rut_tex := RID()             # RS texture: set_ruts's, or the 1x1 dummy
var _rut_texture: Texture2D       # held: an RID alone does not keep the texture alive
var _rut := Vector4(0.0, 0.0, 150.0, 0.05)
var _rut_on := false
var _live := false
var _tiles := 1

# Render-thread state
var _rd: RenderingDevice
var _place_shader := RID()
var _place_pipe := RID()
var _fin_shader := RID()
var _fin_pipe := RID()
var _params := RID()
var _types_buf := RID()
var _counters := RID()
var _stats_buf := RID()
var _sampler := RID()
var _field_tex := RID()
var _place_set := RID()
var _fin_set := RID()
var _mm: Array[RID] = []
var _inst: Array[RID] = []
var _dst: Array[RID] = []
var _cmd: Array[RID] = []
var _ts_a := ""
var _ts_b := ""


## For tools and tests: the gust texture the wind shaders sample.
func gust_texture() -> ImageTexture:
	return _gust_tex


func _init() -> void:
	add_to_group(GROUP)
	_query.texel = grass_maps.query_texel
	_query.water_texel = water_maps.query_texel
	_query.pending = grass_maps.query_pending
	_query.control = _ground_control
	_query.height = _ground_height
	_query.deco_state = _deco_state
	_height_type = ClassDB.class_get_integer_constant(&"Terrain3DRegion", &"TYPE_HEIGHT")


## The blade colour array (GrassColour), built from `types` on first use. Call
## refresh_colours() after changing a row's colours.
func colour_texture() -> Texture2DArray:
	if _colour_tex == null:
		_colour_tex = GrassColour.build(types)
	return _colour_tex


## The project's active species changed (the Species dialog): the type rows, the flowers and their streams, the
## colours and the growth tables are built again from the config's catalog, and in the tree the GPU side with them.
## The editor calls it; a game loads its set once.
func reload_species() -> void:
	if _live:
		_live = false
		_unbind_air()
		RenderingServer.call_on_render_thread(_rt_free.bind(decorations))
	_rebuild_species()
	if is_inside_tree():
		_ready()


## The species side of reload_species (the GPU side is _ready's): the rows, the flowers' streams, the colours, and the
## growth read again, since its names grow only while active.
func _rebuild_species() -> void:
	_species_gen = GrassSpeciesCatalog.generation
	types = GrassTypes.new()
	decorations = DecorationStreams.new()
	growth = GrassTerrainGrowth.from_rules(rules) if rules != null else GrassTerrainGrowth.new()
	_colour_tex = null
	_season_dirty = true
	_types_up.mark()
	if material != null:
		material.set_shader_parameter("colour_tex", colour_texture())
		material.set_shader_parameter("type_mean_luma", GrassColour.mean_luma(types))


## Call after editing `types` rows directly: the type tables are rebuilt and re-sent on the next dispatch.
func types_changed() -> void:
	_types_up.mark()


## Rebuilds the blade colour array from `types`, after a row's colours changed.
func refresh_colours() -> void:
	_far_dirty = true
	_types_up.mark()
	_colour_tex = GrassColour.build(types)
	set_uniform(&"colour_tex", _colour_tex)
	if material != null:
		material.set_shader_parameter("type_mean_luma", GrassColour.mean_luma(types))


## Whether the blades run: the kernels and buffers are built and the terrain is bound.
func is_live() -> bool:
	return _live


func _ready() -> void:
	# ONE flag decides every editor branch, so no fix can sit behind a scattered is_editor_hint() gate that the
	# editor never reaches.
	_editor = force_editor or Engine.is_editor_hint()
	if _species_gen != GrassSpeciesCatalog.generation:
		_rebuild_species()        # the active set changed while this scene was in a background tab
	farfield.direct = _editor         # the editor's far field never writes the terrain material's saved table
	if not _editor:
		process_priority = 1000     # after anything that moves the camera this frame (the editor's camera is
		                            # no node, and a stored priority would land in the saved scene)
	# Re-entry: prepare() below builds new decoration materials (the uniform cache would skip them) and
	# _rt_init new buffers (the type rows and the season must go up again).
	_sent.clear()
	_season_dirty = true
	_types_up.mark()
	mesh_hi = BladeMesh.build(BladeMesh.HIGH_PAIRS, BladeMesh.GAMMA)
	mesh_lo = BladeMesh.build(BladeMesh.LOW_PAIRS, BladeMesh.GAMMA)
	_ts_a = "grass_a_%d" % get_instance_id()
	_ts_b = "grass_b_%d" % get_instance_id()
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load("res://addons/waailand/grass_blade.gdshader")
		var lv := BladeMesh.levels(BladeMesh.LOW_PAIRS, BladeMesh.GAMMA)
		material.set_shader_parameter("lo_u1", lv[1])
		material.set_shader_parameter("lo_u2", lv[2])
		material.set_shader_parameter("colour_tex", colour_texture())
		material.set_shader_parameter("type_mean_luma", GrassColour.mean_luma(types))
	var fn := FastNoiseLite.new()
	fn.seed = 1337
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	var gimg := fn.get_seamless_image(256, 256, false, false, 0.1, true)
	gimg.generate_mipmaps()
	_gust_tex = ImageTexture.create_from_image(gimg)
	material.set_shader_parameter("gust_tex", _gust_tex)
	if terrain == null:
		terrain = _find_terrain()
	if terrain == null:
		push_error("GrassBlades: no Terrain3D above this node and none assigned")
		return
	var data: Object = terrain.get("data")
	if data != null and not data.is_connected("region_map_changed", _on_region_map_changed):
		data.connect("region_map_changed", _on_region_map_changed)
	grass_maps.folder = GrassBladesConfig.current().maps_folder
	grass_maps.editor = _editor
	grass_maps.keep_images = _editor
	if not grass_maps.changed.is_connected(_on_grass_maps_changed):
		grass_maps.changed.connect(_on_grass_maps_changed)
	grass_maps.scene_path = owner.scene_file_path if owner != null else ""
	grass_maps.bind(terrain)
	water_maps.folder = water_folder(grass_maps.folder)
	water_maps.editor = _editor
	water_maps.keep_images = _editor
	water_maps.scene_path = grass_maps.scene_path
	water_maps.bind(terrain)
	if terrain.get("side_maps_enabled") == true and not _warned_side_maps:
		_warned_side_maps = true
		push_warning("GrassBlades: the terrain still loads its side maps (side_maps_enabled), but the grass reads its "
			+ "own maps: switch side_maps_enabled off on the Terrain3D node to free that memory.")
	if terrain.has_signal("assets_changed") and not terrain.is_connected("assets_changed", refresh_growth):
		terrain.connect("assets_changed", refresh_growth)
	if terrain.has_signal("assets_changed") and not terrain.is_connected("assets_changed", _on_ground_changed):
		terrain.connect("assets_changed", _on_ground_changed)
	_load_rules(false)
	refresh_growth()
	var place_f = load(PLACE_SHADER)
	var fin_f = load(FINALIZE_SHADER)
	if not (place_f is RDShaderFile) or not (fin_f is RDShaderFile):
		push_error("GrassBlades: compute shaders did not import as RDShaderFile")
		return
	decorations.prepare(types)
	# The flowers read the gust field too (wind_gust, wind_dir_at): without it they sampled an unset texture and
	# every flower leaned at a full gust, 0.9 rad off the wind (2026-09-28).
	for m in decorations.materials:
		m.set_shader_parameter("gust_tex", _gust_tex)
	_dummy_rut = ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBAH))
	_rut_tex = _dummy_rut.get_rid()
	RenderingServer.call_on_render_thread(_rt_init.bind(place_f, fin_f, get_world_3d().scenario))
	if inputs:
		var cfg := GrassBladesConfig.current()
		if not _editor:
			_attach_inputs(cfg.runtime_inputs)     # the game's feeders (weather, trails, ruts, quality), never the editor's
		_attach_inputs(cfg.editor_inputs)
	_far_grain = GrassFarGrain.load_baked()


func _find_terrain() -> Node:
	var n := get_parent()
	while n != null:
		if n.get_class() == "Terrain3D":
			return n
		n = n.get_parent()
	return null


## The rules file for a map scene: `override`, else <grounds_dir>/<scene name>.json; "" without a scene or a dir.
static func rules_path_for(scene_path: String, grounds_dir: String, override: String) -> String:
	if override != "":
		return override
	if scene_path == "" or grounds_dir == "":
		return ""
	return grounds_dir.path_join(scene_path.get_file().get_basename() + ".json")


## The ground rules file this node reads: rules_path_for with its own scene.
func rules_path() -> String:
	return rules_path_for(owner.scene_file_path if owner != null else "", GrassBladesConfig.current().grounds_dir,
		ground_rules_path)


## Re-reads the map's rules (the Ground rules dialog calls it after each save): the growth table and the season
## plan. A map without a file goes back to the shared table.
func reload_rules() -> void:
	_load_rules(true)


## `always`: replace the growth table even without a file (reload_rules). At _ready only a file replaces it, so a
## growth table a test or tool set is kept.
func _load_rules(always: bool) -> void:
	var p := rules_path()
	rules = GrassGroundRules.load_file(p) if p != "" else null
	if rules != null:
		growth = GrassTerrainGrowth.from_rules(rules)
	elif always:
		growth = GrassTerrainGrowth.new()
	if rules != null:
		season = GrassSeasonPlan.from_rules(rules)
	elif always:
		season = GrassSeasonPlan.new()
	_season_dirty = true
	if terrain != null and always:
		refresh_growth()


## The config's feeders as children: one per script, unless a child already runs it (a scene may hold its
## own). Added without an owner, so a saved scene never carries them.
func _attach_inputs(scripts: Array[Script]) -> void:
	for s in scripts:
		if s == null:
			continue
		var has := false
		for c in get_children():
			has = has or c.get_script() == s
		if has:
			continue
		var n: Node = s.new()
		var nm := String(s.get_global_name())
		n.name = nm if nm != "" else "Input"
		add_child(n)


## Whether this runs as the editor's preview.
func is_editor_mode() -> bool:
	return _editor


## The input API. State: a later call replaces an earlier one. Events (add_*): every caller's add up within a frame
## and clear with it. The date and the sea are read back with get_day_of_year, get_sea_level and get_swell; wind and
## interaction stay public objects, the advanced layer tools reach into.

## The wind the grass follows: its direction (a zero vector: the default direction) and speed. The lean, gust and sway
## ease toward the speed's tuning in ~0.3 s (GrassWindState.for_speed); the direction eases toward the new one at
## wind_veer_rate. `instant` lands both at once. To still the grass completely (a picture, a bake), call wind.calm()
## after it: the grass stays still until the next set_wind.
func set_wind(direction: Vector2, speed_m_s: float, instant := false) -> void:
	var p := GrassWindState.for_speed(speed_m_s)
	wind.speed = p["speed"]
	# The lean/sway/comb TUNING eases (in _ease_wind) instead of landing at once: a
	# per-frame feeder (the weather sim's speed flutters slightly every frame) used to
	# STEP the whole field's tuning, and every blade mid-bend snapped to the new
	# equilibrium — the 2026-09-27 editor-preview "snap". The scroll rate still applies
	# at once: the scroll is integrated, so a rate change moves nothing retroactively.
	wind.set_tuning(p, instant)
	_wind_target = direction.normalized() if direction.length_squared() > 0.0 else GrassWindState.default_dir()
	_wind_follow = true
	if instant:
		wind.dir = _wind_target
		wind.honami_vel = wind.dir * wind.speed


## The date the grass shows (0 = 1 January). Nothing happens when it is unchanged, so a feeder may call it every frame
## (a new day re-applies the type tables and the flower palettes).
func set_date(p_day_of_year: float) -> void:
	var d := fposmod(p_day_of_year, GrassSeason.YEAR)
	if d != _day_of_year:
		_day_of_year = d


## How wet the grass is and how much snow lies on it, 0..1 each.
func set_weather(wetness: float, snow: float) -> void:
	set_uniform(&"weather_wetness", clampf(wetness, 0.0, 1.0))
	set_uniform(&"snow_coverage", clampf(snow, 0.0, 1.0))


## The sea level (NAN: no sea; every depth is dry land) and its dominant swell: `p_swell` takes the keys of
## DEFAULT_SWELL (the direction it travels, crest-to-trough height m, wavenumber rad/m, angular frequency rad/s and
## phase rad); a missing key takes its default.
func set_sea(level: float, p_swell := {}) -> void:
	_sea_level = level
	for k in DEFAULT_SWELL:
		_swell[k] = p_swell.get(k, DEFAULT_SWELL[k])
	var d: Vector2 = _swell["dir"]
	_swell["dir"] = d.normalized() if d.length() > 1e-6 else Vector2(0.0, 1.0)


## The date the grass shows (0 = 1 January).
func get_day_of_year() -> float:
	return _day_of_year


## The sea level (m; NAN: no sea).
func get_sea_level() -> float:
	return _sea_level


## The swell set_sea last gave (a copy: DEFAULT_SWELL's keys).
func get_swell() -> Dictionary:
	return _swell.duplicate()


## Flattens the grass along a capsule from `from` to `to` (a tyre), laying it along `direction`.
func add_crush(from: Vector3, to: Vector3, p_radius: float, strength := 1.0, direction := Vector2.ZERO) -> void:
	interaction.add_capsule(from, to, p_radius, GrassInteractionField.KIND_CRUSH, strength, direction)


## Bends the grass away from a capsule (a body, a foot); along `direction` when given.
func add_push(from: Vector3, to: Vector3, p_radius: float, strength := 1.0, direction := Vector2.ZERO) -> void:
	interaction.add_capsule(from, to, p_radius, GrassInteractionField.KIND_PUSH, strength, direction)


## How far from the camera a crush or push still lands (m): the interaction field's half width.
func interaction_reach() -> float:
	return interaction.size_px * interaction.texel_m * 0.5


## What grows at a point on the ground: GrassQuery over this grass's live inputs. Empty (nothing grows) without a terrain.
func sample(p_position: Vector3) -> GrassSample:
	if terrain == null or terrain.get("data") == null:
		return GrassSample.new()
	_query.types = types
	_query.kinds = decorations.kinds
	_query.allow = _allow
	_query.mix = _mix_f
	_query.sea_level = _sea_level
	_query.species_patch_m = species_patch_m
	_query.all_grounds = all_grounds
	_query.spacing = float(terrain.get("vertex_spacing"))
	_query.max_slope_cos = cos(deg_to_rad(max_slope_deg))
	_query.road_pack = _road_pack
	_query.road_origin = _road_origin
	_query.water_pack = _water_pack
	_query.water_origin = _water_origin
	_query.sea_kind = _sea_kind
	return _query.sample(p_position)


func _ground_control(v: Vector2i) -> int:
	var s := float(terrain.get("vertex_spacing"))
	return int(terrain.get("data").call("get_control", Vector3(v.x * s, 0.0, v.y * s)))


## A vertex's height (the raw height map, as the kernel reads it); NAN where its region is not loaded.
func _ground_height(v: Vector2i) -> float:
	var data: Object = terrain.get("data")
	var rs := int(terrain.get("region_size"))
	if not bool(data.call("has_region", Vector2i(floori(float(v.x) / rs), floori(float(v.y) / rs)))):
		return NAN
	var s := float(terrain.get("vertex_spacing"))
	return (data.call("get_pixel", _height_type, Vector3(v.x * s, 0.0, v.y * s)) as Color).r


func _deco_state(i: int) -> Vector2:
	return decorations.state(i) if i < decorations._state.size() else Vector2.ZERO


## A rotor's downwash over `p_position` this frame: its footprint's radius at the ground (m) and intensity (0..1). The
## shaders have MAX_WASH slots: the frame's strongest are kept, in the order they came.
func add_wash(p_position: Vector3, p_radius: float, intensity: float) -> void:
	_washes.append(Vector4(p_position.x, p_position.z, p_radius, intensity))


## The scene tree's first GrassBlades (in the game the one grass; in the editor the edited scene's), or null.
static func active() -> GrassBlades:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(GROUP) as GrassBlades if tree != null else null


## Every frame, before the dispatch: the wind turns toward its target and the tuning
## eases toward its own (a low-pass — per-frame feeder flutter becomes a smooth drift).
func _ease_wind(dt: float) -> void:
	if _wind_follow:
		wind.dir = wind.dir.slerp(_wind_target, 1.0 - exp(-dt * wind_veer_rate)).normalized()
	wind.ease_tuning(dt)


## The editor's preview wind: re-apply the exported speed, keeping the current direction.
## No-op in a game (the weather owns the wind there).
func apply_editor_wind() -> void:
	if not _editor:
		return
	var dir := wind.dir if wind.dir.length_squared() > 0.000001 else GrassWindState.default_dir()
	set_wind(dir, editor_wind_speed)


## Every frame: the washes added since the last frame go to the shaders. Nothing is written when no one adds washes,
## so a test that sets the wash uniforms itself keeps them.
func _flush_washes() -> void:
	if _washes.is_empty() and _wash_sent == 0:
		_wash_frame = PackedVector4Array()
		return
	var keep: Array[Vector4] = _washes.duplicate()
	if keep.size() > MAX_WASH:
		var order := range(keep.size())
		order.sort_custom(func(a: int, b: int) -> bool: return _washes[a].w > _washes[b].w)
		var top := order.slice(0, MAX_WASH)
		top.sort()
		keep.clear()
		for i in top:
			keep.append(_washes[i])
	_wash_frame = PackedVector4Array(keep)
	set_uniform(&"wash", _wash_frame)
	set_uniform(&"wash_count", keep.size())
	_wash_sent = keep.size()
	_washes.clear()


## Re-resolve the growth table against the terrain's current assets (names -> texture ids).
## Terrain3D's free_editor_textures (on by default) EMPTIES the assets' texture list at the terrain's
## READY in a running game, and the table is keyed by slot name: resolved after that, every slot gets
## the default (grass on asphalt). In the game this node is the terrain's child, so its _ready runs
## before the parent's READY and resolves in time; a node added later needs the terrain's
## free_editor_textures off (tests turn it off).
func refresh_growth() -> void:
	var assets: Resource = terrain.get("assets") if terrain != null else null
	if assets != null and (assets.call("get_texture_list") as Array).is_empty():
		push_warning("GrassBlades: the terrain's texture list is empty (Terrain3D free_editor_textures "
			+ "cleared it); the terrain rule cannot resolve slot names and grass grows everywhere")
	_allow = growth.table_for(assets)
	_mix = growth.mix_bytes(assets, types)
	_mix_f = _mix.to_float32_array()
	_slot_mixes = growth.slot_mixes(assets, types)
	_water_index = growth.water_index()
	_sea_kind = int(_water_index.get(GrassWater.SEA_KIND.to_lower(), -1))
	_water_bytes = growth.water_bytes(types)
	_water_dirty = true
	_far_dirty = true
	_types_up.mark()


func _on_region_map_changed() -> void:
	grass_maps.refresh()
	water_maps.refresh()
	_region_map_dirty = true
	_ground_dirty = true


func _on_ground_changed() -> void:
	_ground_dirty = true


func _on_grass_maps_changed() -> void:
	_far_dirty = true        # the far carpet re-sends its static inputs, the grass map array among them


## The blade material's view of the ground (grass_ground.gdshaderinc), by RID, as Terrain3D binds its own
## material: the region map, region size and spacing, the control and albedo arrays and the slot tints the
## terrain shader multiplies (read back from the terrain material; white if absent).
func _push_ground() -> void:
	var data: Object = terrain.get("data")
	var assets: Object = terrain.get("assets")
	var ctl: RID = data.get_control_maps_rid() if data != null else RID()
	var alb: RID = assets.call("get_albedo_array_rid") if assets != null else RID()
	if not _ground_dirty and ctl == _colour_rids[0] and alb == _colour_rids[1]:
		return
	_ground_dirty = false
	_colour_rids = [ctl, alb]
	var rid := material.get_rid()
	RenderingServer.material_set_param(rid, "ground_region_map", data.get_region_map())
	RenderingServer.material_set_param(rid, "ground_region_size", float(int(terrain.get("region_size"))))
	RenderingServer.material_set_param(rid, "ground_vertex_spacing", float(terrain.get("vertex_spacing")))
	RenderingServer.material_set_param(rid, "ground_control_maps", ctl)
	RenderingServer.material_set_param(rid, "ground_albedo", alb)
	var tint = null
	var tm: Object = terrain.get("material")
	if tm != null and tm.has_method("get_material_rid"):
		tint = RenderingServer.material_get_param(tm.call("get_material_rid"), "_texture_color_array")
	if tint == null or (tint is Array and tint.is_empty()):
		var white := PackedColorArray()
		white.resize(32)
		white.fill(Color.WHITE)
		tint = white
	RenderingServer.material_set_param(rid, "ground_tint", tint)


## A quality tier: {on, pitch (m), radius (m), far (Vector2: d_far0, d_far1), shadow (a ShadowMode name)};
## on false hides the grass. Optional budget keys — cap_hi, cap_lo, cap_shadow, shadow_radius — override the
## node's exports; absent keys leave them. Pitch, radius, the ramps and the shadow mode are per-frame params
## and switch live; the CAPS are read once, when _rt_init allocates the instance buffers — a tier applied by
## a feeder child in its _ready (children ready first) is in time for that, a mid-game tier change is not.
func apply_quality(p: Dictionary) -> void:
	if not bool(p.get("on", true)):
		set_grass_visible(false)
		return
	grid_pitch = float(p["pitch"])
	radius = float(p["radius"])
	var far: Vector2 = p["far"]
	d_far0 = far.x
	d_far1 = far.y
	if p.has("cap_hi"):
		cap_hi = int(p["cap_hi"])
	if p.has("cap_lo"):
		cap_lo = int(p["cap_lo"])
	if p.has("cap_shadow"):
		cap_shadow = int(p["cap_shadow"])
	if p.has("shadow_radius"):
		shadow_radius = float(p["shadow_radius"])
	set_grass_visible(true)
	set_shadow_mode(ShadowMode[String(p["shadow"])] as ShadowMode)


## Ruts: a map over a square of ground (R = depression, m) whose corner is `origin` and side `size_m`; a rut
## `full_depth` deep crushes the blades over it fully, like a wheel track. A null texture: no ruts.
func set_ruts(tex: Texture2D, origin: Vector2, size_m: float, full_depth: float) -> void:
	_rut_on = tex != null
	_rut = Vector4(origin.x, origin.y, size_m, full_depth)
	_rut_texture = tex if tex != null else _dummy_rut
	_rut_tex = _rut_texture.get_rid()


## The road footprint to clear (duck-typed: GrassRoads says what it must answer).
func set_road_footprint(fp) -> void:
	roads.footprint = fp
	_road_dirty = true


## The water maps' folder for a ground maps folder (GrassBladesConfig.maps_folder).
static func water_folder(maps_folder: String) -> String:
	return maps_folder + WATER_FOLDER_SUFFIX


## The water sources (duck-typed: GrassWater says what it must answer); null: none (the sea alone).
func set_water(source) -> void:
	water.source = source
	_water_dirty = true


## What floats at a point (GrassQuery.sample_water over the live inputs): the surface layer's species; empty where no
## water stands over the ground or nothing floats.
func sample_water(p_position: Vector3) -> GrassSample:
	if terrain == null or terrain.get("data") == null:
		return GrassSample.new()
	sample(p_position)                  # brings the query's live inputs up to date
	_query.water_mix = _water_bytes.to_float32_array()
	return _query.sample_water(p_position)


## The highest water surface over `p` (a source's or the sea's), NAN where no water stands over the ground. It reads
## the sources as the blades last sent them (the window around the camera).
func water_surface(p: Vector3) -> float:
	var on := not is_nan(_sea_level)
	var wt := GrassWater.top(_water_pack, _water_origin, Vector2(p.x, p.z),
		Vector3(_sea_level if on else 0.0, float(_sea_kind), 1.0 if on else 0.0))
	if wt.x <= GrassWater.NONE or terrain == null or terrain.get("data") == null:
		return NAN
	var g := float(terrain.get("data").call("get_height", p))
	return wt.x if not is_nan(g) and wt.x > g else NAN


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_grass_visible(is_visible_in_tree())


func _exit_tree() -> void:
	farfield.unbind()
	_live = false
	_unbind_air()
	# The streams bound now: re-entry may replace `decorations` before the render thread runs this.
	RenderingServer.call_on_render_thread(_rt_free.bind(decorations))
	# Back in the tree (the editor's scene tabs take the edited scene out and put it back), _ready runs again
	# and rebuilds what _rt_free released. The game never re-enters.
	request_ready()


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	if _editor and terrain != null and terrain.has_method("get_camera"):
		var c = terrain.call("get_camera")     # Terrain3D follows the editor's viewport 0 camera
		if c is Camera3D:
			return c
	return get_viewport().get_camera_3d()


func _process(dt: float) -> void:
	_ease_wind(dt)
	_flush_washes()
	if _editor:
		_preview_tick()
	_far_tick()
	_drop_check()
	if frozen or not _live or not grass_visible:
		return
	_dispatch(dt)


## Saturation made VISIBLE: when a bin overflows, the place kernel drops whole tiles — the
## blades vanish in bands that move with the camera's facing (scan order decides who loses),
## which reads exactly like a culling bug. stats[3] is the drop bitmask; warn once per bin.
var _drop_warned := 0
var _drop_poll := 0


func _drop_check() -> void:
	_drop_poll += 1
	if _drop_poll % 120 != 0:
		return
	poll_stats()
	var bits := int(stats[3]) if stats.size() >= 4 else 0
	for bin in 3:
		var mask := 1 << bin
		if bits & mask and not _drop_warned & mask:
			_drop_warned |= mask
			var nm: String = ["HIGH", "LOW", "SHADOW"][bin]
			var count := int(stats[bin]) if stats.size() > bin else -1
			push_warning("GrassBlades: the %s bin saturated at %d blades and DROPPED the overflow — "
					% [nm, count]
					+ "grass vanishes in bands that follow the camera's facing. "
					+ "Raise the tier's cap_%s (or shrink radius/far)." % nm.to_lower())


## Editor mode: the preview's date, visibility and paint overlay (GrassEditorPreview, set by the plugin's menu and the
## view strip), and the node's own visibility in the scene tree.
func _preview_tick() -> void:
	var show := GrassEditorPreview.grass_shows() and is_visible_in_tree()
	if show != grass_visible:
		set_grass_visible(show)
	if GrassEditorPreview.overlay != _overlay:
		_overlay = GrassEditorPreview.overlay
		_far_dirty = true         # the far field sends it
	if not is_equal_approx(GrassEditorPreview.day, _day_of_year):
		_day_of_year = GrassEditorPreview.day
	if GrassEditorPreview.all_grounds != all_grounds:
		all_grounds = GrassEditorPreview.all_grounds
	if GrassEditorPreview.all_bloom != season.all_bloom:
		season.all_bloom = GrassEditorPreview.all_bloom      # a reloaded plan starts false: set again here
		_season_dirty = true


## True when the terrain's shader can draw the paint overlay (the far field's include, Waailand 1.5 or newer).
func overlay_supported() -> bool:
	return GrassFarField.shader_has(terrain.get("material") if terrain != null else null, &"grass_overlay")


## The far field (GrassFarField): (re)bind the terrain material, push what changed, then the wind, the
## sun and the blades' fade. On with the blades, off when they are hidden or `far_field` is off; on while the paint
## overlay shows (the editor), which it draws instead.
func _far_tick() -> void:
	if terrain == null:
		return
	if farfield.bind(terrain) or not farfield.in_sync():
		_far_dirty = true
	if not farfield.is_bound():
		return
	if _far_dirty:
		farfield.set_param(&"far_all_grounds", all_grounds)
		farfield.push_static(_far_grain, _allow, GrassFarField.type_heights(types), _gust_tex,
			GrassTerrainGrowth.far_slot_params(_slot_mixes, types, _far_grain), grass_maps.texture())
		farfield.set_overlay(_overlay)
		_far_dirty = false
	var on := (far_field and grass_visible and _live) or _overlay != GrassOverlay.Mode.OFF
	farfield.set_enabled(on)
	if not farfield.in_sync():
		return          # the material does not list the far field's uniforms yet: again next frame
	if on:
		farfield.push_frame(wind.uniforms(), _sun_travel, Vector2(radius - edge_fade_m, radius),
			-1e9 if is_nan(_sea_level) else _sea_level)


## For tools and tests: one dispatch with the current camera, drawn now. It never awaits frame_post_draw (an
## unfocused or off-screen window stops firing it); it forces the draw instead.
func step(dt: float = 1.0 / 60.0) -> void:
	_far_tick()
	_dispatch(dt)
	RenderingServer.force_draw()
	await get_tree().process_frame


## For tools and tests: reads back the last dispatch's results. call_on_render_thread runs inline when rendering
## is single-threaded (the default); with a render thread it lands a frame later.
func readback() -> Dictionary:
	var box := {}
	RenderingServer.call_on_render_thread(_rt_readback.bind(box))
	while box.is_empty():
		await get_tree().process_frame
	return box


## Shows or hides the blades and the decorations; hidden, nothing is dispatched.
func set_grass_visible(on: bool) -> void:
	grass_visible = on
	for i in _inst:
		RenderingServer.instance_set_visible(i, on)
	decorations.set_visible(on)


## For tools and tests: shows or hides the blades alone (the decorations stay as they are).
func show_blades(on: bool) -> void:
	for i in _inst:
		RenderingServer.instance_set_visible(i, on)


func _flags() -> int:
	var f := 0
	if cull_frustum:
		f |= 1
	if clumping:
		f |= 2
	if shadow_mode == ShadowMode.SHADOW_BIN:
		f |= 4
	if all_grounds:
		f |= 8
	return f


func _dispatch(dt: float) -> void:
	var cam := _camera()
	if cam == null or not _live:
		return
	if terrain == null:
		return
	var us0 := Time.get_ticks_usec() if debug_timing else 0
	_clock = fmod(_clock + dt, 3600.0)
	var c := view_of(cam).origin
	interaction.frame_begin(c, dt)
	if wind.calm_serial != _air_calm_seen:
		_air_calm_seen = wind.calm_serial
		air.reset()
	air.frame_begin(c, dt)
	var tsize := TILE_CELLS * grid_pitch
	# A blade shrinks over grow_m of travel CENTRED on its threshold, so blades live out to
	# R + grow_m/2. The grid must reach that far on every side, or the tile rounding (which
	# moves with the camera) drops and restores the last metre whole: a pop at the edge.
	var reach := radius + 0.5 * grow_m + tsize
	_tiles = int(ceil(2.0 * reach / tsize)) + 1
	var t0 := Vector2i(floori((c.x - reach) / tsize), floori((c.z - reach) / tsize))
	var push := PackedByteArray()
	push.resize(16)
	push.encode_s32(0, t0.x)
	push.encode_s32(4, t0.y)
	push.encode_s32(8, _tiles)
	var half := radius + grow_m + 2.0
	var box := AABB(c - Vector3.ONE * half, Vector3.ONE * half * 2.0)
	for mm in _mm:
		RenderingServer.multimesh_set_custom_aabb(mm, box)
	var us1 := Time.get_ticks_usec() if debug_timing else 0
	_update_material(cam, dt)
	var us2 := Time.get_ticks_usec() if debug_timing else 0
	var deco := decorations.frame(c, grow_m) if grass_visible else {}
	var us3 := Time.get_ticks_usec() if debug_timing else 0
	var data: Object = terrain.get("data")
	grass_maps.poll()          # streamed maps that finished loading reach their layers
	water_maps.poll()
	var ground := {"h": data.get_height_maps_rid(), "g": grass_maps.rid(), "rut": _rut_tex,
		"c": data.get_control_maps_rid(), "w": water_maps.rid()}
	if _region_map_dirty:
		ground["map"] = (data.get_region_map() as PackedInt32Array).to_byte_array()
		_region_map_dirty = false
	var wo := roads.window_for(Vector2(c.x, c.z))
	if _road_dirty or wo != _road_origin:
		var pk := roads.pack(wo)
		_road_pack = pk
		ground["roads"] = pk
		_road_origin = wo
		_road_count = int(pk["count"])
		_road_dirty = false
	var wwo := water.window_for(Vector2(c.x, c.z))
	var wrev := water.revision()
	if _water_dirty or wwo != _water_origin or wrev != _water_rev:
		var wpk := water.pack(wwo, _water_index)
		_water_pack = wpk
		ground["water"] = wpk
		_water_origin = wwo
		_water_rev = wrev
		_water_count = int(wpk["count"])
		_water_dirty = false
	# The surface layer runs where anything can float: a water source in the window, or the sea with an entry.
	ground["surface"] = _water_count > 0 or (not is_nan(_sea_level) and _sea_kind >= 0)
	var params := _params_bytes(cam)
	var types_b := PackedByteArray()                        # empty: the GPU has the latest, no upload
	var types_gen := _types_up.pending()
	if types_gen != 0 and _types_bytes_gen != types_gen:
		_types_bytes = types.upload_bytes()
		_types_bytes.append_array(_allow.to_byte_array())   # T.v[160..167]: the terrain's growth allowances
		_types_bytes.append_array(_mix)                     # T.v[168..391]: each texture id's species mix
		var depth := PackedFloat32Array()                   # T.v[392..423]: each type's depth range
		for v: Vector4 in types.depth_table():
			depth.append_array([v.x, v.y, v.z, v.w])
		_types_bytes.append_array(depth.to_byte_array())
		_types_bytes.append_array(_water_bytes)             # T.v[424..487]: the water kinds' floating mixes
		_types_bytes_gen = types_gen
	if types_gen != 0:
		types_b = _types_bytes
	var field := interaction.payload()
	var us4 := Time.get_ticks_usec() if debug_timing else 0
	var air_p := air.payload(wind.uniforms(), _wash_frame) if air_memory else {}
	RenderingServer.call_on_render_thread(_rt_frame.bind(params, push, types_b, types_gen, field, _tiles, deco, ground,
		air_p))
	if debug_timing:
		var us5 := Time.get_ticks_usec()
		cpu_split = {"setup": us1 - us0, "material": us2 - us1, "deco": us3 - us2,
			"ground_params_types_field": us4 - us3, "rt": us5 - us4, "total": us5 - us0}


func _update_material(cam: Camera3D, dt: float) -> void:
	if material == null:
		return
	var vp_h := float(cam.get_viewport().get_visible_rect().size.y)   # the camera's view (the editor's 3D view)
	_send(&"px_per_m", vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5)), false)
	_send(&"r_edge", radius, false)
	_send(&"edge_fade", edge_fade_m, false)
	wind.advance(dt)
	if _season_dirty:
		season.bind(decorations.kinds, types)
		GrassSeason.apply_types(types, _day_of_year, season)
		decorations.set_day(_day_of_year, season)
		decorations.apply_handoff([material])
		_season_dirty = false
		_types_up.mark()
	if _types_mat_gen != _types_up.latest():
		types.apply_to(material)
		_types_mat_gen = _types_up.latest()
	_push_ground()
	_send(&"sea_on", not is_nan(_sea_level), false)
	_send(&"sea_level", 0.0 if is_nan(_sea_level) else _sea_level, false)
	_send(&"swell_dir", _swell["dir"], false)
	_send(&"swell_h", _swell["height"], false)
	_send(&"swell_k", _swell["k"], false)
	_send(&"swell_omega", _swell["omega"], false)
	_send(&"swell_phase", _swell["phase"], false)
	var u := wind.uniforms()
	for k in u:
		_send(k, u[k], true)
	_bind_air()
	_send(&"air_window", air.window() if _air_bound and air_memory else Vector4.ZERO, true)


## A uniform to the blade material (and the flowers' when `decos`), only when its value changed.
func _send(k: StringName, v, decos: bool) -> void:
	if _sent.has(k) and _sent[k] == v:
		return
	_sent[k] = v
	material.set_shader_parameter(k, v)
	if decos:
		for m in decorations.materials:
			m.set_shader_parameter(k, v)


## The air field's textures on the blade and flower materials, once the render thread made them (air_state, air_eq).
func _bind_air() -> void:
	if _air_bound or not air.state_rid().is_valid() or not air.eq_rid().is_valid():
		return
	if _air_tex_state == null:
		_air_tex_state = Texture2DRD.new()
		_air_tex_eq = Texture2DRD.new()
	_air_tex_state.texture_rd_rid = air.state_rid()
	_air_tex_eq.texture_rd_rid = air.eq_rid()
	set_uniform(&"air_state", _air_tex_state)
	set_uniform(&"air_eq", _air_tex_eq)
	_air_bound = true


## Before the render thread frees the air field: the shaders stop reading it, and the wrappers let go of its textures.
func _unbind_air() -> void:
	if not _air_bound:
		return
	_sent.erase(&"air_window")
	set_uniform(&"air_window", Vector4.ZERO)
	_air_tex_state.texture_rd_rid = RID()
	_air_tex_eq.texture_rd_rid = RID()
	_air_bound = false


## Sets a uniform on the blade material and on every decoration material.
func set_uniform(uniform_name: StringName, value) -> void:
	if material != null:
		material.set_shader_parameter(uniform_name, value)
	for m in decorations.materials:
		m.set_shader_parameter(uniform_name, value)


## The direction the sunlight travels (a DirectionalLight3D shines along its -Z): the golden glow
## of the blades and the decorations. A feeder sets it from the scene's sun.
func set_sun(direction: Vector3) -> void:
	_sun_travel = direction
	set_uniform(&"sun_travel_dir", direction)


## The camera as the renderer DRAWS it this frame. With physics interpolation on, a camera moved in
## _physics_process is drawn (and its get_frustum() built) from its INTERPOLATED transform, up to one
## tick behind global_transform (0.5 m and 1.5 deg at 30 m/s in a brisk turn). Every distance the
## compute measures (grid, radius, LOD and far-carpet ramps, edge fade) and the frustum's "inside"
## point must use the same eye as the planes and the image; global_position would lead it by a tick
## and move in physics-tick steps.
static func view_of(cam: Camera3D) -> Transform3D:
	return cam.get_camera_transform()


## Params v0-v6: the eye and grid pitch, then the six frustum planes, sign-normalised so "inside"
## is positive.
static func camera_params(cam: Camera3D, pitch: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(28)
	var view := view_of(cam)
	var c := view.origin
	f[0] = c.x
	f[1] = c.y
	f[2] = c.z
	f[3] = pitch
	var inside := c - view.basis.z * (cam.near * 2.0 + 1.0)
	var planes := cam.get_frustum()
	for i in 6:
		var pl := Plane(0.0, 1.0, 0.0, -1e9)
		if i < planes.size():
			pl = planes[i]
			if pl.distance_to(inside) < 0.0:
				pl = Plane(-pl.normal, -pl.d)
		f[4 + i * 4 + 0] = pl.normal.x
		f[4 + i * 4 + 1] = pl.normal.y
		f[4 + i * 4 + 2] = pl.normal.z
		f[4 + i * 4 + 3] = -pl.d        # Godot: dot(n,p) = d; shader: dot(n,p) + w >= -r
	return f


func _params_bytes(cam: Camera3D) -> PackedByteArray:
	var f := PackedFloat32Array()
	f.resize(PARAM_VEC4 * 4)
	var cp := camera_params(cam, grid_pitch)
	for i in cp.size():
		f[i] = cp[i]
	# The compute inverts the LOD ramp and the edge fade separately, so they must not
	# overlap: the LOD ramp ends by the time the edge fade begins.
	var sw := minf(d_switch, radius - edge_fade_m)
	f[28] = radius
	f[29] = edge_fade_m
	f[30] = minf(d_morph, sw - 0.01)
	f[31] = sw
	f[32] = k_lo
	f[33] = width_exp
	f[34] = grow_m
	f[35] = shadow_margin
	var data: Object = terrain.get("data")
	var mo := GrassTerrainCaps.region_map_origin(data)
	f[36] = float(int(terrain.get("region_size")))
	f[37] = float(terrain.get("vertex_spacing"))
	f[38] = 32.0
	f[39] = 0.0
	f[40] = float(mo.x)
	f[41] = float(mo.y)
	f[42] = float(types.fallback_slot)        # FALLBACK_TYPE (P.v[10].z)
	f[43] = 0.0
	f[44] = float(interaction.origin_texel.x)
	f[45] = float(interaction.origin_texel.y)
	f[46] = interaction.texel_m
	f[47] = float(interaction.size_px)
	f[48] = float(cap_hi)
	f[49] = float(cap_lo)
	f[50] = float(cap_shadow)
	f[51] = float(_flags())
	f[52] = float(force_bin)
	f[53] = force_morph
	f[54] = shadow_radius
	f[55] = shadow_keep
	f[56] = cos(deg_to_rad(max_slope_deg))
	f[57] = root_sink
	f[58] = force_yaw
	var far_on := k_far < k_lo and d_far1 > d_far0 and d_far0 >= sw and d_far1 <= radius - edge_fade_m
	f[59] = k_far if far_on else k_lo
	f[60] = d_far0
	f[61] = d_far1
	f[62] = width_cap
	f[63] = 0.0
	f[64] = _road_origin.x
	f[65] = _road_origin.y
	f[66] = GrassRoads.BIN_M
	f[67] = float(GrassRoads.BINS) if _road_count > 0 else 0.0
	f[68] = GrassRoads.MARGIN_M
	f[69] = GrassRoads.VERGE_M.x
	f[70] = GrassRoads.VERGE_M.y
	f[72] = _rut.x
	f[73] = _rut.y
	f[74] = _rut.z
	f[75] = _rut.w
	f[76] = 1.0 if _rut_on else 0.0
	f[77] = species_patch_m
	f[78] = 0.0 if is_nan(_sea_level) else _sea_level
	f[79] = 0.0 if is_nan(_sea_level) else 1.0
	f[80] = _water_origin.x if _water_count > 0 else 0.0
	f[81] = _water_origin.y if _water_count > 0 else 0.0
	f[82] = GrassWater.BIN_M
	f[83] = float(GrassWater.BINS) if _water_count > 0 else 0.0
	f[84] = float(_sea_kind)
	f[85] = GrassTypes.SEA_SHORE_M
	f[86] = _clock
	f[87] = float(_swell["phase"])
	var sd: Vector2 = _swell["dir"]
	f[88] = sd.x
	f[89] = sd.y
	f[90] = float(_swell["height"])
	f[91] = float(_swell["k"])
	f[92] = water_bob_m
	f[93] = SURFACE_LIFT_M
	return f.to_byte_array()


# ── Render thread ────────────────────────────────────────────────────────────

static func _storage(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u


func _sampled(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sampler)
	u.add_id(tex)
	return u


func _compile(rd: RenderingDevice, f: RDShaderFile) -> RID:
	var spirv := f.get_spirv()
	if spirv == null or spirv.compile_error_compute != "":
		push_error("GrassBlades: compute compile failed: %s"
			% ("no spirv" if spirv == null else spirv.compile_error_compute))
		return RID()
	return rd.shader_create_from_spirv(spirv)


func _rt_init(place_f: RDShaderFile, fin_f: RDShaderFile, scenario: RID) -> void:
	_rd = RenderingServer.get_rendering_device()
	var rd := _rd
	if rd == null:
		push_error("GrassBlades: no RenderingDevice (headless?)")
		return
	_place_shader = _compile(rd, place_f)
	_fin_shader = _compile(rd, fin_f)
	if not _place_shader.is_valid() or not _fin_shader.is_valid():
		return
	_place_pipe = rd.compute_pipeline_create(_place_shader)
	_fin_pipe = rd.compute_pipeline_create(_fin_shader)
	_params = rd.storage_buffer_create(PARAM_VEC4 * 16)
	# The type rows, row e (stripes), the terrain's 32 growth allowances (8 vec4) and mixes, the depth rows, the water
	# kinds' mixes.
	_types_buf = rd.storage_buffer_create((GrassTypes.SLOTS * GrassTypes.VEC4 + GrassTypes.SLOTS
		+ GrassTerrainGrowth.SLOTS / 4 + GrassTerrainGrowth.SLOTS * GrassTerrainGrowth.MIX_VEC4
		+ GrassTypes.SLOTS + GrassTerrainGrowth.WATER_KINDS * GrassTerrainGrowth.WATER_VEC4) * 16)
	var zero16 := PackedByteArray()
	zero16.resize(16)
	_counters = rd.storage_buffer_create(16, zero16)
	_stats_buf = rd.storage_buffer_create(16, zero16)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = rd.sampler_create(ss)
	_field_tex = interaction.rt_create(rd)
	air.rt_create(rd, RenderingServer.texture_get_rd_texture(_gust_tex.get_rid()) if _gust_tex != null else RID())
	_region_buf = rd.storage_buffer_create(REGION_MAP_BYTES)
	_road_idx = rd.storage_buffer_create(GrassRoads.MAX_IDS * 4)
	_road_shapes = rd.storage_buffer_create(GrassRoads.MAX_SHAPES * 3 * 16)
	_water_idx = rd.storage_buffer_create(GrassWater.MAX_IDS * 4)
	_water_shapes = rd.storage_buffer_create((GrassWater.MAX_POLYS + GrassWater.MAX_VERTS) * 16)
	# allocate(use_indirect = true) THEN set_mesh: the order is load-bearing (godotengine/godot#116655).
	var caps := [cap_hi, cap_lo, cap_shadow]
	var meshes := [mesh_hi, mesh_lo, mesh_hi]
	for i in 3:
		var mm := RenderingServer.multimesh_create()
		RenderingServer.multimesh_allocate_data(mm, caps[i],
			RenderingServer.MULTIMESH_TRANSFORM_3D, true, true, true)
		RenderingServer.multimesh_set_mesh(mm, (meshes[i] as ArrayMesh).get_rid())
		var inst := RenderingServer.instance_create2(mm, scenario)
		_mm.append(mm)
		_inst.append(inst)
		var db := RenderingServer.multimesh_get_buffer_rd_rid(mm)
		var cb := RenderingServer.multimesh_get_command_buffer_rd_rid(mm)
		if not db.is_valid() or not cb.is_valid():
			push_error("GrassBlades: MultiMesh %d has no GPU buffers" % i)
			return
		_dst.append(db)
		_cmd.append(cb)
	_apply_shadow_mode()
	# The placement set reads the terrain: _rt_bind_ground builds it on the first frame.
	var fin: Array[RDUniform] = [
		_storage(0, _counters), _storage(1, _cmd[0]), _storage(2, _cmd[1]),
		_storage(3, _cmd[2]), _storage(4, _stats_buf),
	]
	_fin_set = rd.uniform_set_create(fin, _fin_shader, 0)
	if material != null:
		for inst in _inst:
			RenderingServer.instance_geometry_set_material_override(inst, material.get_rid())
	decorations.rt_init(rd, scenario, _field_tex, _params, _types_buf, _fin_shader)
	_live = true
	if not grass_visible:
		set_grass_visible(false)    # new instances start visible: a hidden field stays hidden on re-entry


## Bindings 2 (heights), 3 (grass maps), 9 (region map), 10-11 (roads), 12 (ruts), 13 (control maps), 14 (the water
## maps), 15-16 (water sources): shared by the blade and decoration sets.
func _ground_uniforms(h_rd: RID, g_rd: RID, rut_rd: RID, c_rd: RID, w_rd: RID) -> Array[RDUniform]:
	var out: Array[RDUniform] = [_sampled(2, h_rd), _sampled(3, g_rd), _storage(9, _region_buf),
		_storage(10, _road_idx), _storage(11, _road_shapes), _sampled(12, rut_rd), _sampled(13, c_rd),
		_sampled(14, w_rd), _storage(15, _water_idx), _storage(16, _water_shapes)]
	return out


## (Re)build every uniform set that reads the terrain. Terrain3D replaces an array's RID when it
## rebuilds it (with every region resident); a streaming build's slot pool keeps its arrays.
func _rt_bind_ground(rd: RenderingDevice, h_rs: RID, g_rs: RID, rut_rs: RID, c_rs: RID, w_rs: RID) -> bool:
	if not h_rs.is_valid() or not g_rs.is_valid() or not rut_rs.is_valid() or not c_rs.is_valid() \
			or not w_rs.is_valid():
		return false
	var h_rd := RenderingServer.texture_get_rd_texture(h_rs)
	var g_rd := RenderingServer.texture_get_rd_texture(g_rs)
	var w_rd := RenderingServer.texture_get_rd_texture(w_rs)
	var c_rd := RenderingServer.texture_get_rd_texture(c_rs)
	var rut_rd := RenderingServer.texture_get_rd_texture(rut_rs)
	if not rut_rd.is_valid():
		# An unusable rut map must not stop the grass: bind the dummy (ruts read as none).
		rut_rd = RenderingServer.texture_get_rd_texture(_dummy_rut.get_rid())
	if not h_rd.is_valid() or not g_rd.is_valid() or not rut_rd.is_valid() or not c_rd.is_valid() \
			or not w_rd.is_valid():
		return false
	if _place_set.is_valid() and rd.uniform_set_is_valid(_place_set):
		rd.free_rid(_place_set)
	var pu: Array[RDUniform] = [_storage(0, _params), _storage(1, _types_buf),
		_storage(4, _counters), _storage(5, _dst[0]), _storage(6, _dst[1]), _storage(7, _dst[2])]
	pu.append_array(_ground_uniforms(h_rd, g_rd, rut_rd, c_rd, w_rd))
	var fu := RDUniform.new()
	fu.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	fu.binding = 8
	fu.add_id(_field_tex)
	pu.append(fu)
	_place_set = rd.uniform_set_create(pu, _place_shader, 0)
	decorations.rt_bind(rd, _ground_uniforms(h_rd, g_rd, rut_rd, c_rd, w_rd))
	_ground_rids = [h_rs, g_rs, rut_rs, c_rs, w_rs]
	return _place_set.is_valid()


func _rt_frame(params: PackedByteArray, push: PackedByteArray, types_b: PackedByteArray, types_gen: int,
		field_payload: Dictionary, tiles: int, deco: Dictionary, ground: Dictionary, air_payload := {}) -> void:
	var rd := _rd
	if rd == null or not _place_pipe.is_valid():
		return
	if ground.has("map"):
		var mb: PackedByteArray = ground["map"]
		rd.buffer_update(_region_buf, 0, mb.size(), mb)
	if ground.has("roads"):
		var pk: Dictionary = ground["roads"]
		var ib: PackedByteArray = pk["idx"]
		var sb: PackedByteArray = pk["shapes"]
		rd.buffer_update(_road_idx, 0, ib.size(), ib)
		if not sb.is_empty():
			rd.buffer_update(_road_shapes, 0, sb.size(), sb)
	if ground.has("water"):
		var wk: Dictionary = ground["water"]
		var wib: PackedByteArray = wk["idx"]
		var wsb: PackedByteArray = wk["shapes"]
		rd.buffer_update(_water_idx, 0, wib.size(), wib)
		if not wsb.is_empty():
			rd.buffer_update(_water_shapes, 0, wsb.size(), wsb)
	if ground["h"] != _ground_rids[0] or ground["g"] != _ground_rids[1] or ground["rut"] != _ground_rids[2] \
			or ground["c"] != _ground_rids[3] or ground["w"] != _ground_rids[4] or not _place_set.is_valid():
		if not _rt_bind_ground(rd, ground["h"], ground["g"], ground["rut"], ground["c"], ground["w"]):
			return
	rd.buffer_update(_params, 0, params.size(), params)
	if not types_b.is_empty():
		rd.buffer_update(_types_buf, 0, types_b.size(), types_b)
		_types_up.uploaded(types_gen)
	interaction.rt_prepare(rd, field_payload)
	air.rt_prepare(rd, air_payload)
	decorations.rt_prepare(rd, deco)
	if debug_timing:
		_read_timing(rd)
		rd.capture_timestamp(_ts_a)
	# Fail LOUD, named: a null pipeline or invalid set bound into a compute list errors
	# EVERY FRAME inside the renderer ("compute_list_bind_compute_pipeline: Parameter
	# pipeline is null" + a push-constant size error) with no hint WHICH kernel — the
	# check runs EVERY frame and reports the TRANSITION into broken (state that was fine
	# at the first frame can break after a mid-session RT rebuild), re-arming when valid.
	var broken: Array[String] = []
	if not _place_pipe.is_valid():
		broken.append("place pipeline")
	if not _fin_pipe.is_valid():
		broken.append("finalize pipeline")
	if not _place_set.is_valid():
		broken.append("place uniform set")
	if not _fin_set.is_valid():
		broken.append("finalize uniform set")
	for i in 3:
		if not _dst[i].is_valid() or not _cmd[i].is_valid():
			broken.append("multimesh %d buffer" % i)
	if not interaction.pipe_valid():
		broken.append("interaction stamp pipeline")
	if not decorations.pipe_valid():
		broken.append("decoration pipeline")
	if broken.is_empty():
		_was_broken = false
	else:
		if not _was_broken:
			_was_broken = true
			push_error("GrassBlades: compute state broken, grass disabled — %s. "
					% ", ".join(broken)
					+ "Check the GLSL compile errors logged at world load, and the tier caps "
					+ "(a MultiMesh allocation that fails strands the buffers).")
			_live = false
			return
	if debug_dispatch_marker:
		print("[GrassBlades] dispatch frame ", Engine.get_process_frames())
	var cl := rd.compute_list_begin()
	if not debug_skip_interaction:
		interaction.rt_dispatch(rd, cl)
	if not air_payload.is_empty():
		air.rt_dispatch(rd, cl)
	rd.compute_list_bind_compute_pipeline(cl, _place_pipe)
	rd.compute_list_bind_uniform_set(cl, _place_set, 0)
	rd.compute_list_set_push_constant(cl, push, push.size())
	rd.compute_list_dispatch(cl, tiles, tiles, 1)
	if bool(ground.get("surface", false)) and not debug_skip_surface_layer:
		# The surface layer: the same kernel and tiles, appending to the same bins (the finalize counts both).
		var sp := push.duplicate()
		sp.encode_s32(12, 1)
		rd.compute_list_set_push_constant(cl, sp, sp.size())
		rd.compute_list_dispatch(cl, tiles, tiles, 1)
	rd.compute_list_add_barrier(cl)
	var fp := PackedByteArray()
	fp.resize(16)
	fp.encode_u32(0, cap_hi)
	fp.encode_u32(4, cap_lo)
	fp.encode_u32(8, cap_shadow)
	rd.compute_list_bind_compute_pipeline(cl, _fin_pipe)
	rd.compute_list_bind_uniform_set(cl, _fin_set, 0)
	rd.compute_list_set_push_constant(cl, fp, fp.size())
	rd.compute_list_dispatch(cl, 1, 1, 1)
	rd.compute_list_add_barrier(cl)
	if not debug_skip_deco:
		decorations.rt_frame(rd, cl, deco, _fin_pipe)
	rd.compute_list_end()
	if debug_timing:
		rd.capture_timestamp(_ts_b)


## Timestamps resolve a frame late, so this reads the PREVIOUS frame's pair by name.
func _read_timing(rd: RenderingDevice) -> void:
	var a := -1.0
	var b := -1.0
	for i in rd.get_captured_timestamps_count():
		var nm := rd.get_captured_timestamp_name(i)
		if nm == _ts_a:
			a = float(rd.get_captured_timestamp_gpu_time(i))
		elif nm == _ts_b:
			b = float(rd.get_captured_timestamp_gpu_time(i))
	if a >= 0.0 and b >= a:
		compute_ms = (b - a) / 1e6


func _rt_readback(box: Dictionary) -> void:
	var rd := _rd
	if rd == null:
		return
	var st := rd.buffer_get_data(_stats_buf).to_int32_array()
	box["counts"] = st
	var keys := ["hi", "lo", "shadow"]
	for i in 3:
		var n := st[i]
		box[keys[i]] = (rd.buffer_get_data(_dst[i], 0, n * STRIDE * 4).to_float32_array()
			if n > 0 else PackedFloat32Array())
		box["cmd_" + keys[i]] = rd.buffer_get_data(_cmd[i]).to_int32_array()
	box["field"] = interaction.rt_read(rd)
	if air.state_rid().is_valid():
		box["air"] = air.rt_read(rd)
	decorations.rt_readback(rd, box)
	stats = st


## A cheap poll of `stats` (16 bytes), for a tool that shows the counts.
func poll_stats() -> void:
	RenderingServer.call_on_render_thread(_rt_stats)


func _rt_stats() -> void:
	if _rd != null and _stats_buf.is_valid():
		stats = _rd.buffer_get_data(_stats_buf).to_int32_array()


func _apply_shadow_mode() -> void:
	var off := RenderingServer.SHADOW_CASTING_SETTING_OFF
	var on := RenderingServer.SHADOW_CASTING_SETTING_ON
	var only := RenderingServer.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var hi := on if shadow_mode == ShadowMode.HIGH_CASTS else off
	var sh := only if shadow_mode == ShadowMode.SHADOW_BIN else off
	if _inst.size() == 3:
		RenderingServer.instance_geometry_set_cast_shadows_setting(_inst[0], hi)
		RenderingServer.instance_geometry_set_cast_shadows_setting(_inst[1], off)
		RenderingServer.instance_geometry_set_cast_shadows_setting(_inst[2], sh)
		RenderingServer.instance_set_visible(_inst[2], shadow_mode == ShadowMode.SHADOW_BIN)
	applied_casts = {"hi": hi, "lo": off, "shadow": sh}


## Switches which blades cast shadows (shadow_mode).
func set_shadow_mode(mode: ShadowMode) -> void:
	shadow_mode = mode
	RenderingServer.call_on_render_thread(_apply_shadow_mode)


func _rt_free(p_decorations: DecorationStreams = null) -> void:
	var rd := _rd
	if rd == null:
		return
	# The decorations' uniform sets reference our params and types buffers: they go first. `p_decorations`: the streams
	# being replaced (reload_species), freed on the render thread after the new ones are set.
	(p_decorations if p_decorations != null else decorations).rt_free(rd)
	# OUR resources first. Freeing a MultiMesh frees its instance buffer, and the RD then
	# auto-frees every uniform set built on it, so freeing _place_set afterwards would hit a dead ID.
	for us in [_place_set, _fin_set]:
		if (us as RID).is_valid() and rd.uniform_set_is_valid(us):
			rd.free_rid(us)
	for r in [_place_pipe, _fin_pipe, _place_shader, _fin_shader, _params, _types_buf,
			_counters, _stats_buf, _sampler, _region_buf, _road_idx, _road_shapes, _water_idx, _water_shapes]:
		if (r as RID).is_valid():
			rd.free_rid(r)
	interaction.rt_free(rd)
	air.rt_free(rd)
	# Exit reports 3 StorageBuffers leaked per GrassBlades, one per MultiMesh: what the engine's
	# command-buffer leak on MultiMesh free would give (godotengine/godot#108148), though not
	# proven to be it.
	for inst in _inst:
		RenderingServer.free_rid(inst)
	for mm in _mm:
		RenderingServer.free_rid(mm)
	_inst.clear()
	_mm.clear()
	_dst.clear()
	_cmd.clear()
	# Re-entry builds new buffers: nothing may point at the freed ones. A freed RID keeps its id (is_valid()
	# stays true), so reset them, or the rebind check never fires.
	_place_set = RID()
	_fin_set = RID()
	_ground_rids = [RID(), RID(), RID(), RID(), RID()]
	_region_map_dirty = true
	_road_dirty = true


# ── Decoding (tests, tools) ──────────────────────────────────────────────────

## Two 0..1 values packed into one float by the kernels (pack2).
static func unpack2(v: float) -> Vector2:
	var a := floorf(v / 1024.0)
	return Vector2(a, v - a * 1024.0) / 1023.0


## Blade `i` of a read-back instance buffer (readback()), as a Dictionary of its fields.
static func decode(buf: PackedFloat32Array, i: int) -> Dictionary:
	var o := i * STRIDE
	var ud := unpack2(buf[o + 12])            # COLOR.x: clump hash, clump distance
	var fa := unpack2(buf[o + 13])            # COLOR.y: clump facing, away-from-centre angle
	var ly := unpack2(buf[o + 14]) * 2.0 - Vector2.ONE   # COLOR.z: lay direction
	var cp := unpack2(buf[o + 15])            # COLOR.w: crush, push
	var lo := floorf(buf[o + 18] / 1048576.0)  # CUSTOM.z: (type & 15) x 2^20 + pack2(morph, seed)
	var hi := floorf(buf[o + 19] / 1048576.0)  # CUSTOM.w: (type >> 4) x 2^20 + pack2(ground normal x, z)
	var ty := lo + 16.0 * hi
	var ms := unpack2(buf[o + 18] - lo * 1048576.0)
	var nx := unpack2(buf[o + 19] - hi * 1048576.0) * 2.0 - Vector2.ONE
	return {
		"side": Vector3(buf[o + 0], buf[o + 4], buf[o + 8]),
		"facing": Vector3(buf[o + 2], buf[o + 6], buf[o + 10]),
		"root": Vector3(buf[o + 3], buf[o + 7], buf[o + 11]),
		"h": buf[o + 16],
		"w": buf[o + 17],
		"morph": ms.x,
		"seed": ms.y,
		"type": int(ty),
		"u": ud.x,
		"cdist": ud.y,
		"clump_facing": fa.x * TAU,
		"away": fa.y * TAU,
		"lay": ly,
		"crush": cp.x,
		"push": cp.y,
		"ground_n": Vector3(nx.x, sqrt(maxf(1.0 - nx.length_squared(), 0.0)), nx.y),
	}
