class_name HumanSquadMember
extends RTSUnit

## One shared Human unit implementation configured by HumanSquadData.

@export var squad_data: HumanSquadData

@onready var body: Polygon2D = %Body
@onready var accent: Line2D = %Accent
@onready var unit_label: Label = %UnitLabel

var squad_instance_id: StringName
var squad_member_index := -1


func _ready() -> void:
	super._ready()
	_apply_squad_data()


func configure_member(
	data: HumanSquadData, instance_id: StringName, member_index: int
) -> void:
	squad_data = data
	squad_instance_id = instance_id
	squad_member_index = member_index
	if is_node_ready():
		_apply_squad_data()


func get_squad_instance_id() -> StringName:
	return squad_instance_id


func get_squad_member_index() -> int:
	return squad_member_index


func get_squad_data() -> HumanSquadData:
	return squad_data


func _apply_squad_data() -> void:
	if squad_data == null:
		return
	move_speed = squad_data.move_speed
	health_component.max_health = squad_data.max_health
	health_component.current_health = squad_data.max_health
	body.color = squad_data.body_color
	accent.default_color = squad_data.accent_color
	unit_label.text = str(squad_data.squad_id).to_upper()

	melee_component.combat_enabled = (
		squad_data.attack_style == HumanSquadData.AttackStyle.MELEE
	)
	melee_component.attack_damage = squad_data.damage
	melee_component.attack_interval = squad_data.attack_interval
	melee_component.attack_range = squad_data.attack_range
	melee_component.acquisition_range = squad_data.acquisition_range
	melee_component.chase_range = squad_data.chase_range

	ranged_component.combat_enabled = (
		squad_data.attack_style != HumanSquadData.AttackStyle.MELEE
	)
	ranged_component.attack_damage = squad_data.damage
	ranged_component.attack_interval = squad_data.attack_interval
	ranged_component.attack_range = squad_data.attack_range
	ranged_component.projectile_speed = squad_data.projectile_speed
	ranged_component.splash_radius = squad_data.splash_radius
	ranged_component.projectile_modulate = squad_data.accent_color

