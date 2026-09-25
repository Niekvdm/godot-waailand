# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassEditorPreview
extends RefCounted
## The editor preview's state: the day of the year the grass shows, whether it shows, and whether every ground grows.
## GrassBlades in editor mode reads it every frame; the plugin's "Grass" menu sets it and keeps it in the editor's
## project metadata (section SECTION, never a scene). Plain statics, no editor API: the game
## and the tests load this too.

const SECTION := "grass_blades"
const DEFAULT_DAY := 104.0          # 15 April: the spring flowers are out

static var day := DEFAULT_DAY
static var visible := true
static var all_grounds := false       # every ground grows (the preview only: the game never reads it)
