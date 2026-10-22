class_name PassengerMood
extends RefCounted
## Qualitative in-ride mood for the HUD (presentation only, v0.03A).
##
## The v0.02 live percentage scored elapsed time against the whole route's
## target, so it looked rosy early in a ride. This projects the finish time
## (elapsed + remaining ÷ current pace) and reuses the existing subscore
## functions unchanged. The final numeric rating on the result card still
## comes from PassengerSatisfaction.evaluate(), untouched.

enum Mood { HAPPY, IMPATIENT, NERVOUS, EXCITED, BORED, UPSET }

const KEYS := ["MOOD_HAPPY", "MOOD_IMPATIENT", "MOOD_NERVOUS", "MOOD_EXCITED", "MOOD_BORED", "MOOD_UPSET"]


static func evaluate(t: RideTelemetry, p: PassengerProfile, route_m: float, remaining_m: float, c: RideConfig) -> Mood:
	if t.pedestrian_danger > 0 or t.pedestrian_impacts > 0:
		return Mood.UPSET
	var target := maxf(route_m, 1.0) / (p.expected_speed_kmh / 3.6)
	var pace := maxf(t.average_speed_kmh(), p.expected_speed_kmh * 0.5) / 3.6 if t.elapsed > 5.0 else p.expected_speed_kmh / 3.6
	var projected := t.elapsed + maxf(remaining_m, 0.0) / pace
	var time_score := PassengerSatisfaction.time_subscore(projected / target, c)
	var safety := PassengerSatisfaction.safety_subscore(t, p, c)
	var comfort := PassengerSatisfaction.comfort_subscore(t, p, c)
	var excitement := PassengerSatisfaction.excitement_subscore(t, p, c)
	var w := p.normalised_weights()
	var score := w.x * time_score + w.y * safety + w.z * comfort + w.w * excitement
	if score < 40.0:
		return Mood.UPSET
	if w.w >= 0.3 and excitement >= 55.0 and score >= 60.0:
		return Mood.EXCITED
	# Name the dominant complaint when one subscore drags the mood down.
	var deficits := [w.x * (100.0 - time_score), (w.y + w.z) * (100.0 - minf(safety, comfort)), w.w * (100.0 - excitement)]
	var worst := 0
	for i in deficits.size():
		if float(deficits[i]) > float(deficits[worst]):
			worst = i
	if score >= 70.0 and float(deficits[worst]) < 12.0:
		return Mood.HAPPY
	match worst:
		0:
			return Mood.IMPATIENT if time_score < 75.0 else Mood.HAPPY
		1:
			return Mood.NERVOUS if minf(safety, comfort) < 80.0 else Mood.HAPPY
		_:
			return Mood.BORED if excitement < 50.0 else Mood.HAPPY
