class_name MonsterLegionManager
extends Node

## Owns four lightweight, mutually exclusive Monster control groups.

signal legion_changed(slot: int, units: Array[Node2D])
signal active_legion_changed(slot: int)
signal legion_creation_failed(reason: StringName)

@export_range(1, 9, 1) var max_legions := 4

var selection_manager: UnitSelectionManager
var fog_of_war_manager: FogOfWarManager
var _legions: Dictionary[int, Array] = {}
var _active_slot := 0
var _player_input_enabled := true


func _ready() -> void:
	add_to_group(&"monster_legion_manager")
	call_deferred("_bind_dependencies")


func _unhandled_input(event: InputEvent) -> void:
	if (
		not _player_input_enabled
		or not event is InputEventKey
		or not event.pressed
		or event.echo
		or not _is_monster_view_active()
	):
		return
	var slot := _slot_from_key(event as InputEventKey)
	if slot == 0:
		return
	if (event as InputEventKey).ctrl_pressed:
		create_legion(slot)
	else:
		select_legion(slot)


func create_legion(slot: int, units: Array[Node2D] = []) -> bool:
	_bind_dependencies()
	if slot < 1 or slot > max_legions:
		legion_creation_failed.emit(&"invalid_slot")
		return false
	var source_units := units
	if source_units.is_empty() and selection_manager != null:
		source_units = selection_manager.get_selected_units()
	var monsters := _filter_living_monsters(source_units)
	if monsters.is_empty():
		legion_creation_failed.emit(&"no_monsters_selected")
		return false

	_clear_legion_members(slot)
	for monster in monsters:
		_remove_from_other_legions(monster, slot)
	var references: Array[WeakRef] = []
	for monster in monsters:
		references.append(weakref(monster))
		monster.call("set_legion_slot", slot)
	_legions[slot] = references
	_set_active_slot(slot)
	legion_changed.emit(slot, monsters.duplicate())
	return true


func create_next_legion() -> int:
	for slot in range(1, max_legions + 1):
		if get_legion_units(slot).is_empty():
			return slot if create_legion(slot) else 0
	var replacement_slot := _active_slot if _active_slot > 0 else 1
	return replacement_slot if create_legion(replacement_slot) else 0


func select_legion(slot: int) -> bool:
	_bind_dependencies()
	var units := get_legion_units(slot)
	if units.is_empty() or selection_manager == null:
		return false
	selection_manager.select_units(units)
	_set_active_slot(slot)
	return true


func get_legion_units(slot: int) -> Array[Node2D]:
	var units: Array[Node2D] = []
	var references: Array = _legions.get(slot, [])
	for reference_value in references:
		var reference := reference_value as WeakRef
		if reference == null:
			continue
		var unit := reference.get_ref() as Node2D
		if (
			unit != null
			and is_instance_valid(unit)
			and unit.is_in_group(&"selectable_units")
		):
			units.append(unit)
	if units.size() != references.size():
		var cleaned: Array[WeakRef] = []
		for unit in units:
			cleaned.append(weakref(unit))
		_legions[slot] = cleaned
		legion_changed.emit(slot, units.duplicate())
	return units


func get_active_slot() -> int:
	return _active_slot


func set_player_input_enabled(value: bool) -> void:
	_player_input_enabled = value
	if not value and selection_manager != null:
		selection_manager.clear_selection()


func clear_legion(slot: int) -> void:
	if slot < 1 or slot > max_legions:
		return
	_clear_legion_members(slot)
	_legions.erase(slot)
	if _active_slot == slot:
		_set_active_slot(0)
	legion_changed.emit(slot, [])


func _bind_dependencies() -> void:
	if selection_manager == null or not is_instance_valid(selection_manager):
		selection_manager = get_tree().get_first_node_in_group(
			&"unit_selection_manager"
		) as UnitSelectionManager
	if fog_of_war_manager == null or not is_instance_valid(fog_of_war_manager):
		fog_of_war_manager = get_tree().get_first_node_in_group(
			&"human_fog_manager"
		) as FogOfWarManager


func _filter_living_monsters(units: Array[Node2D]) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		var faction := FactionComponent.find_on(unit)
		var health := unit.get_node_or_null("HealthComponent") as HealthComponent
		if (
			faction != null
			and faction.faction == FactionComponent.Faction.MONSTER
			and (health == null or not health.is_dead)
			and unit.has_method("set_legion_slot")
			and not result.has(unit)
		):
			result.append(unit)
	return result


func _clear_legion_members(slot: int) -> void:
	for unit in get_legion_units(slot):
		if unit.call("get_legion_slot") == slot:
			unit.call("set_legion_slot", 0)


func _remove_from_other_legions(unit: Node2D, destination_slot: int) -> void:
	for slot in range(1, max_legions + 1):
		if slot == destination_slot:
			continue
		var units := get_legion_units(slot)
		if not units.has(unit):
			continue
		units.erase(unit)
		var references: Array[WeakRef] = []
		for member in units:
			references.append(weakref(member))
		_legions[slot] = references
		legion_changed.emit(slot, units.duplicate())


func _set_active_slot(slot: int) -> void:
	if _active_slot == slot:
		return
	_active_slot = slot
	active_legion_changed.emit(_active_slot)


func _is_monster_view_active() -> bool:
	_bind_dependencies()
	return (
		fog_of_war_manager != null
		and fog_of_war_manager.is_monster_view_active()
	)


func _slot_from_key(event: InputEventKey) -> int:
	var key := event.keycode
	if key < KEY_1 or key > KEY_9:
		key = event.physical_keycode
	if key < KEY_1 or key > KEY_9:
		return 0
	var slot := int(key - KEY_1) + 1
	return slot if slot <= max_legions else 0
