extends RefCounted
## Speed units. Physics runs in metres per second; the player sees miles per hour.

const MPH := 2.23694
const MPH_LABEL := "mph"


static func mph(metres_per_second: float) -> int:
	return roundi(metres_per_second * MPH)
