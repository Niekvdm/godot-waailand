# Changelog

## Unreleased

- The grass remembers the air (`air_memory`, on by default; `GrassAirField`, `air_step.glsl`,
  `grass_air.gdshaderinc`): a camera-centred window of springs, one per half-metre patch, integrated each frame toward
  the air's equilibrium lean. The shaders add only its deviation, so a steady wind looks as before; a gust or a
  rotor now lays the grass with a lag, a released patch rebounds past upright once, and grass a hovering rotor held
  flat (matted) creeps back up over a few seconds. `wind.calm()` settles it. `readback()` returns it as `"air"`.
- The wind and a rotor's downwash are one flow of air. The wall jet joins the wind (m/s), so each species leans by
  its own wind response (a rigid one stands, a meadow lies over), faces comb outward along the jet, and upwind of a
  rotor the wind and the wash no longer bend a blade two ways. The lean saturates (a soft minimum toward 1.35 rad):
  a breeze leans exactly as before, a gale lays the grass without folding it past flat, and a heavy load folds a
  blade at its root, blowing away the rest tilt that pointed into it. Only the column under the disc still presses
  as a hinge. The wash buffets at two frequencies per plant; the sway gets a cross-wind loop; a flower's plume
  flutter follows the air (it fluttered in still air). The outwash profile peaks at 1.7-2 rotor radii (NASA's
  outwash measurements) and reaches 4 footprints. New in `grass_wash.gdshaderinc`: `grass_wash_air`,
  `grass_wash_buffet`; `grass_wash_lean` stays for other callers.
- The fine gusts: the waves running through a field travel at the wind's own velocity (`wind_honami`, a finer octave
  of the gust texture on a flow map, TIME-driven so it carries motion vectors). They replace the sway ripple, which ran
  at ~20 m/s whatever the wind; each plant's sway now has its own phase. `GrassWindState.honami_vel` (eased);
  `anchor`, `ripple_term`, `ripple_origin`, `ripple_phase` and `wave_k` are deprecated (the shaders no longer read
  them).
- The flowers read the gust field: their materials never got it, so every flower leaned at a full gust and 0.9 rad off
  the wind whatever the field did.
- `GrassWindState.for_speed` grows to 20 m/s (`GALE_M_S`); it stopped at 7.2 m/s, so a gale looked like a stiff
  breeze.
- Every TIME-driven frequency fits TIME's rollover (`grass_time.gdshaderinc`, `rollover_hz`; GrassWindState sends
  the project's `time_rollover_secs`): every plant's sway jumped once an hour.
- `wind.calm()` holds: the tuning's easing brought the wind back within ~0.3 s (pictures, bakes and tests rendered
  swaying grass). The eased target lives in GrassWindState (`set_tuning`, `ease_tuning`).
- Wind: blades no longer snap to another angle as the wind veers. The comb (a blade turning its face into the local
  wind) flipped a blade by up to 180 degrees in one frame when the swirled wind crossed its face's perpendicular; the
  turn now tapers to zero there, so the blade turns smoothly (`wind_comb_turn`, `GrassWindState.comb_turn`).

## 1.5.0 (2026-09-26)

Needs Terrain3D Extended 1.2 (the plugin says so and leaves the Grass workspace off on an older one).

- The Grass workspace, reorganised by what changes when. The bar: the tools in three groups (Paint: Paint, Replace,
  Erase; Shape: Density, Height, Smooth; Rules: Force, Remove, Reset), the species chip with a picker (a search, the
  favourites, the species by pack, hover cards), the eyedropper (Pick), and Replace's From.
- The panel holds only the tool's settings: a line saying what it does, its brush options, its mode (Density and
  Height: Thicker/Taller, Thinner/Shorter, Back to ×1; Smooth: Density or Height), Apply (under the brush or the whole
  region) and Only where (slope and elevation, each a switch and one range). Ground | Water and an empty layer's banner
  sit under its header; Species… and Ground rules… are behind ⋯.
- The view strip at the top of the 3D view: show grass, the year as one track by season (drag it, or a month letter
  for its 15th) marking the selected species' flowering windows, the date, In bloom (every species with flowers in
  bloom for the preview, whatever the date: `GrassSeasonPlan.all_bloom`), every ground; a map's fixed date locks it
  and links its Ground rules.
