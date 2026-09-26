# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGroundRulesDialog
extends GrassSuite
## The Ground rules dialog, headless: its building blocks, its states, the Rules
## tab's drops, the inspector, the Seasons tab, undo and redo, against a fake map (four surfaces, no pictures) and a
## save that records what it was given.

const UxComponents := preload("res://addons/terrain_3d_extended/src/ux_components.gd")
const RULES := {"format": 1, "default_grass": true, "rules": [
	{"name": "Meadows", "colour": "#8bc34a", "surfaces": ["Pasture", "Town Ground"], "density": 1.0,
		"species": {"pasture": 0.65, "verge": 0.35}},
	{"name": "Bare", "colour": "#616161", "surfaces": ["Asphalt"], "density": 0.0, "species": {}}],
	"everything_else": {"density": 1.0, "species": {}}}

var saved: Array = []


static func run() -> Dictionary:
	var keep := GrassSuite.use_fixture_species()           # the addon's own species: it passes in any project
	var r := await GrassSuite.run_suite(TestGroundRulesDialog.new(), "ground_rules_dialog")
	GrassBladesConfig.use(keep)
	return r


func test_the_building_blocks() -> void:
	var t := GroundTile.make("ground_surface", "Pasture", null, "Pasture", 46, Color("8bc34a"), true)
	assert_eq(t._get_drag_data(Vector2.ZERO), {"kind": "ground_surface", "id": "Pasture"}, "a tile carries {kind, id}")
	assert_eq(t.mouse_filter, Control.MOUSE_FILTER_PASS, "a drop over a tile reaches the target around it")
	t.disabled = true
	assert_true(t._get_drag_data(Vector2.ZERO) == null, "a disabled tile does not drag")
	t.free()
	var got := []
	var target := GroundDropTarget.new().setup("ground_surface", func(id: String) -> void: got.append(id),
		StyleBoxFlat.new(), StyleBoxFlat.new())
	assert_true(target._can_drop_data(Vector2.ZERO, {"kind": "ground_surface", "id": "Mud"}), "it takes its kind")
	assert_true(not target._can_drop_data(Vector2.ZERO, {"kind": "ground_species", "id": "fern"}), "not another")
	target._drop_data(Vector2.ZERO, {"kind": "ground_surface", "id": "Mud"})
	assert_eq(got, ["Mud"], "a drop calls back with the id")
	target.free()
	var strip := SeasonYearStrip.new()
	strip.lanes = [{"keys": Vector4(68.0, 80.0, 99.0, 109.0), "colour": Color.YELLOW}, {"keys": Vector4(212.0, 231.0, 292.0,
		30.0), "colour": Color.WHITE}]
	assert_true(strip.get_combined_minimum_size().y >= 2 * SeasonYearStrip.LANE, "a lane per kind")
	assert_near(strip.x_of(182.5, 365.0), 182.5, 1e-6, "days map across the width")
	strip.free()


func _save(r: GrassGroundRules) -> Error:
	saved.append(r.snapshot())
	return OK


func _start() -> GrassGroundRules:
	return GrassGroundRules.from_text(JSON.stringify(RULES))


func _dialog(rules: GrassGroundRules, map := "isle", path := "res://grounds/isle.json") -> GroundRulesDialog:
	saved = []
	var d := GroundRulesDialog.new()
	var types := GrassTypes.new()
	d.setup({"rules": rules, "types": types, "kinds": DecoKinds.new(DecoKinds.FROM_CONFIG, types), "kit": UxComponents,
		"surfaces": [{"name": "Pasture", "picture": null}, {"name": "Town Ground", "picture": null},
			{"name": "Asphalt", "picture": null}, {"name": "Mud", "picture": null}],
		"map": map, "path": path, "save": _save, "start": _start})
	return d


static func _has_text(n: Node, text: String) -> bool:
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).text.contains(text):
			return true
	return false


