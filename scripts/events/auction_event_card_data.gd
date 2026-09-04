class_name AuctionEventCardData
extends Resource

enum Alignment {
	HUMAN,
	MONSTER,
	NEUTRAL,
}

enum EffectKind {
	NONE,
	TOWER_COMBAT,
	HUMAN_COMBAT,
	MONSTER_COMBAT,
	MONSTER_PRODUCTION_COST,
	MONSTER_TYPE_COST,
	HUMAN_VISION,
	MONSTER_INCOME,
	HUMAN_REPAIR,
	ECLIPSE,
	MAGIC_STORM,
}

@export var event_id: StringName
@export_range(1, 2, 1) var round_index := 1
@export var title: String
@export_multiline var description: String
@export var alignment: Alignment = Alignment.NEUTRAL
@export_multiline var effect_summary: String
@export_range(0, 1000000, 1) var resource_reward := 0
@export var effect_kind: EffectKind = EffectKind.NONE
@export_range(0.0, 600.0, 1.0) var duration := 0.0
@export_range(0.0, 10.0, 0.05) var primary_value := 1.0
@export_range(0.0, 10.0, 0.05) var secondary_value := 1.0
@export var target_id: StringName
