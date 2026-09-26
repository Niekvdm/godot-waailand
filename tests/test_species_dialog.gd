# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestSpeciesDialog
extends GrassSuite
## The Species dialog, headless: the pack tree, its filters and search, the slots (the fallback's frame, a missing
## species, the names not active), drops on an empty and a filled slot with the question, a pack all or nothing, the
## refusals (the slot and the meter red), the slot menu, dragging a slot out, undo and redo, the hover card, and the
## plugin's context writing the table; against fixture packs and a save that records what it was given.

const UxComponents := preload("res://addons/terrain_3d_extended/src/ux_components.gd")

var saved: Array = []


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestSpeciesDialog.new(), "species_dialog")


static func _sp(id: String, kinds := 0, extra := {}) -> GrassSpecies:
	var s := GrassSpecies.new()
	s.id = StringName(id)
	for i in kinds:
		var d := GrassDecoration.new()
		d.name = StringName("%s_%d" % [id, i])
		s.decorations.append(d)
	for k in extra:
		s.set(k, extra[k])
	return s


static func _pack(nm: String, species: Array) -> GrassSpeciesPack:
	var p := GrassSpeciesPack.new()
	p.name = nm
	p.species.assign(species)
	return p


## Bulbs (a project pack: three species of 11 flower kinds), the Pond set (an addon: its ground and its water pack),
## the starter grass.
func _sources() -> Array:
	var bulbs := _pack("Bulbs", [_sp("tulips", 11), _sp("crocus", 11, {"display_name": "Spring crocus"}),
		_sp("hyacinth", 11)])
	return [
		{"name": "Bulbs", "kind": "project", "path": "res://bulbs.tres", "packs": [bulbs]},
		{"name": "Pond set", "kind": "addon", "path": "res://addons/pond/waailand_packs.tres", "packs": [
			_pack("Pond ground", [_sp("reed", 0, {"wet_depth_m": 0.4}), _sp("sedge")]),
			_pack("Pond water", [_sp("lily", 2, {"layer": GrassSpecies.Layer.SURFACE}),
				_sp("weed", 0, {"depth_m": Vector2(0.3, 3.0)})])]},
		{"name": "Starter grass", "kind": "waailand", "path": "res://starter.tres", "packs": [
			_pack("Starter", [_sp("lawn", 1), _sp("meadow", 2)])]}]


func _save(a: GrassActiveSet) -> Error:
	saved.append([a.to_table(), a.fallback])
	return OK


## lawn (the fallback) and meadow active, and "gone", which no pack has any more, in slot 5.
func _dialog(table := {"lawn": 0, "meadow": 1, "gone": 5}, fallback := &"lawn") -> GrassSpeciesDialog:
	saved = []
	var srcs := _sources()
	var installed := []
	for s in srcs:
		for p in s["packs"]:
			installed.append_array((p as GrassSpeciesPack).species)
	var d := GrassSpeciesDialog.new()
	d.setup({"active": GrassActiveSet.new(installed, table, fallback), "sources": srcs, "kit": UxComponents,
		"path": "res://grass_species_slots.json", "save": _save,
		"uses": {"the growth table": {"slots": {"X": {"density": 1.0, "species": {"reed": 1.0, "lawn": 1.0, "nope": 1.0}}}}}})
	return d


static func _has_text(n: Node, text: String) -> bool:
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).text.contains(text):
			return true
	return false


static func _library_ids(d: GrassSpeciesDialog) -> Array:
	return d.find_child("Library", true, false).find_children("*", "", true, false).filter(
		func(c): return c is GrassSpeciesTile).map(func(t): return String(t.id))


static func _slot(d: GrassSpeciesDialog, i: int) -> GrassSpeciesTile:
	return d.find_child("Slot%d" % i, true, false) as GrassSpeciesTile


