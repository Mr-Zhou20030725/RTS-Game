extends SceneTree

const MANAGER_SCENE := preload(
	"res://scenes/time/game_time_manager.tscn"
)
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var manager := MANAGER_SCENE.instantiate() as GameTimeManager
	manager.set_process(false)
	root.add_child(manager)
	await process_frame
	manager.set_process(false)
	var reached: Array[int] = []
	manager.milestone_reached.connect(
		func(milestone: GameTimeManager.Milestone, _elapsed: float) -> void:
			reached.append(int(milestone))
	)

	if manager.config.get_milestone_times() != PackedFloat32Array([
		300.0, 900.0, 1200.0, 1500.0, 1800.0
	]):
		_fail("Milestone configuration does not match 5/15/20/25/30 minutes.")
		return

	manager.advance_simulation(299.0)
	if not reached.is_empty():
		_fail("The five-minute milestone fired early.")
		return
	manager.advance_simulation(1.0)
	manager.advance_simulation(120.0)
	var announcement_label := manager.get_node(
		"TimeDisplayLayer/StageAnnouncementPanel/AnnouncementLabel"
	) as Label
	var announcement_panel := manager.get_node(
		"TimeDisplayLayer/StageAnnouncementPanel"
	) as PanelContainer
	if (
		reached != [GameTimeManager.Milestone.MINUTE_5]
		or manager.get_current_announcement_milestone()
		!= GameTimeManager.Milestone.MINUTE_5
		or not announcement_panel.visible
		or not "5 分钟阶段" in announcement_label.text
	):
		_fail(
			"Five-minute broadcast mismatch: reached=%s current=%d visible=%s text=%s"
			% [
				str(reached),
				manager.get_current_announcement_milestone(),
				str(announcement_panel.visible),
				announcement_label.text,
			]
		)
		return

	manager.pause_time()
	var paused_elapsed := manager.elapsed_seconds
	manager.advance_simulation(1200.0)
	if (
		not is_equal_approx(manager.elapsed_seconds, paused_elapsed)
		or reached.size() != 1
	):
		_fail("Paused game time continued advancing or emitted a milestone.")
		return
	manager.resume_time()
	manager.jump_to_time(1800.0)
	var expected: Array[int] = [
		GameTimeManager.Milestone.MINUTE_5,
		GameTimeManager.Milestone.MINUTE_15,
		GameTimeManager.Milestone.MINUTE_20,
		GameTimeManager.Milestone.MINUTE_25,
		GameTimeManager.Milestone.MINUTE_30,
	]
	if reached != expected:
		_fail("A debug jump did not emit crossed milestones in chronological order.")
		return
	if manager.get_pending_announcement_count() != 5:
		_fail("Crossed milestones were not all queued for visible broadcast.")
		return
	manager.dismiss_current_announcement()
	if (
		manager.get_current_announcement_milestone()
		!= GameTimeManager.Milestone.MINUTE_15
		or not "15 分钟阶段" in announcement_label.text
	):
		_fail("Queued milestone broadcasts are not shown in chronological order.")
		return
	manager.jump_to_time(2000.0)
	manager.jump_to_time(300.0)
	if reached != expected or manager.get_next_milestone() != -1:
		_fail("A milestone was repeated after later or backward jump requests.")
		return

	var debug_manager := MANAGER_SCENE.instantiate() as GameTimeManager
	debug_manager.set_process(false)
	root.add_child(debug_manager)
	await process_frame
	debug_manager.set_process(false)
	debug_manager.elapsed_seconds = 0.0
	if (
		not is_equal_approx(debug_manager.cycle_debug_time_scale(), 10.0)
		or not is_equal_approx(debug_manager.cycle_debug_time_scale(), 60.0)
		or not is_equal_approx(debug_manager.cycle_debug_time_scale(), 1.0)
	):
		_fail("Debug time-scale cycling does not follow 1x/10x/60x.")
		return
	debug_manager.set_debug_time_scale(60.0)
	debug_manager._process(1.0)
	if not is_equal_approx(debug_manager.elapsed_seconds, 60.0):
		_fail("The debug multiplier was not applied to elapsed game time.")
		return
	if (
		not debug_manager.jump_to_next_milestone()
		or not debug_manager.has_triggered(GameTimeManager.Milestone.MINUTE_5)
		or debug_manager.get_next_milestone()
		!= GameTimeManager.Milestone.MINUTE_15
	):
		_fail("Jump-to-next-milestone did not stop at the expected stage.")
		return

	var battle := BATTLE_SCENE.instantiate()
	var integrated_manager := battle.get_node_or_null(
		"GameTimeManager"
	) as GameTimeManager
	if (
		integrated_manager == null
		or integrated_manager.get_node_or_null(
			"TimeDisplayLayer/TimePanel/TimeLabel"
		) == null
		or integrated_manager.get_node_or_null(
			"TimeDisplayLayer/StageAnnouncementPanel"
		) == null
	):
		battle.free()
		_fail("Battle is missing the T27 manager or its visible time display.")
		return
	battle.free()
	print(
		"T27 validation passed: battle time tracks 5/15/20/25/30-minute "
		+ "milestones exactly once, survives pause/resume, and supports "
		+ "1x/10x/60x speed plus deterministic milestone jumps."
	)
	quit()


func _fail(message: String) -> void:
	push_error("T27 validation failed: %s" % message)
	quit(1)
