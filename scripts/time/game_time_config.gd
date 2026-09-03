class_name GameTimeConfig
extends Resource

@export_category("阶段时间（秒）")
@export_range(0.0, 7200.0, 1.0) var minute_5_time: float = 300.0
@export_range(0.0, 7200.0, 1.0) var minute_15_time: float = 900.0
@export_range(0.0, 7200.0, 1.0) var minute_20_time: float = 1200.0
@export_range(0.0, 7200.0, 1.0) var minute_25_time: float = 1500.0
@export_range(0.0, 7200.0, 1.0) var minute_30_time: float = 1800.0

@export_category("开发调试")
@export var debug_time_scales: PackedFloat32Array = PackedFloat32Array([1.0, 10.0, 60.0])


func get_milestone_times() -> PackedFloat32Array:
	return PackedFloat32Array([
		minute_5_time,
		minute_15_time,
		minute_20_time,
		minute_25_time,
		minute_30_time,
	])