func _key(d: GrassSpeciesDialog, code: Key, ctrl := false, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	d._input(k)


func test_the_tree_filters_and_search() -> void:
	var d := _dialog()
	assert_true(_has_text(d, "Species 3/32") and _has_text(d, "Flower kinds 3/32"), "the meters: slots and flower kinds")
	assert_true(_has_text(d, "INSTALLED · 9 SPECIES IN 4 PACKS"), "what is installed")
	assert_eq(_library_ids(d), [], "the packs start closed")
	assert_true(d.find_child("Source_Pond set", true, false) != null and d.find_child("Pack_Pond water", true, false) != null,
		"an addon's row, and its packs under it")
	assert_true(_has_text(d.find_child("Source_Pond set", true, false), "0/4 active"), "a row counts its active species")
	(d.find_child("Pack_Starter", true, false).find_child("Toggle", true, false) as Button).pressed.emit()
	assert_eq(_library_ids(d), ["lawn", "meadow"], "a row opened: its species")
	var lawn := d.find_child("Species_lawn", true, false) as GrassSpeciesTile
	assert_true(lawn.active and lawn.modulate.a < 1.0 and lawn.kinds == 1, "an active species dimmed; its flower count")
	d.filter = "float"
	d.rebuild()
	assert_eq(_library_ids(d), ["lily"], "Floating: the floating species, their packs open")
	assert_eq((d.find_child("Species_lily", true, false) as GrassSpeciesTile).layer, "float", "its corner fold")
	d.filter = "ground"
	d.rebuild()
	assert_eq(_library_ids(d), ["tulips", "crocus", "hyacinth", "reed", "sedge", "lawn", "meadow"],
		"Ground: the wet ground species too")
	d.filter = "under"
	d.rebuild()
	assert_eq(_library_ids(d), ["weed"], "Underwater")
	d.filter = "inactive"
	d.rebuild()
	assert_eq(_library_ids(d), ["tulips", "crocus", "hyacinth", "reed", "sedge", "lily", "weed"], "Not active")
	d.filter = "all"
	d.search = "spring"
	d.rebuild()
	assert_eq(_library_ids(d), ["crocus"], "the search finds a display name")
	d.search = "WEE"
	d.rebuild()
	assert_eq(_library_ids(d), ["weed"], "and an id, in any case")
	d.search = "zzz"
	d.rebuild()
	assert_true(_has_text(d, "No installed species match."), "nothing found says so")
	d.free()


func test_the_slots() -> void:
	var d := _dialog()
	var s0 := _slot(d, 0)
	assert_true(s0.id == &"lawn" and s0.fallback, "the fallback in its frame")
	var s5 := _slot(d, 5)
	assert_true(s5.missing and s5.tooltip_text.contains("not installed"), "a species no pack has any more: missing")
	assert_eq(_slot(d, 7).id, &"", "an empty slot")
	assert_true(_has_text(d, "Ground 3 · Underwater 0 · Floating 0"), "the layer counts")
	assert_true(_has_text(d, "grow nothing: reed (the growth table).") and not _has_text(d, "nope"),
		"the installed names that are not active (a name nothing installs is not one)")
	assert_eq(s0._get_drag_data(Vector2.ZERO), {"kind": "waailand_slot", "slot": 0, "id": "lawn"}, "a slot drags itself")
	assert_true(s0._can_drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "reed"})
		and s0._can_drop_data(Vector2.ZERO, {"kind": "waailand_pack", "ids": [], "name": "x"})
		and not s0._can_drop_data(Vector2.ZERO, {"kind": "waailand_slot", "slot": 1, "id": "meadow"}),
		"a slot takes a species or a pack, not another slot")
	assert_eq(s0.mouse_filter, Control.MOUSE_FILTER_PASS, "a drop past a tile reaches the area around it")
	var t := GrassSpeciesTile.make(&"reed", null, "Reed", -1, "wet", 0)
	assert_eq(t._get_drag_data(Vector2.ZERO), {"kind": "waailand_species", "id": "reed"}, "a library tile drags its species")
	assert_true(not t._can_drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "lawn"}), "and takes nothing")
	t.free()
	d.free()


