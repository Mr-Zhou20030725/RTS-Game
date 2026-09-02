class_name MonsterUnit
extends RTSUnit

## One shared runtime implementation configured by MonsterProductionData.

signal stealth_changed(is_stealthed: bool)
signal aura_buff_changed(is_buffed: bool)

@export var monster_data: MonsterProductionData

@onready var body: Polygon2D = %Body
@onready var accent: Line2D = %Accent
@onready var unit_label: Label = %UnitLabel
@onready var aura_ring: Line2D = %AuraRing
@onready var buff_indicator: Line2D = %BuffIndicator
@onready var stealth_indicator: Line2D = %StealthIndicator
@onready var legion_badge: Label = %LegionBadge

var _base_move_speed := 0.0
var _base_damage := 0.0
var _stealth_remaining := 0.0
var _aura_update_elapsed := 0.0
var _aura_targets: Dictionary[int, WeakRef] = {}
var _aura_buffs: Dictionary[int, Vector2] = {}
var _legion_slot := 0


func _ready() -> void:
	super._ready()
	_apply_monster_data()
	if health_component != null:
		health_component.died.connect(_on_monster_died)
	if melee_component != null:
		melee_component.attack_performed.connect(_on_attack_performed)
	if ranged_component != null:
		ranged_component.projectile_fired.connect(_on_projectile_fired)


func _process(delta: float) -> void:
	_update_stealth(delta)
	_update_support_aura(delta)


func _exit_tree() -> void:
	_clear_aura_targets()


func configure_monster(data: MonsterProductionData) -> void:
	monster_data = data
	if is_node_ready():
		_apply_monster_data()


func get_monster_data() -> MonsterProductionData:
	return monster_data


func set_legion_slot(slot: int) -> void:
	_legion_slot = maxi(slot, 0)
	if is_node_ready():
		legion_badge.text = "L%d" % _legion_slot if _legion_slot > 0 else ""
		legion_badge.visible = _legion_slot > 0


func get_legion_slot() -> int:
	return _legion_slot


func is_hidden_from_human() -> bool:
	return _stealth_remaining > 0.0


func get_stealth_remaining() -> float:
	return _stealth_remaining


func is_aura_buffed() -> bool:
	return not _aura_buffs.is_empty()


func get_current_damage_multiplier() -> float:
	var multiplier := 1.0
	for buff in _aura_buffs.values():
		multiplier = maxf(multiplier, (buff as Vector2).x)
	return multiplier


func get_current_speed_multiplier() -> float:
	var multiplier := 1.0
	for buff in _aura_buffs.values():
		multiplier = maxf(multiplier, (buff as Vector2).y)
	return multiplier


func set_aura_buff(
	source_id: int, damage_multiplier: float, speed_multiplier: float
) -> void:
	if source_id <= 0:
		return
	var was_buffed := is_aura_buffed()
	_aura_buffs[source_id] = Vector2(
		maxf(damage_multiplier, 1.0), maxf(speed_multiplier, 1.0)
	)
	_apply_aura_multipliers()
	if was_buffed != is_aura_buffed():
		aura_buff_changed.emit(is_aura_buffed())


func remove_aura_buff(source_id: int) -> void:
	if not _aura_buffs.has(source_id):
		return
	var was_buffed := is_aura_buffed()
	_aura_buffs.erase(source_id)
	_apply_aura_multipliers()
	if was_buffed != is_aura_buffed():
		aura_buff_changed.emit(is_aura_buffed())


func _apply_monster_data() -> void:
	if monster_data == null:
		return
	_base_move_speed = monster_data.move_speed
	_base_damage = monster_data.damage
	move_speed = _base_move_speed
	selection_radius = monster_data.collision_radius + 8.0
	separation_distance = monster_data.collision_radius * 2.5
	health_component.set_max_health(monster_data.max_health, false)
	health_component.heal(monster_data.max_health)
	body.color = monster_data.body_color
	body.scale = Vector2.ONE * monster_data.visual_scale
	accent.default_color = monster_data.accent_color
	accent.scale = Vector2.ONE * monster_data.visual_scale
	unit_label.text = monster_data.display_name
	_configure_collision()
	_configure_combat()
	_configure_special_ability()


func _configure_collision() -> void:
	if collision_shape != null and collision_shape.shape is CircleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		(collision_shape.shape as CircleShape2D).radius = (
			monster_data.collision_radius
		)
	navigation_agent.radius = monster_data.collision_radius + 2.0


