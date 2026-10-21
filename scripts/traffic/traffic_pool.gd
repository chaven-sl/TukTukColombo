class_name TrafficPool
extends RefCounted
## Fixed-capacity pool of pre-built TrafficAgents, bucketed by vehicle class.
## Nothing is instantiated or freed during normal gameplay.

var all_agents: Array[TrafficAgent] = []
var _free: Dictionary = {}  # TrafficVehicleClass -> Array[TrafficAgent]


func add(agent: TrafficAgent) -> void:
	all_agents.append(agent)
	_bucket(agent.vehicle_class).append(agent)


func acquire(cls: TrafficVehicleClass) -> TrafficAgent:
	var bucket := _bucket(cls)
	if bucket.is_empty():
		return null
	return bucket.pop_back()


func release(agent: TrafficAgent) -> void:
	var bucket := _bucket(agent.vehicle_class)
	if bucket.has(agent):
		push_error("[TrafficPool] double release of %s" % agent.name)
		return
	bucket.append(agent)


func free_count(cls: TrafficVehicleClass) -> int:
	return _bucket(cls).size()


func total_free() -> int:
	var n := 0
	for bucket in _free.values():
		n += (bucket as Array).size()
	return n


func capacity() -> int:
	return all_agents.size()


func _bucket(cls: TrafficVehicleClass) -> Array[TrafficAgent]:
	if not _free.has(cls):
		var bucket: Array[TrafficAgent] = []
		_free[cls] = bucket
	return _free[cls]
