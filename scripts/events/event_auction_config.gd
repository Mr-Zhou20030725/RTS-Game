class_name EventAuctionConfig
extends Resource

@export var cards: Array[AuctionEventCardData] = []
@export_range(0.0, 1.0, 0.01) var round_one_ai_bid_ratio := 0.25
@export_range(0.0, 1.0, 0.01) var round_two_ai_bid_ratio := 0.45
@export_range(0, 1000000, 1) var minimum_ai_bid := 10
@export_multiline var tie_rule_text := "平价：中立牌无人获得，双方均不扣费。"


func get_neutral_card() -> AuctionEventCardData:
	for card in cards:
		if card != null and card.alignment == AuctionEventCardData.Alignment.NEUTRAL:
			return card
	return null


func get_ai_bid_ratio(round_index: int) -> float:
	return round_two_ai_bid_ratio if round_index >= 2 else round_one_ai_bid_ratio
