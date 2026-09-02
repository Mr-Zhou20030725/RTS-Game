class_name WorldCamera
extends Camera2D

## Moves a fixed-size viewport across the 4000 × 4000 battlefield.

@export var world_bounds := Rect2(0.0, 0.0, 4000.0, 4000.0)
@export_range(100.0, 3000.0, 10.0) var pan_speed := 900.0
@export_range(0.2, 1.0, 0.05) var minimum_zoom := 0.4
@export_range(1.0, 3.0, 0.05) var maximum_zoom := 1.5
@export_range(0.05, 0.5, 0.05) var zoom_step := 0.1

var _dragging := false


func _ready() -> void:
	position = world_bounds.get_center()
	zoom = Vector2(0.75, 0.75)
	_clamp_to_world()


func _process(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	if not direction.is_zero_approx():
		position += direction.normalized() * pan_speed * delta / zoom.x
		_clamp_to_world()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse_event.pressed
			get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x + zoom_step)
			get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x - zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp_to_world()
		get_viewport().set_input_as_handled()


func _set_zoom(value: float) -> void:
	var clamped := clampf(value, minimum_zoom, maximum_zoom)
	zoom = Vector2(clamped, clamped)
	_clamp_to_world()


func _clamp_to_world() -> void:
	var half_view := get_viewport_rect().size * 0.5 / zoom
	var minimum := world_bounds.position + half_view
	var maximum := world_bounds.end - half_view
	position.x = (
		world_bounds.get_center().x
		if minimum.x > maximum.x
		else clampf(position.x, minimum.x, maximum.x)
	)
	position.y = (
		world_bounds.get_center().y
		if minimum.y > maximum.y
		else clampf(position.y, minimum.y, maximum.y)
	)
