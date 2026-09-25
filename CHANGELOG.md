# Changelog

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
