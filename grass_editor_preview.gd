# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassEditorPreview
extends RefCounted
## The editor preview's state: the day of the year the grass shows, whether it shows, whether every ground grows, and
## the paint overlay (GrassOverlay), which hides the grass while it shows.
## GrassBlades in editor mode reads it every frame; the plugin's "Grass" menu sets it and keeps it in the editor's
## project metadata (section SECTION, never a scene). Plain statics, no editor API: the game
## and the tests load this too.

const SECTION := "grass_blades"
const DEFAULT_DAY := 104.0          # 15 April: the spring flowers are out

static var day := DEFAULT_DAY
static var visible := true
static var all_grounds := false       # every ground grows (the preview only: the game never reads it)
static var all_bloom := false         # every species with flowers in bloom (the preview only: GrassSeasonPlan.all_bloom)
static var overlay := 0               # the paint overlay's GrassOverlay.Mode (OFF: none; the preview only)
static var overlay_mode := 1          # the mode the overlay's switch turns on (the last chosen)


## The grass shows: the eye is on and the overlay is off.
static func grass_shows() -> bool:
	return visible and overlay == 0
