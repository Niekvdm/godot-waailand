# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassBladesConfig
extends Resource
## The addon's one integration point: which feeder nodes run under every GrassBlades, and where the catalogs
## and the baked grain live. The project ships it at DEFAULT_PATH; the project setting SETTING overrides the
## path (read only: nothing here writes project.godot). Without one the grass runs with no feeders, on the packs
## it finds (or the starter pack), and says so once.

## Where the project's config lives, unless the project setting SETTING names another path.
const DEFAULT_PATH := "res://waailand_config.tres"
## The project setting that overrides DEFAULT_PATH.
const SETTING := "waailand/config_path"

## Feeder nodes added under every GrassBlades in the game (GrassBlades.inputs), one per script.
@export var runtime_inputs: Array[Script] = []
## Feeder nodes that also run in the editor (their scripts need @tool). In the game they run too.
@export var editor_inputs: Array[Script] = []
## The packs this project lists first (pack addons are found without it; see resolved_packs). Species ids must be
## unique across every pack in use.
@export var packs: Array[GrassSpeciesPack] = []
## The project's slot table: species id -> the slot the grass maps and GPU tables use. The editor writes it.
@export_file("*.json") var slots_path := "res://grass_species_slots.json"
## Overrides the packs' fallback species (what grows where a mix cannot); empty: the first pack's that sets one.
@export var fallback_species: StringName = &""
## Overrides the packs' default mix ({species id: weight}); empty: the first pack's that sets one.
@export var default_mix: Dictionary = {}
## The terrain growth table (GrassTerrainGrowth): what grows on which terrain texture, by species id.
@export_file("*.json") var growth_path := ""
## Where GrassFarGrain loads and saves the baked carpet grain.
@export_dir var far_grain_dir := ""
## Where each map's ground rules live: <grounds_dir>/<map scene name>.json.
## "" (or no file for a map): the shared growth table.
@export_dir var grounds_dir := ""
## The grass maps' folder under the terrain's data directory: one map a
## region, named like the region's file.
@export var maps_folder := "grass"
## Packs not to grow, by res:// path: one the config lists, a pack addon, or the starter pack.
@export var disabled_packs := PackedStringArray()

## The file a pack addon holds at its folder's root: res://addons/<name>/waailand_pack.tres.
const PACK_FILE := "waailand_pack.tres"

static var _current: GrassBladesConfig = null


## The project's config, loaded once. Missing, or not a GrassBladesConfig: a stand-in (one error) with no feeders,
## on the packs it finds, that saves no slot table (its species get their slots for this run only): a config that
## failed to load, as on the first scan after the addon moved, must not grow the project's table.
static func current() -> GrassBladesConfig:
	if _current == null:
		var p := String(ProjectSettings.get_setting(SETTING, DEFAULT_PATH))
		var c: GrassBladesConfig = null
		if ResourceLoader.exists(p):
			c = load(p) as GrassBladesConfig
		if c == null:
			push_error("GrassBladesConfig: no config at %s; the grass runs with no feeders, on the packs it finds" % p)
			c = GrassBladesConfig.new()
			c.slots_path = ""
		_current = c
	return _current


## For tools and tests: use `c` from now on; null forgets it (the next current() loads again).
static func use(c: GrassBladesConfig) -> void:
	_current = c


## The packs in use, in order: the config's `packs`, then every pack addon under `addons_dir` (sorted by path; one
## the config already lists counts once), less `disabled_packs`. When none is left: the built-in starter pack, so a
## project grows grass before it has species of its own.
func resolved_packs(addons_dir := "res://addons") -> Array[GrassSpeciesPack]:
	var out: Array[GrassSpeciesPack] = []
	var seen := {}
	for p in packs:
		if p != null and not seen.has(_key(p)) and not disabled_packs.has(p.resource_path):
			seen[_key(p)] = true
			out.append(p)
	for path in discovered_pack_paths(addons_dir):
		if seen.has(path) or disabled_packs.has(path):
			continue
		var pk := load(path) as GrassSpeciesPack
		if pk != null:
			seen[path] = true
			out.append(pk)
	var starter := starter_pack_path()
	if out.is_empty() and not disabled_packs.has(starter) and ResourceLoader.exists(starter):
		var st := load(starter) as GrassSpeciesPack
		if st != null:
			out.append(st)
	return out


## Every <addons_dir>/<folder>/waailand_pack.tres, sorted (ResourceLoader.list_directory, so an exported game finds
## them too).
static func discovered_pack_paths(addons_dir := "res://addons") -> PackedStringArray:
	var out := PackedStringArray()
	for d in ResourceLoader.list_directory(addons_dir):
		if d.ends_with("/"):
			var p := addons_dir.path_join(d.trim_suffix("/")).path_join(PACK_FILE)
			if ResourceLoader.exists(p):
				out.append(p)
	out.sort()
	return out


## The built-in starter pack, beside this script (whatever the addon's folder is called).
func starter_pack_path() -> String:
	return (get_script() as Script).resource_path.get_base_dir().path_join("packs/starter/starter.tres")


## A pack's identity for counting it once: its file, or the object for a pack that is not a file.
static func _key(p: GrassSpeciesPack) -> Variant:
	return p.resource_path if p.resource_path != "" else p
