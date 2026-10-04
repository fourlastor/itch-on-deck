class_name Bandwidth
extends RefCounted
## The download speed limit, a possible setting in SPEC.md section 4.3.

## Offered values, in kilobits per second. 0 is no limit.
const CHOICES: Array[int] = [0, 1000, 2000, 5000, 10000, 20000, 50000]


static func apply() -> void:
	var kbps := int(Config.get_value("bandwidth_kbps", 0))
	await Butler.request("Network.SetBandwidthThrottle", {"enabled": kbps > 0, "rate": kbps})


static func label(kbps: int) -> String:
	if kbps <= 0:
		return "No limit"
	return "%d Mbit/s" % (kbps / 1000)