func test_drops_replace_and_refusals() -> void:
	var d := _dialog()
	_slot(d, 3)._drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "reed"})
	assert_eq([d.active.slot_of(&"reed"), saved.size()], [3, 1], "onto an empty slot: active there, written")
	assert_true(not _has_text(d, "reed (the growth table)"), "and named but not active no more")
	(d.find_child("Grid", true, false) as GrassSpeciesDropArea)._drop_data(Vector2.ZERO,
		{"kind": "waailand_species", "id": "sedge"})
	assert_eq(d.active.slot_of(&"sedge"), 2, "onto the grid's free space: the first free slot")
	_slot(d, 0)._drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "weed"})
	assert_eq([d.active.slots[0], saved.size()], [&"lawn", 2], "onto a filled slot: nothing yet")
	assert_true(_has_text(d, "Replace lawn in slot 0 with weed? Grass painted as lawn on any map will grow as weed."),
		"it asks, saying what painted grass will do")
	(d.find_child("Cancel", true, false) as Button).pressed.emit()
	assert_true(d.pending.is_empty() and d.find_child("Confirm", true, false) == null and d.active.slots[0] == &"lawn",
		"Cancel")
	_slot(d, 0)._drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "weed"})
	(d.find_child("Replace", true, false) as Button).pressed.emit()
	assert_eq([d.active.slots[0], d.active.slot_of(&"lawn"), d.active.fallback, saved.size()], [&"weed", -1, &"", 3],
		"Replace: weed in, lawn out, the fallback with it")
	d.search = "tulips"
	d.rebuild()
	(d.find_child("Species_tulips", true, false) as GrassSpeciesTile).activated.emit()
	assert_eq(d.active.slot_of(&"tulips"), 4, "a double-click: the first free slot")
	d.search = ""
	_slot(d, 6)._drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "crocus"})
	assert_eq(d.active.used_kinds(), 24, "24 flower kinds")
	_slot(d, 7)._drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "hyacinth"})
	assert_eq([d.active.slot_of(&"hyacinth"), saved.size()], [-1, 5], "past 32 flower kinds: refused, nothing written")
	assert_true(_has_text(d, "hyacinth brings 11 flower kinds; 8 of 32 are free."), "saying what it brings and what is free")
	assert_eq(_slot(d, 7).ring, GrassSpeciesDialog.ERROR, "the slot it aimed at red")
	assert_eq((d.find_child("MeterKinds", true, false) as Label).get_theme_color("font_color"), GrassSpeciesDialog.ERROR,
		"and the flower kinds meter")
	assert_true((d.find_child("MeterSpecies", true, false) as Label).get_theme_color("font_color") != GrassSpeciesDialog.ERROR,
		"not the species meter")
	var grip := d.find_child("Source_Pond set", true, false).find_child("Grip", true, false)
	var data: Dictionary = grip._get_drag_data(Vector2.ZERO)
	assert_eq([data["kind"], data["name"], data["ids"]], ["waailand_pack", "Pond set", [&"reed", &"sedge", &"lily", &"weed"]],
		"a pack's handle drags all its species")
	(d.find_child("Grid", true, false) as GrassSpeciesDropArea)._drop_data(Vector2.ZERO, data)
	assert_eq([d.active.slot_of(&"lily"), saved.size(), d.error], [7, 6, ""], "dropped: its inactive species fill free slots")
	(d.find_child("Pack_Bulbs", true, false).find_child("AddAll", true, false) as Button).pressed.emit()
	assert_eq(d.error, "Bulbs doesn't fit. It needs 1 slot and 11 flower kinds; 24 slots and 6 kinds are free. "
		+ "Drag single species, or free kinds first.", "+ all that does not fit: refused, saying why")
	assert_eq([d.active.slot_of(&"hyacinth"), saved.size()], [-1, 6], "all or nothing")
	d.free()


func test_menu_drag_out_undo_and_keys() -> void:
	var d := _dialog()
	d.menu_action(1, GrassSpeciesDialog.Menu.FALLBACK)
	assert_eq([d.active.fallback, saved.size()], [&"meadow", 1], "Make fallback")
	assert_true(_slot(d, 1).fallback and not _slot(d, 0).fallback, "its frame moves")
	d.menu_action(1, GrassSpeciesDialog.Menu.SHOW)
	var meadow := d.find_child("Species_meadow", true, false) as GrassSpeciesTile
	assert_true(meadow != null and meadow.ring == Color.WHITE, "Show in the library: its pack opens, the species marked")
	(d.find_child("Library", true, false) as GrassSpeciesDropArea)._drop_data(Vector2.ZERO,
		{"kind": "waailand_slot", "slot": 5, "id": "gone"})
	assert_eq([d.active.slots[5], saved.size()], [&"", 2], "a slot dragged out onto the library: emptied (a missing one too)")
	d.menu_action(0, GrassSpeciesDialog.Menu.EMPTY)
	assert_eq(d.active.slot_of(&"lawn"), -1, "Empty the slot")
	_key(d, KEY_Z, true)
	assert_eq(d.active.slot_of(&"lawn"), 0, "Ctrl+Z")
	_key(d, KEY_Z, true)
	assert_eq(d.active.slots[5], &"gone", "and again")
	_key(d, KEY_Y, true)
	assert_eq(d.active.slots[5], &"", "Ctrl+Y")
	assert_eq(saved[-1], [{"lawn": 0, "meadow": 1}, &"meadow"], "every step written")
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(d)
	d.open_slot_menu(1, Vector2(40, 40))
	var m := d.find_child("SlotMenu", true, false) as PopupMenu
	assert_true(m != null and m.item_count == 3 and m.is_item_disabled(m.get_item_index(GrassSpeciesDialog.Menu.FALLBACK)),
		"the menu, Make fallback off for the fallback")
	m.id_pressed.emit(GrassSpeciesDialog.Menu.EMPTY)
	assert_eq(d.active.slot_of(&"meadow"), -1, "its Empty the slot")
	root.remove_child(d)
	_slot(d, 0)._drop_data(Vector2.ZERO, {"kind": "waailand_species", "id": "weed"})
	var closed := [0]
	d.closed.connect(func() -> void: closed[0] += 1)
	_key(d, KEY_ESCAPE)
	assert_true(d.pending.is_empty() and closed[0] == 0, "Esc drops the question first")
	_key(d, KEY_ESCAPE)
	assert_eq(closed[0], 1, "then closes")


