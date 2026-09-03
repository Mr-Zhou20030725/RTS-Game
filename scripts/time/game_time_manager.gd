class_name GameTimeManager
extends Node

signal time_changed(elapsed_seconds: float)
signal milestone_reached(milestone: Milestone, elapsed_seconds: float)
signal pause_changed(is_paused: bool)
signal debug_time_scale_changed(scale: float)

enum Milestone {
	MINUTE_5,
	MINUTE_15,
	MINUTE_20,
	MINUTE_25,
	MINUTE_30,
}

@export var config: GameTimeConfig

var elapsed_seconds: float = 0.0
var debug_time_scale: float = 1.0
var _time_paused := false
var _triggered_milestones: Dictionary = {}
var _announcement_queue: Array[int] = []
var _current_announcement := -1
@onready var _time_display: Label = get_node_or_null(
	"TimeDisplayLayer/TimePanel/TimeLabel"
)
@onready var _announcement_panel: PanelContainer = get_node_or_null(
	"TimeDisplayLayer/StageAnnouncementPanel"
)
@onready var _announcement_label: Label = get_node_or_null(
	"TimeDisplayLayer/StageAnnouncementPanel/AnnouncementLabel"
)
@onready var _announcement_timer: Timer = get_node_or_null(
	"AnnouncementTimer"
)


func _ready() -> void:
	if config == null:
		config = GameTimeConfig.new()
	time_changed.emit(elapsed_seconds)
	debug_time_scale_changed.emit(debug_time_scale)
	_update_time_display()
	if _announcement_timer != null:
		_announcement_timer.timeout.connect(dismiss_current_announcement)


func _process(delta: float) -> void:
	if _time_paused:
		return
	advance_simulation(delta * debug_time_scale)


func _unhandled_input(event: InputEvent) -> void:
	if (
		not OS.is_debug_build()
		or not event is InputEventKey
		or not event.is_pressed()
		or event.is_echo()
	):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_F6:
		cycle_debug_time_scale()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F7:
		jump_to_next_milestone()
		get_viewport().set_input_as_handled()


func advance_simulation(seconds: float) -> void:
	if _time_paused or seconds <= 0.0:
		return
	elapsed_seconds += seconds
	_emit_crossed_milestones()
	time_changed.emit(elapsed_seconds)
	_update_time_display()


func set_time_paused(value: bool) -> void:
	if _time_paused == value:
		return
	_time_paused = value
	pause_changed.emit(_time_paused)
	_update_time_display()


func pause_time() -> void:
	set_time_paused(true)


func resume_time() -> void:
	set_time_paused(false)


func is_time_paused() -> bool:
	return _time_paused


func set_debug_time_scale(value: float) -> void:
	var next_scale := maxf(value, 0.01)
	if is_equal_approx(debug_time_scale, next_scale):
		return
	debug_time_scale = next_scale
	debug_time_scale_changed.emit(debug_time_scale)
	_update_time_display()


func cycle_debug_time_scale() -> float:
	var scales := config.debug_time_scales if config != null else PackedFloat32Array([1.0])
	if scales.is_empty():
		set_debug_time_scale(1.0)
		return debug_time_scale
	var next_index := 0
	for index in range(scales.size()):
		if is_equal_approx(scales[index], debug_time_scale):
			next_index = (index + 1) % scales.size()
			break
	set_debug_time_scale(scales[next_index])
	return debug_time_scale


func jump_to_time(target_seconds: float) -> void:
	var safe_target := maxf(target_seconds, 0.0)
	if safe_target <= elapsed_seconds:
		return
	elapsed_seconds = safe_target
	_emit_crossed_milestones()
	time_changed.emit(elapsed_seconds)
	_update_time_display()


func jump_to_next_milestone() -> bool:
	var next_milestone := get_next_milestone()
	if next_milestone < 0:
		return false
	jump_to_time(_get_milestone_time(next_milestone))
	return true


func get_next_milestone() -> int:
	for milestone in range(Milestone.size()):
		if not _triggered_milestones.has(milestone):
			return milestone
	return -1


func has_triggered(milestone: Milestone) -> bool:
	return _triggered_milestones.has(milestone)


func get_triggered_milestones() -> Array[int]:
	var result: Array[int] = []
	for milestone in range(Milestone.size()):
		if _triggered_milestones.has(milestone):
			result.append(milestone)
	return result


func get_milestone_label(milestone: Milestone) -> String:
	match milestone:
		Milestone.MINUTE_5:
			return "5 分钟阶段"
		Milestone.MINUTE_15:
			return "15 分钟阶段"
		Milestone.MINUTE_20:
			return "20 分钟阶段"
		Milestone.MINUTE_25:
			return "25 分钟阶段"
		Milestone.MINUTE_30:
			return "30 分钟阶段"
	return "未知阶段"


func get_current_announcement_milestone() -> int:
	return _current_announcement


func get_pending_announcement_count() -> int:
	return _announcement_queue.size() + (1 if _current_announcement >= 0 else 0)


func dismiss_current_announcement() -> void:
	if _announcement_timer != null:
		_announcement_timer.stop()
	_current_announcement = -1
	if _announcement_panel != null:
		_announcement_panel.hide()
	_show_next_announcement()


func _emit_crossed_milestones() -> void:
	for milestone in range(Milestone.size()):
		if _triggered_milestones.has(milestone):
			continue
		if elapsed_seconds >= _get_milestone_time(milestone):
			_triggered_milestones[milestone] = true
			_queue_milestone_announcement(milestone)
			milestone_reached.emit(milestone, elapsed_seconds)


func _get_milestone_time(milestone: int) -> float:
	var times := config.get_milestone_times()
	if milestone < 0 or milestone >= times.size():
		return INF
	return times[milestone]


func _queue_milestone_announcement(milestone: int) -> void:
	_announcement_queue.append(milestone)
	print(
		"[阶段广播] 对局已到达 %s。"
		% get_milestone_label(milestone as Milestone)
	)
	if _current_announcement < 0:
		_show_next_announcement()


func _show_next_announcement() -> void:
	if _announcement_queue.is_empty():
		return
	_current_announcement = _announcement_queue.pop_front()
	if _announcement_label != null:
		_announcement_label.text = "阶段广播\n对局已到达 %s" % get_milestone_label(
			_current_announcement as Milestone
		)
	if _announcement_panel != null:
		_announcement_panel.show()
	if _announcement_timer != null:
		_announcement_timer.start()


func _update_time_display() -> void:
	if _time_display == null:
		return
	var total_seconds := int(floor(elapsed_seconds))
	var hours := int(total_seconds / 3600)
	var minutes := int((total_seconds % 3600) / 60)
	var seconds := total_seconds % 60
	var time_text := "%02d:%02d" % [minutes, seconds]
	if hours > 0:
		time_text = "%02d:%02d:%02d" % [hours, minutes, seconds]
	_time_display.text = "时间 %s" % time_text
	if OS.is_debug_build():
		var state_text := "已暂停" if _time_paused else "倍率"
		_time_display.text += "\n%s ×%s" % [
			state_text,
			str(debug_time_scale),
		]
	elif _time_paused:
		_time_display.text += "\n已暂停"