func _configure_combat() -> void:
	var is_melee := (
		monster_data.attack_style == MonsterProductionData.AttackStyle.MELEE
	)
	melee_component.combat_enabled = is_melee
	melee_component.attack_damage = monster_data.damage
	melee_component.attack_interval = monster_data.attack_interval
	melee_component.attack_range = monster_data.attack_range
	melee_component.acquisition_range = monster_data.acquisition_range
	melee_component.chase_range = monster_data.chase_range
	melee_component.target_priority = monster_data.target_priority
	ranged_component.combat_enabled = not is_melee
	ranged_component.attack_damage = monster_data.damage
	ranged_component.attack_interval = monster_data.attack_interval
	ranged_component.attack_range = monster_data.attack_range
	ranged_component.projectile_speed = monster_data.projectile_speed
	ranged_component.projectile_modulate = monster_data.projectile_color
	ranged_component.target_priority = monster_data.target_priority


func _configure_special_ability() -> void:
	_clear_aura_targets()
	_aura_buffs.clear()
	buff_indicator.visible = false
	_stealth_remaining = 0.0
	stealth_indicator.visible = false
	aura_ring.visible = false
	if (
		monster_data.special_ability
		== MonsterProductionData.SpecialAbility.SHORT_STEALTH
	):
		_stealth_remaining = monster_data.stealth_duration
		stealth_indicator.visible = _stealth_remaining > 0.0
		stealth_changed.emit(is_hidden_from_human())
	elif (
		monster_data.special_ability
		== MonsterProductionData.SpecialAbility.SUPPORT_AURA
	):
		aura_ring.points = _make_circle_points(monster_data.aura_radius, 40)
		aura_ring.visible = true


func _update_stealth(delta: float) -> void:
	if _stealth_remaining <= 0.0:
		return
	_stealth_remaining = maxf(_stealth_remaining - delta, 0.0)
	if is_zero_approx(_stealth_remaining):
		_end_stealth()


func _end_stealth() -> void:
	if _stealth_remaining <= 0.0 and not stealth_indicator.visible:
		return
	_stealth_remaining = 0.0
	stealth_indicator.visible = false
	stealth_changed.emit(false)
	_refresh_human_fog()


func _on_attack_performed(_target: Node2D, _damage: float) -> void:
	_end_stealth()


func _on_projectile_fired(_projectile: Node2D, _target: Node2D) -> void:
	_end_stealth()


func _refresh_human_fog() -> void:
	if not is_inside_tree():
		return
	var fog_manager := get_tree().get_first_node_in_group(&"human_fog_manager")
	if fog_manager != null:
		fog_manager.call("refresh_visibility")


func _update_support_aura(delta: float) -> void:
	if (
		monster_data == null
		or monster_data.special_ability
		!= MonsterProductionData.SpecialAbility.SUPPORT_AURA
		or health_component == null
		or health_component.is_dead
	):
		return
	_aura_update_elapsed -= delta
	if _aura_update_elapsed > 0.0:
		return
	_aura_update_elapsed = 0.2
	_refresh_aura_targets()


func _refresh_aura_targets() -> void:
	var next_target_ids: Dictionary[int, bool] = {}
	for candidate_node in get_tree().get_nodes_in_group(&"monster_units"):
		var candidate := candidate_node as MonsterUnit
		if candidate == null or candidate == self:
			continue
		var candidate_health := candidate.health_component as HealthComponent
		if candidate_health == null or candidate_health.is_dead:
			continue
		if global_position.distance_to(candidate.global_position) > monster_data.aura_radius:
			continue
		var candidate_id := candidate.get_instance_id()
		next_target_ids[candidate_id] = true
		_aura_targets[candidate_id] = weakref(candidate)
		candidate.set_aura_buff(
			get_instance_id(),
			monster_data.aura_damage_multiplier,
			monster_data.aura_speed_multiplier
		)
	for previous_id in _aura_targets.keys():
		if next_target_ids.has(previous_id):
			continue
		_remove_buff_from_aura_target(previous_id)


func _clear_aura_targets() -> void:
	for target_id in _aura_targets.keys():
		_remove_buff_from_aura_target(target_id)
	_aura_targets.clear()


func _remove_buff_from_aura_target(target_id: int) -> void:
	var target_ref := _aura_targets.get(target_id) as WeakRef
	_aura_targets.erase(target_id)
	if target_ref == null:
		return
	var target := target_ref.get_ref() as MonsterUnit
	if target != null and is_instance_valid(target):
		target.remove_aura_buff(get_instance_id())


func _apply_aura_multipliers() -> void:
	var damage_multiplier := get_current_damage_multiplier()
	var speed_multiplier := get_current_speed_multiplier()
	move_speed = _base_move_speed * speed_multiplier
	melee_component.attack_damage = _base_damage * damage_multiplier
	ranged_component.attack_damage = _base_damage * damage_multiplier
	buff_indicator.visible = is_aura_buffed()


func _on_monster_died(_source: Node) -> void:
	_stealth_remaining = 0.0
	stealth_indicator.visible = false
	aura_ring.visible = false
	_clear_aura_targets()
	_aura_buffs.clear()
	buff_indicator.visible = false
	set_legion_slot(0)


func _make_circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments + 1:
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2.RIGHT.rotated(angle) * radius)
	return points