func test_the_card() -> void:
	var d := _dialog()
	var texts := func(c: Control) -> Array:
		return c.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	var lily := d.card_for(&"lily")
	var t: Array = texts.call(lily)
	assert_true(t.has("Floats on water") and t.has("Not active"), "an installed species: its layer, not active (%s)" % [t])
	assert_true(not t.any(func(s): return String(s).contains("grows it") or String(s).begins_with("Grows on")),
		"no ground line: the growth is the map's")
	lily.free()
	var lawn := d.card_for(&"lawn")
	assert_true((texts.call(lawn) as Array).has("Active in slot 0 (the fallback)"), "an active one: its slot")
	lawn.free()
	assert_true(d.card_for(&"gone") == null, "a missing one has none")
	d.free()


func test_inactive_names() -> void:
	var a := GrassActiveSet.new([_sp("a"), _sp("b"), _sp("c")], {"a": 0})
	var out := GrassSpeciesDialog.inactive_names(a, {
		"the growth table": {"default_species": {"b": 1.0}, "slots": {"X": {"species": {"a": 1.0, "c": 1.0},
			"bands": [{"above_m": 5.0, "species": {"b": 1.0}}]}}},
		"this map's ground rules": {"rules": [{"species": {"c": 1.0, "zz": 1.0}}]}})
	assert_eq(out, PackedStringArray(["b (the growth table)", "c (the growth table, this map's ground rules)"]),
		"every mix, band and default; only installed names; where each is named")


func test_the_plugins_context_writes_the_table() -> void:
	var keep := GrassBladesConfig.current()
	var cfg := GrassBladesConfig.new()
	cfg.packs.assign([_pack("ctx fixture", [_sp("ctx_lawn"), _sp("ctx_reed")])])
	cfg.disabled_packs = GrassBladesConfig.discovered_set_paths() + PackedStringArray([cfg.starter_pack_path()])
	var p := "user://test_species_dialog_slots.json"
	GrassSlotTable.save_file(p, {"ctx_lawn": 0})
	cfg.slots_path = p
	cfg.default_mix = {"ctx_reed": 1.0}
	GrassBladesConfig.use(cfg)
	var fired := [0]
	var gen := GrassSpeciesCatalog.generation
	var ctx := GrassSpeciesDialog.context_for(UxComponents, null, Callable(), func() -> void: fired[0] += 1)
	assert_eq((ctx["sources"] as Array).map(func(s): return s["name"]), ["ctx fixture"], "the installed packs")
	var a: GrassActiveSet = ctx["active"]
	assert_eq([a.slot_of(&"ctx_lawn"), a.is_installed(&"ctx_reed")], [0, true], "the table, among the installed")
	assert_eq(GrassSpeciesDialog.inactive_names(a, ctx["uses"]), PackedStringArray(["ctx_reed (the config's default mix)"]),
		"the config's default mix naming an inactive species")
	a.place(&"ctx_reed", 4)
	a.set_fallback(&"ctx_reed")
	assert_eq((ctx["save"] as Callable).call(a), OK, "saved")
	assert_eq([GrassSlotTable.load_file(p), GrassSlotTable.load_fallback(p)], [{"ctx_lawn": 0, "ctx_reed": 4}, &"ctx_reed"],
		"the table written, its fallback too")
	assert_eq([fired[0], GrassSpeciesCatalog.generation], [1, gen + 1], "the grass told; the generation moved on")
	DirAccess.remove_absolute(p)
	GrassBladesConfig.use(keep)
