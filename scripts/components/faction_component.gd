class_name FactionComponent
extends Node

## Identifies an actor's faction without coupling it to combat behavior.

enum Faction {
	NEUTRAL,
	HUMAN,
	MONSTER,
}

@export var faction: Faction = Faction.NEUTRAL


func is_same_faction(other: FactionComponent) -> bool:
	return other != null and faction == other.faction


func is_hostile_to(other: FactionComponent) -> bool:
	if other == null:
		return false
	if faction == Faction.NEUTRAL or other.faction == Faction.NEUTRAL:
		return false
	return faction != other.faction


func get_faction_name() -> String:
	return Faction.keys()[faction].capitalize()


static func find_on(actor: Node) -> FactionComponent:
	if actor == null:
		return null
	if actor is FactionComponent:
		return actor as FactionComponent
	return actor.get_node_or_null("FactionComponent") as FactionComponent
