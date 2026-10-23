class_name EconomyFormat
extends RefCounted
## Player-facing money and reputation text: "Rs. 1,250", "★ 120".


static func rupees(amount: int) -> String:
	return "Rs. %s" % group(amount)


static func signed_rupees(amount: int) -> String:
	return ("+" if amount >= 0 else "−") + rupees(absi(amount))


static func stars(amount: int) -> String:
	return "★ %d" % amount


## 1250 → "1,250".
static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
