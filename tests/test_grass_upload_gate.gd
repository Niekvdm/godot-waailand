# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassUploadGate
extends GrassSuite
## A table the CPU re-sends only on change must never lose the
## change: a frame whose render-thread half returns before the upload (no device yet, the ground not
## bound) sends it again next frame, and an upload that was in flight when the table changed again does
## not mark the newer change done. The first cut cleared a flag on the main thread before the render
## thread ran, and a dropped upload stayed dropped.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassUploadGate.new(), "grass_upload_gate")


func test_a_new_gate_wants_the_first_upload() -> void:
	var g := GrassUploadGate.new()
	assert_true(g.pending() != 0, "nothing is on the GPU yet (%d)" % g.pending())


func test_a_confirmed_upload_stops_the_resend() -> void:
	var g := GrassUploadGate.new()
	g.uploaded(g.pending())
	assert_eq(g.pending(), 0, "the GPU holds the latest: no upload")
	g.mark()
	assert_true(g.pending() != 0, "a change wants an upload")
	g.uploaded(g.pending())
	assert_eq(g.pending(), 0, "and stops once it has one")


func test_a_dropped_upload_is_sent_again() -> void:
	var g := GrassUploadGate.new()
	g.uploaded(g.pending())
	g.mark()
	var sent := g.pending()
	# the render thread returns before its upload: no uploaded(sent)
	assert_eq(g.pending(), sent, "the next frame sends the same change again")


func test_an_older_upload_does_not_retire_a_newer_change() -> void:
	var g := GrassUploadGate.new()
	g.uploaded(g.pending())
	g.mark()
	var in_flight := g.pending()
	g.mark()                                  # the table changes while that upload is on its way
	g.uploaded(in_flight)
	assert_true(g.pending() != 0, "the newer change still wants its upload (%d)" % g.pending())
	g.uploaded(g.pending())
	assert_eq(g.pending(), 0, "and is done once it lands")


func test_latest_names_the_current_generation() -> void:
	var g := GrassUploadGate.new()
	var a := g.latest()
	g.mark()
	assert_true(g.latest() != a, "a change is a new generation")
	assert_eq(g.latest(), g.pending(), "pending sends the latest")
