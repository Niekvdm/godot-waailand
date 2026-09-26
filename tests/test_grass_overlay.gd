# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassOverlay
extends GrassSuite
## The paint overlay (GrassOverlay, drawn by grass_far.gdshaderinc): what a texel shows in each mode (the shader's fill,
## mirrored), the colors the shader is sent, the legend, and what the preview does while it shows.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassOverlay.new(), "grass_overlay")


func test_painted() -> void:
	var M := GrassOverlay.Mode.PAINTED
	assert_eq(GrassOverlay.fill(M, GrassMaps.NEUTRAL).a, 0.0, "the ground's own: clear")
	assert_eq(GrassOverlay.fill(M, Color8(128, 255, 128, 255)), Color(GrassOverlay.REMOVED, GrassOverlay.ALPHA),
		"removed: red")
	assert_eq(GrassOverlay.fill(M, Color8(128, 5, 128, 255)), Color(GrassOverlay.species_color(4), GrassOverlay.ALPHA),
		"a painted species: its slot's tint")
	assert_eq(GrassOverlay.fill(M, Color8(40, 0, 220, 255)).a, 0.0, "density and height have their own modes")
	assert_eq(GrassOverlay.marks(Color8(128, 0, 128, 0)), GrassOverlay.MARK_FORCED, "forced: the orange stripes")
	assert_eq(GrassOverlay.marks(Color8(128, 5, 128, 128 + 3)), GrassOverlay.MARK_COLOR, "a painted flower color: dots")
	assert_eq(GrassOverlay.marks(Color8(128, 5, 128, 127)), GrassOverlay.MARK_FORCED, "127: forced, its color Auto (no dots)")
	assert_eq(GrassOverlay.marks(Color8(128, 5, 128, 2)), GrassOverlay.MARK_FORCED | GrassOverlay.MARK_COLOR, "both")


func test_heat() -> void:
	var D := GrassOverlay.Mode.DENSITY
	var H := GrassOverlay.Mode.HEIGHT
	assert_eq(GrassOverlay.fill(D, GrassMaps.NEUTRAL).a, 0.0, "x1: clear")
	var thin := GrassOverlay.fill(D, Color8(64, 0, 128, 255))
	var thick := GrassOverlay.fill(D, Color8(255, 0, 128, 255))
	assert_true(Color(thin, 1.0) == Color(GrassOverlay.LESS, 1.0) and Color(thick, 1.0) == Color(GrassOverlay.MORE, 1.0),
		"thinner blue, thicker warm")
	assert_true(thin.a > 0.3 and thick.a > thin.a, "stronger the further from x1 (%.2f, %.2f)" % [thin.a, thick.a])
	assert_near(GrassOverlay.fill(D, Color8(0, 0, 128, 255)).a, GrassOverlay.ALPHA_HEAT.y, 1e-6, "none at all: the most")
	assert_eq(Color(GrassOverlay.fill(H, Color8(128, 0, 40, 255)), 1.0), Color(GrassOverlay.LESS, 1.0), "shorter blue")
	assert_eq(GrassOverlay.fill(H, Color8(40, 0, 128, 255)).a, 0.0, "Height reads B alone")
	assert_eq(GrassOverlay.marks(Color8(128, 255, 128, 255), D), GrassOverlay.MARK_REMOVED,
		"removed shows in the heat modes too (hatched: nothing grows, whatever the numbers)")


func test_colors_and_legend() -> void:
	var hues := GrassOverlay.hues_linear()
	assert_eq(hues.size(), GrassTypes.SLOTS, "a tint per slot")
	var distinct := {}
	for i in GrassTypes.SLOTS:
		var c := GrassOverlay.species_color(i)
		distinct[c.to_html()] = true
		assert_true(c.h >= 0.14 and c.h <= 0.91, "slot %d stays clear of removed's red and forced's orange (%.2f)" % [i, c.h])
	assert_eq(distinct.size(), GrassTypes.SLOTS, "every slot its own tint")
	assert_eq(GrassOverlay.key_linear().size(), 4, "removed, forced, less, more")
	var keep := GrassSuite.use_fixture_species()
	var types := GrassTypes.new()
	var leg := GrassOverlay.legend(GrassOverlay.Mode.PAINTED, types)
	var labels := leg.map(func(e: Array) -> String: return e[1])
	assert_true(labels.slice(0, 3) == ["Removed", "Forced (stripes)", "A painted flower color (dots)"],
		"the marks first: %s" % [labels.slice(0, 3)])
	var verge := types.names().find("verge")
	assert_true(verge >= 0 and leg.any(func(e: Array) -> bool: return e[1] == "verge" and e[0] == GrassOverlay.species_color(verge)),
		"then each species with its tint")
	assert_eq(labels.size(), 3 + Array(types.names()).filter(func(n: String) -> bool: return n != "").size(),
		"only the slots in use")
	assert_eq(GrassOverlay.legend(GrassOverlay.Mode.HEIGHT, types).map(func(e: Array) -> String: return e[1]),
		["Shorter", "Taller"], "Height's key")
	GrassBladesConfig.use(keep)


func test_preview_state() -> void:
	var keep := [GrassEditorPreview.overlay, GrassEditorPreview.visible]
	GrassEditorPreview.visible = true
	GrassEditorPreview.overlay = GrassOverlay.Mode.OFF
	assert_true(GrassEditorPreview.grass_shows(), "no overlay: the grass as the eye says")
	GrassEditorPreview.overlay = GrassOverlay.Mode.DENSITY
	assert_true(not GrassEditorPreview.grass_shows(), "the overlay hides the grass: the ground reads clearly")
	GrassEditorPreview.overlay = GrassOverlay.Mode.OFF
	GrassEditorPreview.visible = false
	assert_true(not GrassEditorPreview.grass_shows(), "and the eye still hides it")
	GrassEditorPreview.overlay = keep[0]
	GrassEditorPreview.visible = keep[1]
