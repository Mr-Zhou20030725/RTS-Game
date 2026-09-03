class_name AuctionEventCardData
extends Resource

enum Alignment {
	HUMAN,
	MONSTER,
	NEUTRAL,
}

@export var event_id: StringName
@export var title: String
@export_multiline var description: String
@export var alignment: Alignment = Alignment.NEUTRAL
@export_multiline var effect_summary: String
@export_range(0, 1000000, 1) var resource_reward := 0
