extends SceneTree
const Screen = preload("res://src/presentation/result_screen.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Control.new()
	host.size = Vector2(1280,720)
	root.add_child(host)
	var screen := Screen.new()
	host.add_child(screen)
	var data := {"outcome":"defeat","rooms_completed":1,"room_count":3,"defeated":0,
		"elapsed_seconds":12.0,"casts":24,"contract_id":"threshold_colossus","mode":"Manual",
		"room_results":[{"outcome":"victory"},{"outcome":"defeat"}],
		"primary_bottleneck":{"title":"Growth converged","action":"Find growth-chance affixes in targeted side contracts"}}
	var before := data.duplicate(true)
	screen.present(data)
	await _settle()
	var report_button := screen.find_child("ReportDetailButton",true,false) as Button
	_expect(report_button != null and report_button.visible,"report detail action missing")
	if report_button != null:
		report_button.pressed.emit()
		await _settle()
	_expect(data == before,"presentation mutated supplied result")
	_expect(screen._reported_route_steps().size() == 2,"unreported third room was fabricated")
	_expect(screen._reported_route_steps()[0].state == "completed" and screen._reported_route_steps()[1].state == "failed","room states were inferred incorrectly")
	var bar := screen.find_child("RoomCompletionBar",true,false) as ProgressBar
	_expect(bar.visible and bar.value == 1 and bar.max_value == 3,"bar must use authoritative room numerator/denominator")
	_expect(_text(screen,"observed").contains("Kills 0"),"reported zero was hidden")
	_expect(_text(screen,"bottleneck") == "Growth converged","real bottleneck not surfaced")
	_expect(_text(screen,"next").contains("targeted side contracts"),"supplied action not surfaced")
	for id in ["observed","unverified","bottleneck","next"]:
		var card := screen.find_child("EvidenceCard_"+id,true,false) as Control
		_expect(card != null and card.is_visible_in_tree(),id+" card not reachable from report detail")
		var label := screen.find_child("EvidenceBody_"+id,true,false) as Label
		_expect(label != null and label.is_visible_in_tree() and label.get_theme_font_size("font_size") >= 18,id+" text below floor or hidden")
	_expect(_text(screen,"unverified").contains("build growth conclusions") and _text(screen,"unverified").contains("Training"),"growth follow-up left the player-facing result card")
	screen.present({"outcome":"victory","room_count":3})
	await _settle()
	_expect(not bar.visible,"missing completed rooms was shown as zero")
	_expect(screen._reported_route_steps().is_empty(),"missing route invented nodes")
	_expect(_text(screen,"observed").contains("No"),"missing combat fields invented readings")
	_expect(not _text(screen,"bottleneck").contains("Growth converged"),"previous failure leaked to victory")
	_expect(not _text(screen,"next").contains("targeted side contracts"),"previous action leaked to new result")
	for pair in [[4,3],[-1,3],[0,0],[1.5,3]]:
		screen.present({"outcome":"victory","rooms_completed":pair[0],"room_count":pair[1]})
		_expect(not bar.visible,"invalid progress was silently clamped")
	screen.present({"outcome":"victory","rooms_completed":0,"room_count":3,"room_results":[{},"bad"]})
	_expect(bar.visible and bar.value == 0,"valid zero progress hidden")
	_expect(screen._reported_route_steps()[0].state == "unknown" and screen._reported_route_steps()[1].state == "unknown","malformed records inferred as successes")
	host.free()
	print("RESULT_EVIDENCE ","pass" if errors.is_empty() else "fail", " ",errors)
	quit(0 if errors.is_empty() else 1)

func _text(screen: Control,id: String) -> String:
	return (screen.find_child("EvidenceBody_"+id,true,false) as Label).text

func _expect(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func _visible(node: Control, screen: Control) -> bool:
	if node == null or not node.is_visible_in_tree(): return false
	var rect := node.get_global_rect()
	if not screen.get_global_rect().encloses(rect): return false
	var parent := node.get_parent()
	while parent is Control:
		if parent.clip_contents and not parent.get_global_rect().encloses(rect): return false
		parent = parent.get_parent()
	return true

func _settle() -> void:
	for frame in range(12): await process_frame
