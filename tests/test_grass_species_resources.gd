# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassSpeciesResources
extends GrassSuite
## The species resources: a GrassSpecies gives the row GrassTypes parses, a
## GrassDecoration the kind DecoKinds parses, the built-in mesh builders build what their recipe builds, and a custom
## builder script is called for its mesh.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassSpeciesResources.new(), "grass_species_resources")


## A test builder: counts its calls, builds a spike.
class CountingBuilder extends GrassDecorationMeshBuilder:
	var calls := 0

	func build() -> Array:
		calls += 1
		return DecoKinds._build_mesh({"builder": "spike", "args": [0.3, 0.15, 0.01, 3]})


static func _types_of(sp: GrassSpecies) -> GrassTypes:
	var t := GrassTypes.new("")
	t._load_doc({"types": [sp.to_row_json(0)]})
	return t


static func _same_meshes(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i in a.size():
		var x: Array = (a[i] as ArrayMesh).surface_get_arrays(0)
		var y: Array = (b[i] as ArrayMesh).surface_get_arrays(0)
		if x[Mesh.ARRAY_VERTEX] != y[Mesh.ARRAY_VERTEX] or x[Mesh.ARRAY_INDEX] != y[Mesh.ARRAY_INDEX] \
				or x[Mesh.ARRAY_TEX_UV] != y[Mesh.ARRAY_TEX_UV]:
			return false
	return true


func test_a_species_gives_its_row() -> void:
	var sp := GrassSpecies.new()
	sp.id = &"meadow"
	var t := _types_of(sp)
	assert_eq(t.errors, PackedStringArray(), "a new species parses clean")
	var r := t.row(0)
	assert_true(r["name"] == "meadow" and r["height"] == sp.height and r["floor"] == sp.floor_fill,
		"its blade fields (floor from floor_fill)")
	assert_eq(r["base_a"], sp.base_a.linear_to_srgb(), "its colours: linear in the resource, sRGB in the row")
	assert_eq(r["depth"], GrassTypes.LAND_DEPTH, "no depth: a land species")
	sp.depth_m = Vector2(2.0, 12.0)
	sp.height_season = PackedVector2Array([Vector2(0, 0.5), Vector2(180, 1.0)])
	sp.density = 0.0
	sp.host_only = true
	r = _types_of(sp).row(0)
	assert_true(r["depth"] == Vector3(2.0, 12.0, 1.0) and r["height_season"] == [Vector2(0, 0.5), Vector2(180, 1.0)]
		and r["host_only"], "a sea host with a season")


## A species can choose the day its library picture is drawn on (picture_day); -1 leaves the day to its first
## decoration's mid-bloom, else the preview's default date.
func test_the_picture_day() -> void:
	var sp := GrassSpecies.new()
	sp.id = &"kochia"
	var t := _types_of(sp)
	var growth := GrassTerrainGrowth.new("")
	assert_true(not t.row(0).has("picture_day"), "no picture_day: none in the row")
	assert_eq(GrassSpeciesPreview.recipe(t, DecoKinds.new("", t), growth, 0)["day"], GrassEditorPreview.DEFAULT_DAY,
		"the preview's default date")
	sp.picture_day = 288.0
	assert_eq(sp.to_row_json(0).get("picture_day"), 288.0, "in the species' row")
	t = _types_of(sp)
	assert_eq(t.row(0).get("picture_day"), 288.0, "GrassTypes keeps it")
	assert_eq(GrassSpeciesPreview.recipe(t, DecoKinds.new("", t), growth, 0)["day"], 288.0, "the picture is drawn on it")


func test_a_decoration_gives_its_kind() -> void:
	var sp := GrassSpecies.new()
	sp.id = &"meadow"
	var types := _types_of(sp)
	var d := GrassDecoration.new()
	d.name = &"meadow_plume"
	var pb := PlumeMeshBuilder.new()
	d.mesh_builder = pb
	var k := DecoKinds.new("")
	k._load_doc({"kinds": [d.to_kind_json("meadow", 116)]}, types)
	assert_eq(k.errors, PackedStringArray(), "a new decoration parses clean")
	assert_true(k.kinds[0]["host"] == 0 and k.kinds[0]["salt"] == 116.0, "its host is the species' slot; its salt kept")
	var row := k.params_bytes(types, [Vector2.ZERO]).to_float32_array()
	assert_eq(row[18], 116.0, "the salt reaches the params (vec4 4, z)")
	assert_true(_same_meshes(k.mesh(0), DecoKinds._build_mesh(pb.recipe())), "its mesh is its recipe's")


func test_every_builder_matches_its_recipe() -> void:
	var cases := {"plume": PlumeMeshBuilder.new(), "freesia": FreesiaMeshBuilder.new(), "isogiku": IsogikuMeshBuilder.new(),
		"spike": SpikeMeshBuilder.new(), "lycoris": LycorisMeshBuilder.new(), "lily": LilyMeshBuilder.new(),
		"coral": CoralMeshBuilder.new()}
	var bad := []
	for nm in cases:
		var b: GrassDecorationMeshBuilder = cases[nm]
		if b.recipe().get("builder", "") != nm or not _same_meshes(b.build(), DecoKinds._build_mesh(b.recipe())):
			bad.append(nm)
	assert_eq(bad, [], "each built-in builder names its recipe and builds it")


func test_a_custom_builder_is_called() -> void:
	var sp := GrassSpecies.new()
	sp.id = &"meadow"
	var types := _types_of(sp)
	var d := GrassDecoration.new()
	d.name = &"odd"
	var cb := CountingBuilder.new()
	d.mesh_builder = cb
	var k := DecoKinds.new("")
	k._load_doc({"kinds": [d.to_kind_json("meadow", -1)]}, types)
	var m := k.mesh(0)
	k.mesh(0)
	assert_true(m.size() == 2 and cb.calls == 1, "its build() gives the mesh, once (cached)")
	var none := GrassDecoration.new()
	none.name = &"bare"
	var k2 := DecoKinds.new("")
	k2._load_doc({"kinds": [none.to_kind_json("meadow", -1)]}, types)
	assert_true(k2.kinds.is_empty() and k2.errors.size() == 1, "a decoration without a mesh builder is an error (%s)" % [k2.errors])
