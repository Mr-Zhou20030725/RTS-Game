class_name HumanSquadManager
extends Node2D

## Purchases and spawns Resource-configured Human squads.

signal squad_recruited(squad: Node2D, data: HumanSquadData, cost: int)
signal recruitment_failed(reason: StringName)

@export var member_scene: PackedScene
@export var squad_catalog: Array[Resource] = []
@export var spawn_origin := Vector2(640.0, 500.0)
@export var squad_spawn_spacing := Vector2(130.0, 0.0)

var human_economy: Node
var _squads: Array[Node2D] = []
var _squad_serial := 0


func _ready() -> void:
	call_deferred("_bind_human_economy")


func recruit_squad(catalog_index: int) -> bool:
	if (
		catalog_index < 0
		or catalog_index >= squad_catalog.size()
		or member_scene == null
	):
		recruitment_failed.emit(&"invalid_configuration")
		return false
	var data := squad_catalog[catalog_index] as HumanSquadData
	if data == null or data.member_count < 2:
		recruitment_failed.emit(&"invalid_configuration")
		return false
	_bind_human_economy()
	if (
		human_economy == null
		or not human_economy.call("try_spend", data.cost, &"squad_recruitment")
	):
		recruitment_failed.emit(&"not_enough_gold")
		return false

	_squad_serial += 1
	var squad := Node2D.new()
	var instance_id := StringName("human_squad_%02d" % _squad_serial)
	squad.name = "HumanSquad_%02d_%s" % [_squad_serial, data.squad_id]
	squad.add_to_group(&"human_squads")
	add_child(squad)
	squad.global_position = _get_spawn_position(_squad_serial - 1)
	_spawn_members(squad, data, instance_id)
	_squads.append(squad)
	squad_recruited.emit(squad, data, data.cost)
	return true


func get_squad_catalog() -> Array[Resource]:
	return squad_catalog.duplicate()


func get_recruited_squads() -> Array[Node2D]:
	for index in range(_squads.size() - 1, -1, -1):
		if not is_instance_valid(_squads[index]):
			_squads.remove_at(index)
	return _squads.duplicate()


func _spawn_members(
	squad: Node2D, data: HumanSquadData, instance_id: StringName
) -> void:
	var columns := ceili(sqrt(float(data.member_count)))
	var rows := ceili(float(data.member_count) / float(columns))
	var formation_size := Vector2(
		float(columns - 1) * data.formation_spacing,
		float(rows - 1) * data.formation_spacing
	)
	for member_index in data.member_count:
		var member := member_scene.instantiate() as Node2D
		member.call("configure_member", data, instance_id, member_index)
		member.name = "%s_%02d" % [data.display_name.replace(" ", ""), member_index + 1]
		squad.add_child(member)
		var column := member_index % columns
		var row := member_index / columns
		member.position = Vector2(
			float(column) * data.formation_spacing,
			float(row) * data.formation_spacing
		) - formation_size * 0.5


func _get_spawn_position(squad_index: int) -> Vector2:
	# Keep all first four squads inside the battlefield''s safe band and away
	# from the dedicated command dock below y=720.
	var column := squad_index % 4
	var row := squad_index / 4
	return spawn_origin + Vector2(
		(float(column) - 1.5) * squad_spawn_spacing.x,
		float(row) * 90.0
	)


func _bind_human_economy() -> void:
	if human_economy != null and is_instance_valid(human_economy):
		return
	human_economy = get_tree().get_first_node_in_group(&"human_economy")
