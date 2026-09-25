# Changelog

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
