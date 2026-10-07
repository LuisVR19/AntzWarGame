extends RefCounted
## Base class for tests (no plugins needed). Test files live in res://tests,
## are named test_*.gd, extend this script and define methods test_*().
##
## IMPORTANT: every test method must end with `return done()`. GDScript has
## no exceptions: a runtime error aborts the method and returns null, and the
## runner reports that as "aborted" instead of silently passing.

var tree: SceneTree
var current_test := ""
var failures: PackedStringArray = PackedStringArray()


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func done() -> bool:
	return true


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message := "") -> void:
	var equal := false
	if _is_number(actual) and _is_number(expected):
		equal = is_equal_approx(float(actual), float(expected))
	else:
		equal = typeof(actual) == typeof(expected) and actual == expected
	if not equal:
		failures.append("%s (esperado %s, obtenido %s)" % [message, var_to_str(expected), var_to_str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message := "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (esperado %.3f ± %.3f, obtenido %.3f)" % [message, expected, tolerance, actual])


## Awaits frames until cond.call() is true or the timeout expires.
func wait_until(cond: Callable, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await tree.process_frame
	return true


func wait_frames(count: int) -> void:
	for i in count:
		await tree.process_frame


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
