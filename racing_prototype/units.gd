extends RefCounted
## Speed units. Physics runs in metres per second; the player sees miles per hour.

const MPH := 1.0 / 0.44704
const MPH_LABEL := "mph"
const METERS_PER_MILE := 1609.344


static func mph(metres_per_second: float) -> int:
	return roundi(metres_per_second * MPH)


static func miles(meters: float) -> float:
	return meters / METERS_PER_MILE