- "no water here" on the brush chip in place of the panel's hint. Presets saved by 1.4 keep their meaning.
- Opposites are one tool: hold Ctrl and the bar shows the opposite (Paint / Remove, Color / Auto color, thicker /
  thinner, taller / shorter, Path / Grow back, Force / the ground's rules). The Remove and Erase tools are gone: Paint
  with Ctrl removes, and Reset can reset the species alone.
- Remove is its own marker (the species byte's 255: nothing grows); painting over it brings the grass back at its
  painted density and height, and a removal made the old way (density 0) heals when painted.
- Force grows the chosen species or the ground's own mix; Only where gains Grounds (only on / not on the terrain
  textures you tick), so Force can leave asphalt alone.
- Color paints which of a flower's colors grows (the selected species' palette, or Auto: the field's own stripes).
  Stored in the force byte's low 7 bits; existing maps read as Auto. Flowers, the far-away blades' flower tint (the
  color rides in the blade instance's spare COLOR bits) and `sample()` honour it.
- Hovering Color in the bar opens its swatches above it (Terrain3D Extended's hover flyout): a click picks the color
  and switches to Color.
- Path wears a path (Light, Worn, Bare) and grows it back; Inspect (ⓘ on the view strip) puts what grows under the
  cursor, and why, on the brush chip.
- The paint overlay (the view strip's layers button, ▾ for the mode and its key; also the Grass menu's "Paint
  overlay"): what the maps hold, drawn on the terrain with the grass hidden. What's painted (species tints, removed
  hatched red, forced striped orange, painted colors dotted), Density or Height (blue below ×1, warm above). Drawn by
  `grass_far.gdshaderinc` (`grass_overlay_apply`), so a terrain shader that includes the far field draws it with no
  change; the button is off offer on one that does not. `GrassOverlay`, `GrassEditorPreview.overlay`.
- A growth table's slot can be `"painted_only": true`: its own grass is off, what is painted there grows at its
  density (as a ground rule with its own grass off).
- `GrassSeason.spans`; `GrassYearTrack`, `GrassViewStrip`.

## 1.4.0 (2026-09-26)

- Installed and active species: any number of packs can be installed, and none costs anything until its species are
  active. The slot table (`slots_path`) is the active set, up to 32 species bringing up to 32 flower kinds, and it no
  longer grows when a pack is installed; a project without one starts with the starter grass active (the editor
  writes it). `GrassBladesConfig.installed_packs()` and `installed_sources()`; `GrassActiveSet`, the set as a model.
- The Species dialog (the Grass panel's "Species…"): the installed packs as a tree with a search and layer filters,
  and the 32 slots. Drag a species or a whole pack in (all or nothing), a slot out; a filled slot asks before it is
  replaced; a right-click makes the fallback; a change past a budget is refused, saying what it needs and what is
  free. Every change is written at once and is one undo step; the editor's grass and its library follow at once
  (`GrassBlades.reload_species()`), a scene in a background tab when it comes back.
- The fallback can be chosen: the slot table's `"fallback"`.
- A mix naming an installed species that is not active skips it (a mix of only such names grows nothing); ground rules
  keep such names. A slot whose species no installed pack has is reported as missing.
- Species' cards name their water: floating, the depth under water, or the water they stand in.

## 1.3.0 (2026-09-26)

- Water sources: `GrassBlades.set_water(source)` (duck-typed, like the roads: outlines, surface heights, kinds) and a
  ready-made feeder, `GrassWaterGroup` (the visible planes and paths in the group `waailand_water`). The species
  measure their depth below the highest water over them, the sea's or a source's, judged at each blade's final root.
- `GrassSpecies.wet_depth_m`: an emergent species stands in water that deep (rice, reed). Land species reach an inland
  waterline; at the sea they keep their 0.3 m (the sea's shore), as before.
- The surface layer: `GrassSpecies.layer` (`GROUND`, `SURFACE`). Surface species float on water in a second grid, from
  the growth table's new `water` section (a mix per water kind; the sea's is `Zee`) or their own grass maps
  (`<maps_folder>_water`); rooted at the surface, bobbing, their decorations without a root hinge.
  `GrassBlades.sample_water(position)`, `GrassSample.surface_m`.
- The Grass workspace: a Ground / Water switch (the library, the selection, the maps and the tools follow it; with
  Terrain3D Extended 1.1 the stroke lands on the water's surface). The Ground rules dialog edits water kinds.
- Pictures of surface species float on a pool.
- Mixes are checked for the layer of their species (a floating species in a ground's mix, or a ground species in a
  water kind's, is refused with an error).

## 1.2.0 (2026-09-25)

- `GrassSpecies.picture_day`: the day of the year a species' library picture is drawn on (a species whose look is a
  season of its own: autumn colour, winter leaves). It is part of the picture's stamp, so a change marks it stale.

## 1.1.1 (2026-09-25)

- The README's far-field instructions follow Terrain3D 1.1's shader (`mat.albedo_height`); the earlier lines did not
  compile there.
- The addon's tests leave out whatever pack addons the project has installed, and the camera test turns physics
  interpolation on for itself instead of asking the project for it.

## 1.1.0 (2026-09-25)

- Pack addons are sets: an addon's `waailand_packs.tres` is a `GrassPackSet` listing one or more packs, so one addon
  can ship several (a mega pack). It replaces the single `waailand_pack.tres`. `disabled_packs` takes a whole set's
  path or one pack's.

## 1.0.0 (2026-09-25)

The first release.

- GPU grass for Terrain3D: blades placed every frame by compute, one per grid cell, HIGH and LOW meshes with a morph,
  a thinning far carpet, clumps, a grow ramp so nothing pops, optional shadows.
- Species packs: `GrassSpecies`, `GrassDecoration` (built-in flower, plume, spike and coral meshes, or your own),
  `GrassSpeciesPack`; pack addons (a folder in `addons/` with a `waailand_pack.tres`, found without being listed);
  permanent slots; a starter pack; pictures rendered with the real shaders.
- What grows where: a growth table by terrain texture, elevation bands, and per-map ground rules with their own
  dialog.
- Seasons: accents, heights and flowers in bud, bloom and seed through the year; per-species season settings.
- The sea: species by depth, the swell's surge under water.
- Wind with gusts and a combed field, weather, trampling, tyres, rotor downwash, ruts, live roads with verges.
- A far field in the terrain shader: the carpet's brightness, grain and canopy light past the blades.
- Painting through Terrain3D Extended: ten tools, a species library, limits, a region fill, undo.
- An editor preview with a date, and a Grass menu.
- The input API (`set_wind`, `set_date`, `set_weather`, `set_sun`, `set_sea`, `add_crush`, `add_push`, `add_wash`, and
  more), feeders (`GrassFeeder`, `GrassGroupStamper`), and `sample()` to read what grows at a point.