func _key(d: GroundRulesDialog, code: Key, ctrl := false, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	d._input(k)


func test_the_states_and_the_shell() -> void:
	var none := _dialog(null, "")
	assert_true(_has_text(none, "This map has no grass"), "no GrassBlades: says so")
	none.free()
	var nodir := _dialog(null, "isle", "")
	assert_true(_has_text(nodir, "grounds_dir"), "no grounds_dir in the config: says where to set it")
	nodir.free()
	var fresh := _dialog(null)
	assert_true(_has_text(fresh, "shared growth table"), "no file: the shared table")
	(fresh.find_child("Start", true, false) as Button).pressed.emit()
	assert_true(fresh.rules != null and saved.size() == 1, "Start from defaults writes the map's rules")
	fresh.free()
	var d := _dialog(GrassGroundRules.from_text(JSON.stringify(RULES)))
	assert_true(d.find_child("TabRules", true, false) != null and d.find_child("TabSeasons", true, false) != null,
		"the two tabs")
	(d.find_child("Master", true, false).get_node("Toggle") as CheckBox).toggled.emit(false)
	assert_true(not d.rules.default_grass and saved.size() == 1, "the master switch: one change, written")
	_key(d, KEY_Z, true)
	assert_true(d.rules.default_grass and saved.size() == 2, "Ctrl+Z undoes it (and writes)")
	_key(d, KEY_Z, true, true)
	assert_true(not d.rules.default_grass, "Ctrl+Shift+Z redoes it")
	assert_true(not (d.find_child("Undo", true, false) as Button).disabled, "Undo is enabled with a step to undo")
	var closed := [0]
	d.closed.connect(func() -> void: closed[0] += 1)
	_key(d, KEY_ESCAPE)
	assert_eq(closed[0], 1, "Esc closes it")


static func _tiles(n: Node, kind: String) -> Array:
	return n.find_children("*", "", true, false).filter(func(c): return c is GroundTile and c.drag_kind == kind)


func test_the_rules_tab_drops() -> void:
	var d := _dialog(GrassGroundRules.from_text(JSON.stringify(RULES)))
	assert_eq(_tiles(d.find_child("Surfaces", true, false), "ground_surface").size(), 4, "every surface of the map")
	var bare := d.find_child("Rule1", true, false) as GroundDropTarget
	bare._drop_data(Vector2.ZERO, {"kind": "ground_surface", "id": "Mud"})
	assert_eq([d.rules.rule_of("Mud"), saved.size()], [1, 1], "Mud dropped on Bare: moved and written")
	(d.find_child("NewRuleZone", true, false) as GroundDropTarget)._drop_data(Vector2.ZERO,
		{"kind": "ground_surface", "id": "Town Ground"})
	var i := d.rules.rule_of("Town Ground")
	assert_eq([i, d.rules.rules[i]["name"], d.selected, d.rules.rules[i]["species"]],
		[2, "Town Ground", 2, {"pasture": 0.65, "verge": 0.35}], "the new-rule zone: a rule of its own, selected, Meadows' settings")
	(d.find_child("Surfaces", true, false) as GroundDropTarget)._drop_data(Vector2.ZERO, {"kind": "ground_surface", "id": "Mud"})
	assert_eq(d.rules.rule_of("Mud"), -1, "dropped back on the surfaces: unassigned")
	d.undo()
	assert_eq(d.rules.rule_of("Mud"), 1, "undo")
	d.redo()
	assert_eq(d.rules.rule_of("Mud"), -1, "redo")
	(d.find_child("Rule0", true, false) as GroundDropTarget).pressed.emit()
	assert_eq(d.selected, 0, "a click selects a rule")
	(d.find_child("EverythingElse", true, false) as GroundDropTarget).pressed.emit()
	assert_eq(d.selected, -1, "and Everything else")
	(d.find_child("NewRule", true, false) as Button).pressed.emit()
	assert_eq([d.rules.rules.size(), d.selected], [4, 3], "+ New rule: an empty rule, selected")
	d.surface_filter = "unassigned"
	d.rebuild()
	assert_eq(_tiles(d.find_child("Surfaces", true, false), "ground_surface").map(func(t): return t.drag_id), ["Mud"],
		"the Unassigned filter")
	d.free()


func test_the_inspector() -> void:
	var d := _dialog(GrassGroundRules.from_text(JSON.stringify(RULES)))
	(d.find_child("Master", true, false).get_node("Toggle") as CheckBox).toggled.emit(false)
	assert_true((d.find_child("DefaultGrass", true, false).get_node("Toggle") as CheckBox).disabled,
		"the master switch off greys the rule's Default grass")
	d.undo()
	var dens := d.find_child("Density", true, false).get_node("Slider") as HSlider
	dens.value = 0.4
	dens.drag_ended.emit(true)
	assert_near(float(d.rules.rules[0]["density"]), 0.4, 1e-6, "the density, on release")
	var fern: GroundTile = _tiles(d.find_child("SpeciesStrip", true, false), "ground_species").filter(
		func(t): return t.drag_id == "fern")[0]
	fern.pressed.emit()
	assert_near(float(d.rules.rules[0]["species"].get("fern", 0.0)), 0.5, 1e-6, "a species clicked in: an equal weight")
	(d.find_child("Species_fern", true, false).find_child("Remove", true, false) as Button).pressed.emit()
	assert_true(not d.rules.rules[0]["species"].has("fern"), "✕ removes it")
	(d.find_child("Mix", true, false) as GroundDropTarget)._drop_data(Vector2.ZERO, {"kind": "ground_species", "id": "sedge"})
	assert_true(d.rules.rules[0]["species"].has("sedge"), "a species dropped on the mix joins it")
	(d.find_child("AddBand", true, false) as Button).pressed.emit()
	assert_near(float(d.rules.rules[0]["band"]["above_m"]), 500.0, 1e-6, "+ a band, at 500 m")
	(d.find_child("RemoveBand", true, false) as Button).pressed.emit()
	assert_true((d.rules.rules[0]["band"] as Dictionary).is_empty(), "✕ removes it")
	(d.find_child("Name", true, false) as LineEdit).text_submitted.emit("Lawns")
	assert_eq(d.rules.rules[0]["name"], "Lawns", "renamed on Enter")
	d.selected = 1
	d.rebuild()
	(d.find_child("Mix", true, false) as GroundDropTarget)._drop_data(Vector2.ZERO, {"kind": "ground_species", "id": "fern"})
	var bare: Dictionary = d.rules.rules[1]["species"]
	assert_true(bare.has("fern") and bare.has("verge") and bare.has("pasture"),
		"adding to an inherited mix keeps what it inherited (%s)" % bare)
	(d.find_child("Delete", true, false) as Button).pressed.emit()
	assert_eq([d.rules.rules.size(), d.rules.rule_of("Asphalt"), d.selected], [1, -1, -1],
		"Delete: its surfaces go to Everything else")
	d.free()


func test_the_seasons_tab() -> void:
	var d := _dialog(GrassGroundRules.from_text(JSON.stringify(RULES)))
	(d.find_child("TabSeasons", true, false) as Button).pressed.emit()
	var rows := d.find_children("Season_*", "", true, false).map(func(n): return String(n.name))
	assert_eq(rows, ["Season_pasture", "Season_verge"], "the species this map grows, in palette order")
	(d.find_child("ShowAll", true, false).get_node("Toggle") as CheckBox).toggled.emit(true)
	var fr := d.find_child("Season_freesia", true, false) as GroundDropTarget
	assert_true(fr != null, "Show all species")
	var keys: Vector4 = d.kinds.kinds[d.kinds.index_of("freesia")]["bloom"]
	var strip := fr.find_child("Strip", true, false) as SeasonYearStrip
	assert_true(strip.lanes.size() == 1 and strip.lanes[0]["keys"] == keys and strip.pins == [-1.0],
		"its year: one lane (its flower), no pin on the calendar")
	fr.pressed.emit()
	assert_eq(d.season_open, "freesia", "a click opens its controls")
	(d.find_child("Mode_bloom", true, false) as Button).pressed.emit()
	assert_eq(d.rules.season_of("freesia"), {"mode": "bloom"}, "Always in bloom")
	var pinned := d.find_child("Season_freesia", true, false).find_child("Strip", true, false) as SeasonYearStrip
	assert_near(float(pinned.pins[0]), GrassSeasonPlan.stage_day(keys, 0.5), 1e-6, "pinned at Prime on its strip")
	(d.find_child("Mode_stage", true, false) as Button).pressed.emit()
	var st := d.find_child("Stage", true, false).get_node("Slider") as HSlider
	st.value = 0.8
	st.drag_ended.emit(true)
	var fs := d.rules.season_of("freesia")
	assert_true(fs["mode"] == "stage" and is_equal_approx(float(fs["stage"]), 0.8), "a stage, on release (%s)" % fs)
	(d.find_child("Season_pasture", true, false) as GroundDropTarget).pressed.emit()
	assert_true((d.find_child("Mode_bloom", true, false) as Button).disabled
		and (d.find_child("Mode_stage", true, false) as Button).disabled, "pasture has no flowers: no bloom, no stage")
	var md := d.find_child("MapDate", true, false) as OptionButton
	md.item_selected.emit(7)
	assert_near(d.rules.map_date, GrassPreviewMenu.DAYS[6], 1e-6, "the map's date: fixed at 15 Jul")
	d.free()


## The plugin's context: no GrassBlades → no map; a GrassBlades → its rules file, a save that writes it and
## reloads the grass, and Start from defaults.
func test_the_context() -> void:
	var types := GrassTypes.new()
	assert_eq(GroundRulesDialog.context_for(null, types, UxComponents, Callable())["map"], "", "no GrassBlades: no map")
	var b := GrassBlades.new()
	var p := OS.get_temp_dir().path_join("ground_rules_ctx_%d.json" % Time.get_ticks_usec())
	b.ground_rules_path = p
	var ctx := GroundRulesDialog.context_for(b, types, UxComponents, Callable())
	assert_eq([ctx["path"], ctx["rules"]], [p, null], "its file (none yet)")
	var r: GrassGroundRules = (ctx["start"] as Callable).call()
	assert_true(r != null and r.errors.is_empty(), "Start from defaults: the converter's rules")
	assert_eq((ctx["save"] as Callable).call(r), OK, "save writes the file")
	assert_true(FileAccess.file_exists(p) and b.rules != null, "and the blades reload it")
	DirAccess.remove_absolute(p)
	b.free()


## Modal over the editor (so no click under it paints the terrain, it sits centred, and the overlay does not stay on
## top): the dialog covers the whole window (top level, whatever its parent lays out), is centred, and joins
## the overlay's modal group, which stops the terrain's 3D input and hides the overlay while it is open.
func test_the_dialog_is_modal() -> void:
	var d := _dialog(GrassGroundRules.from_text(JSON.stringify(RULES)))
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame               # the batch runs suites from _initialize: the root enters the tree on a frame
	var root := tree.root
	var host := Control.new()               # a parent that is not the window's size
	host.position = Vector2(30, 20)
	host.size = Vector2(10, 10)
	root.add_child(host)
	host.add_child(d)
	assert_true(d.top_level and d.is_in_group(GroundRulesDialog.UX_MODAL_GROUP), "top level, in the overlay's modal group")
	assert_eq(d.get_global_rect(), root.get_visible_rect(), "it covers the whole window, not its parent")
	root.remove_child(host)
	host.free()


func test_water_kinds() -> void:
	var keep := TestGrassWaterGrowth.use_water_fixture()
	var d := _dialog(GrassGroundRules.from_text(JSON.stringify(RULES)))
	assert_true(_has_text(d, "RULES · 2") and _has_text(d, "WATER · 0"), "the rules and the water kinds, counted apart")
	(d.find_child("NewWater", true, false) as Button).pressed.emit()
	var i := d.rules.rules.size() - 1
	assert_true(d.rules.is_water(i) and d.selected == i, "+ New water kind: a water kind, selected")
	assert_true(d.find_child("Water%d" % i, true, false) != null, "its row under Water")
	assert_true(d.find_child("DefaultGrass", true, false) == null and d.find_child("AddBand", true, false) == null
		and d.find_child("RuleSurfaces", true, false) == null, "a water kind has no surfaces, band or default grass")
	var strip: Array = _tiles(d.find_child("SpeciesStrip", true, false), "ground_species").map(func(t): return t.drag_id)
	assert_true(strip.has("t_lily") and strip.has("t_duck") and not strip.has("pasture"), "its strip: surface species")
	assert_true(_has_text(d, "Floats nothing"), "an empty water kind floats nothing (it inherits no mix)")
	var lily: GroundTile = _tiles(d.find_child("SpeciesStrip", true, false), "ground_species").filter(
		func(t): return t.drag_id == "t_lily")[0]
	lily.pressed.emit()
	assert_eq(d.rules.rules[i]["species"], {"t_lily": 1.0}, "a surface species clicked in")
	(d.find_child("Name", true, false) as LineEdit).text_submitted.emit("Vijver")
	assert_eq(d.rules.rules[i]["name"], "Vijver", "named as its sources' water_kind")
	assert_true(not (d.find_child("Water%d" % i, true, false) as GroundDropTarget)._can_drop_data(Vector2.ZERO,
		{"kind": "ground_surface", "id": "Mud"}), "a surface cannot be dropped on a water kind")
	d.selected = 0
	d.rebuild()
	var ground: Array = _tiles(d.find_child("SpeciesStrip", true, false), "ground_species").map(func(t): return t.drag_id)
	assert_true(not ground.has("t_lily") and ground.has("fern"), "a rule's strip: ground species only")
	assert_eq(GrassTerrainGrowth.from_rules(d.rules).water_names, PackedStringArray(["Vijver"]), "the map floats it")
	d.free()
	GrassBladesConfig.use(keep)
