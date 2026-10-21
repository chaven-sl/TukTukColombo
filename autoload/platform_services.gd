extends Node
## Platform service facade. v0.01: every method is a safe NO-OP.
##
## Gameplay code may call these methods but must never depend on a third-party
## SDK directly. Future adapters (analytics, ads, billing, cloud save) plug in
## behind this interface without touching gameplay.

signal rewarded_ad_finished(placement: String, rewarded: bool)
signal interstitial_closed(placement: String)
signal purchase_finished(product_id: String, success: bool)
signal restore_finished(product_ids: PackedStringArray)
signal cloud_save_finished(slot: String, success: bool)
signal cloud_load_finished(slot: String, success: bool, payload: Dictionary)

## Set true to print every call while developing integrations.
var verbose := false


func track_event(event_name: String, properties: Dictionary = {}) -> void:
	_log("track_event", event_name, properties)


func show_rewarded_ad(placement: String) -> bool:
	_log("show_rewarded_ad", placement)
	rewarded_ad_finished.emit.call_deferred(placement, false)
	return false


func show_interstitial(placement: String) -> bool:
	_log("show_interstitial", placement)
	interstitial_closed.emit.call_deferred(placement)
	return false


func purchase(product_id: String) -> bool:
	_log("purchase", product_id)
	purchase_finished.emit.call_deferred(product_id, false)
	return false


func restore_purchases() -> void:
	_log("restore_purchases")
	restore_finished.emit.call_deferred(PackedStringArray())


func is_online() -> bool:
	return false


func cloud_save(slot: String, payload: Dictionary) -> bool:
	_log("cloud_save", slot, payload.size())
	cloud_save_finished.emit.call_deferred(slot, false)
	return false


func cloud_load(slot: String) -> bool:
	_log("cloud_load", slot)
	cloud_load_finished.emit.call_deferred(slot, false, {})
	return false


func _log(method: String, a: Variant = null, b: Variant = null) -> void:
	if verbose:
		print("[PlatformServices] %s(%s, %s) -> no-op" % [method, a, b])
