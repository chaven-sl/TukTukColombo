class_name MathUtil
extends RefCounted
## Small allocation-free math helpers shared by gameplay systems.


## Basis whose -Z axis points along `forward` (projected flat), +Y up.
static func basis_from_forward(forward: Vector3) -> Basis:
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 0.000001:
		f = Vector3.FORWARD
	f = f.normalized()
	var z := -f
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)


## Exponential smoothing factor for frame-rate independent lerps.
static func smoothing(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
