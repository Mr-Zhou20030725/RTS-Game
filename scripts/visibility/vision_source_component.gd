class_name VisionSourceComponent
extends PointLight2D

## Reusable Human vision source backed by a soft radial 2D light.

@export_range(16.0, 2000.0, 1.0) var vision_radius := 160.0:
	set(value):
		vision_radius = maxf(value, 16.0)
		_sync_texture_scale()


func _ready() -> void:
	blend_mode = Light2D.BLEND_MODE_MIX
	add_to_group(&"human_vision_sources")
	_sync_texture_scale()
	var health := get_parent().get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health != null:
		health.died.connect(_on_owner_died)


func set_vision_radius(value: float) -> void:
	vision_radius = value


func get_vision_radius() -> float:
	return vision_radius


func is_vision_active() -> bool:
	if not enabled or not is_inside_tree():
		return false
	var owner := get_parent()
	if owner == null or not owner is CanvasItem:
		return false
	var health := owner.get_node_or_null("HealthComponent") as HealthComponent
	return health == null or not health.is_dead


func _sync_texture_scale() -> void:
	if texture == null or texture.get_width() <= 0:
		return
	texture_scale = vision_radius / (float(texture.get_width()) * 0.5)


func _on_owner_died(_source: Node) -> void:
	enabled = false
