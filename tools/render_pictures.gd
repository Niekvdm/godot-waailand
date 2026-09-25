# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
extends Node
## Renders a species pack's pictures into <pack folder>/pictures: <id>.png (the
## 112 px tile), <id>_card.png (360 x 240) and stamps.json (what each was made from). Windowed (the grass needs a GPU),
## forced frames:
##   godot --position -6000,-6000 res://addons/waailand/tools/render_pictures.tscn -- --pack <res://…/pack.tres>
##     --only a,b      just these species (the others' pictures and stamps stay)
##     --stale         just the missing or stale ones
##     --sheet PATH    also a contact sheet of the cards drawn this run
## The pack's inspector launches it (GrassPictureTool).


func _ready() -> void:
	RenderingServer.render_loop_enabled = false      # forced frames only
	var args := OS.get_cmdline_user_args()
	var only := PackedStringArray()
	var sheet_path := ""
	var pack_path := ""
	for i in args.size() - 1:
		match args[i]:
			"--only": only = args[i + 1].split(",")
			"--sheet": sheet_path = args[i + 1]
			"--pack": pack_path = args[i + 1]
	get_tree().physics_interpolation = false
	await get_tree().process_frame
	for n in get_tree().root.get_children():         # a project's autoload HUDs and props out of the picture
		if n == self:
			continue
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		elif n is Node3D:
			(n as Node3D).visible = false
	var pack := load(pack_path) as GrassSpeciesPack if pack_path != "" and ResourceLoader.exists(pack_path) else null
	var dir := GrassSpeciesPreview.pack_pictures_dir(pack)
	if pack == null or dir == "":
		print("[pictures] no species pack at '%s' (--pack res://…/pack.tres)" % pack_path)
		get_tree().quit(2)
		return
	var t := GrassPictureRenderer.tables(pack)
	var types: GrassTypes = t[0]
	var kinds: DecoKinds = t[1]
	var growth := GrassTerrainGrowth.new()
	var abs_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if not FileAccess.file_exists(abs_dir.path_join(".gdignore")):
		FileAccess.open(abs_dir.path_join(".gdignore"), FileAccess.WRITE).close()   # loaded as images, never imported
	if args.has("--stale"):
		only = GrassSpeciesPreview.stale(types, kinds, growth, dir)
		print("[pictures] stale: %s" % ", ".join(only))
		if only.is_empty():
			print("[pictures] done: 0")
			get_tree().quit(0)
			return
	var vp := SubViewport.new()
	vp.size = GrassPictureRenderer.SHOT
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = false
	add_child(vp)
	var stamps := GrassSpeciesPreview.stamps(dir)
	var cards: Array[Image] = []
	for e in GrassPaintTool.palette(types):
		var nm := String(e["name"])
		if not only.is_empty() and not only.has(nm):
			continue
		var slot := int(e["slot"])
		var img: Image = await GrassPictureRenderer.render(vp, pack, types, kinds, growth, slot)
		GrassPictureRenderer.save(img, dir, nm)
		stamps[nm] = GrassSpeciesPreview.stamp(types, kinds, growth, slot)
		var card := img.duplicate() as Image
		card.resize(GrassPictureRenderer.CARD.x, GrassPictureRenderer.CARD.y, Image.INTERPOLATE_LANCZOS)
		cards.append(card)
		print("[pictures] %s: %s" % [nm, GrassSpeciesPreview.recipe(types, kinds, growth, slot)])
	var keys := stamps.keys()
	keys.sort()
	var ordered := {}
	for k in keys:
		ordered[k] = stamps[k]
	var f := FileAccess.open(abs_dir.path_join(GrassSpeciesPreview.STAMPS), FileAccess.WRITE)
	f.store_string(JSON.stringify(ordered, "\t") + "\n")
	f.close()
	if sheet_path != "" and not cards.is_empty():
		_sheet(cards).save_png(sheet_path)
		print("[pictures] sheet %s" % sheet_path)
	print("[pictures] done: %d" % cards.size())
	get_tree().quit(0)


## The cards in rows of four.
static func _sheet(cards: Array[Image]) -> Image:
	var cw := cards[0].get_width()
	var ch := cards[0].get_height()
	var cols := mini(4, cards.size())
	var rows := (cards.size() + cols - 1) / cols
	var sheet := Image.create_empty(cw * cols, ch * rows, false, Image.FORMAT_RGB8)
	for i in cards.size():
		sheet.blit_rect(cards[i], Rect2i(Vector2i.ZERO, Vector2i(cw, ch)), Vector2i((i % cols) * cw, (i / cols) * ch))
	return sheet
