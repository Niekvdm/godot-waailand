# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassInputs
extends GrassSuite
## GrassBlades adds the project's feeders (GrassBladesConfig): one per
## script, none twice (a scene may already hold one of its own), never with an
## owner, so a saved scene never carries them.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassInputs.new(), "grass_inputs")


static func _script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\n"
	s.reload()
	return s


func test_feeders_attach_once_without_an_owner() -> void:
	var b := GrassBlades.new()
	var a := _script()
	var c := _script()
	var pre: Node = a.new()
	pre.name = "Pre"
	b.add_child(pre)
	var list: Array[Script] = [a, c, null, c]
	b._attach_inputs(list)
	assert_eq(b.get_child_count(), 2, "one feeder per script: the scene's own counts, a repeat and null add nothing")
	var added := b.get_child(1)
	assert_true(added.get_script() == c, "the missing feeder was added")
	assert_true(added.owner == null, "without an owner, so a saved scene never carries it")
	b.free()


class _Counter extends GrassFeeder:
	var fed := 0

	func _feed(_dt: float) -> void:
		fed += 1


## A feeder finds its parent GrassBlades, runs just before it, and is fed
## every frame; under anything else it feeds nothing. (_find_blades is what enter-tree calls: a node outside a scene
## tree cannot be sent that notification.)
func test_a_feeder_finds_its_blades() -> void:
	var b := GrassBlades.new()
	var f := _Counter.new()
	b.add_child(f)
	f._find_blades()
	assert_true(f.blades == b and f.process_priority == GrassBlades.FEED_PRIORITY, "its parent, and it runs first")
	f._process(0.016)
	assert_eq(f.fed, 1, "fed once a frame")
	var stray := _Counter.new()
	var n := Node.new()
	n.add_child(stray)
	stray._find_blades()
	stray._process(0.016)
	assert_eq([stray.blades, stray.fed], [null, 0], "under anything else: no blades, never fed")
	var kept := _Counter.new()
	kept.blades = b
	n.add_child(kept)
	kept._find_blades()
	assert_true(kept.blades == b, "blades set by hand (a test) are kept")
	b.free()
	n.free()
