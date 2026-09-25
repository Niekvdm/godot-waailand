# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassPictureTool
extends RefCounted
## The picture tool as the editor launches it: a pack's missing and stale
## pictures, rendered in a separate, off-screen window (the renderer needs forced frames, which the editor cannot give).
## On Linux the window gets its own user data folder, so a project's autoloads write nothing of the user's.

const SCENE := "res://addons/waailand/tools/render_pictures.tscn"


## The tool's command line for a pack: this project, off screen, the pack's stale pictures.
static func args_for(p_pack_path: String) -> PackedStringArray:
	return PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--position", "-6000,-6000", SCENE,
		"--", "--pack", p_pack_path, "--stale"])


## The pack's species whose pictures are missing or stale (all of them for a pack that is not a file).
static func stale_of(p_pack: GrassSpeciesPack) -> PackedStringArray:
	var t := GrassPictureRenderer.tables(p_pack)
	var dir := GrassSpeciesPreview.pack_pictures_dir(p_pack)
	if dir == "":
		var out := PackedStringArray()
		for e in GrassPaintTool.palette(t[0]):
			out.append(String(e["name"]))
		return out
	return GrassSpeciesPreview.stale(t[0], t[1], GrassTerrainGrowth.new(), dir)


## Starts the tool on a pack; the process id (-1: it did not start).
static func launch(p_pack_path: String) -> int:
	var linux := OS.get_name() == "Linux"
	var keep := OS.get_environment("XDG_DATA_HOME")
	if linux:
		var tmp := OS.get_temp_dir().path_join("grass_pictures_%d" % Time.get_ticks_usec())
		DirAccess.make_dir_recursive_absolute(tmp)
		OS.set_environment("XDG_DATA_HOME", tmp)
	var pid := OS.create_process(OS.get_executable_path(), args_for(p_pack_path))
	if linux:
		if keep == "":
			OS.unset_environment("XDG_DATA_HOME")
		else:
			OS.set_environment("XDG_DATA_HOME", keep)
	return pid
