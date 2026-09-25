# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin
## Waailand in the editor: keeps the preview state (GrassEditorPreview) in the editor's project metadata
## (never in a scene) and puts the "Grass" menu in the 3D editor's toolbar.
## GrassBlades is @tool on its own: without this plugin it still previews, at the default date.

const KEY_DAY := "preview_day"
const KEY_VISIBLE := "preview_visible"
const KEY_ALL_GROUNDS := "preview_all_grounds"
const PROVIDERS := "res://addons/terrain_3d_extended/src/tool_providers.gd"
const UX_COMPONENTS := "res://addons/terrain_3d_extended/src/ux_components.gd"
const PackInspector := preload("res://addons/waailand/editor/species_pack_inspector.gd")

var _menu: GrassPreviewMenu
var _paint: GrassPaintProvider
var _dialog: GroundRulesDialog = null
var _blades_root: Node = null        # the edited scene _blades_found was found in
var _blades_found: GrassBlades = null
var _pack_inspector: EditorInspectorPlugin = null   # a species pack's pictures


func _enter_tree() -> void:
	var es := EditorInterface.get_editor_settings()
	GrassEditorPreview.day = float(es.get_project_metadata(GrassEditorPreview.SECTION, KEY_DAY, GrassEditorPreview.DEFAULT_DAY))
	GrassEditorPreview.visible = bool(es.get_project_metadata(GrassEditorPreview.SECTION, KEY_VISIBLE, true))
	GrassEditorPreview.all_grounds = bool(es.get_project_metadata(GrassEditorPreview.SECTION, KEY_ALL_GROUNDS, false))
	_menu = GrassPreviewMenu.new()
	_menu.changed.connect(_save)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
	_pack_inspector = PackInspector.new()
	add_inspector_plugin(_pack_inspector)
	_register_paint.call_deferred()


func _exit_tree() -> void:
	if _pack_inspector != null:
		remove_inspector_plugin(_pack_inspector)
		_pack_inspector = null
	if _paint != null and ResourceLoader.exists(PROVIDERS):
		load(PROVIDERS).unregister(_paint)
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_paint = null
	if _menu != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
		_menu.queue_free()
		_menu = null


func _save() -> void:
	var es := EditorInterface.get_editor_settings()
	es.set_project_metadata(GrassEditorPreview.SECTION, KEY_DAY, GrassEditorPreview.day)
	es.set_project_metadata(GrassEditorPreview.SECTION, KEY_VISIBLE, GrassEditorPreview.visible)
	es.set_project_metadata(GrassEditorPreview.SECTION, KEY_ALL_GROUNDS, GrassEditorPreview.all_grounds)


## The grass paint tool lives in the Terrain3D Extended overlay: without it there is none (Terrain3D's own "Side Map"
## button paints nothing grass-specific).
func _register_paint() -> void:
	if not ResourceLoader.exists(PROVIDERS):
		return
	_paint = GrassPaintProvider.new(GrassTypes.new())
	_paint.preview_changed.connect(_on_preview_changed)
	_paint.set_undo(get_undo_redo())
	_paint.blades_of = _blades
	_paint.ground_rules_requested.connect(_open_ground_rules)
	_paint.map_date = func() -> float:
		var b := _blades()
		return b.season.map_date if b != null else -1.0
	load(PROVIDERS).register(_paint)


## The scene save also writes the painted grass maps: every GrassMaps with
## unsaved changes, a background scene tab's included (GrassMaps' registry).
func _save_external_data() -> void:
	for m in GrassMaps.unsaved_maps():
		var out: Dictionary = (m as GrassMaps).save_dirty()
		for loc in out:
			if out[loc] != OK:
				push_error("Waailand: the grass map of region %s was not saved (%s)" % [loc, error_string(out[loc])])


## The prompt closing a scene (its maps) or quitting ("": any).
func _get_unsaved_status(p_for_scene: String) -> String:
	return "Save the painted grass maps?" if not GrassMaps.unsaved_for(p_for_scene).is_empty() else ""


func _on_preview_changed() -> void:
	_save()
	if _menu != null:
		_menu.sync()


## The edited scene's GrassBlades (null: the open map has no grass). Kept per edited scene: the Grass panel asks on each
## rebuild, and walking a whole map scene (all its roads and props) each time would be slow.
func _blades() -> GrassBlades:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if root == _blades_root and is_instance_valid(_blades_found) and root.is_ancestor_of(_blades_found):
		return _blades_found
	_blades_root = root
	_blades_found = root as GrassBlades
	if _blades_found == null:
		for n in root.find_children("*", "", true, false):
			if n is GrassBlades:
				_blades_found = n
				break
	return _blades_found


## The Ground rules dialog for the open map, over the editor (the overlay's host: Godot 4.8 hides the main screen).
func _open_ground_rules() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		return
	_dialog = GroundRulesDialog.new()
	_dialog.setup(GroundRulesDialog.context_for(_blades(), _paint.types, load(UX_COMPONENTS), _paint.picture_of))
	_dialog.closed.connect(func() -> void:
		_dialog = null
		_paint._refresh())
	EditorInterface.get_base_control().add_child(_dialog)
