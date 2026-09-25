# Asset Library entry: Waailand

Paste these into the Godot Asset Library's submission form (https://godotengine.org/asset-library/asset/submit).

| Field | Value |
|---|---|
| Asset name | Waailand |
| Category | 3D Tools |
| Godot version | 4.8 |
| Version | 1.0.0 |
| License | MIT |
| Repository host | Custom |
| Repository URL | https://github.com/Niekvdm/godot-waailand |
| Issues URL | https://github.com/Niekvdm/godot-waailand/issues |
| Download URL | https://github.com/Niekvdm/godot-waailand/releases/download/v1.0.0/godot-waailand-1.0.0.zip |
| Icon URL | https://raw.githubusercontent.com/Niekvdm/godot-waailand/v1.0.0/.release/icon.png |

## Description

GPU grass, flowers and seasons for Terrain3D. Every frame a compute shader places the blades around the camera from
the terrain and a painted grass map, so nothing per blade runs on the CPU. Species come in packs (a starter pack is
included), grow by the terrain texture under them, and change with the seasons; flowers, plumes and corals grow on
their host species. The grass reacts to wind, weather, trampling, tyres, rotor downwash and the sea's swell, and a far
field in the terrain shader carries the carpet to the horizon. Games can read what grows at any point (for footsteps,
tyre effects and the like). Paint it with Terrain3D Extended.

Requires Terrain3D, and the Forward+ renderer (compute shaders).

## Before submitting

- The URLs work once the repository is public and the v1.0.0 release carries the zip (`.release/make_zip.sh`).
- The addon is tested on Godot 4.8.dev6 and Terrain3D 1.1.0-dev (upstream main, 188873b). The Asset Library lists
  assets against released Godot versions, so the listing waits for Godot 4.8 and Terrain3D 1.1, or for a test on the
  released versions a listing would name.
