extends SceneTree
## Minimal headless test runner (no plugins).
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=simulation
##
## Discovers res://tests/**/test_*.gd, runs every test_* method (awaiting
## coroutines), prints a summary and exits with code 0 (ok) or 1 (failures).

const TESTS_DIR := "res://tests"
const SKIP_DIRS := ["framework"]

var _passed := 0
var _failed: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run()


func _run() -> void:
	var filter := _filter_arg()
	var files := _find_tests(TESTS_DIR)
	files.sort()
	print("\n=== AntzGame client tests (%d archivos) ===" % files.size())
	for path in files:
		if not filter.is_empty() and not path.contains(filter):
			continue
		await _run_file(path)
	print("\n=== Resultado: %d OK, %d FALLIDOS ===" % [_passed, _failed.size()])
	for f in _failed:
		print("  ✗ " + f)
	Engine.time_scale = 1.0
	quit(1 if not _failed.is_empty() else 0)


func _run_file(path: String) -> void:
	print("\n# " + path)
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		_failed.append("%s: no se pudo cargar (¿error de sintaxis o de tipos?)" % path)
		return
	var methods: Array[String] = []
	for m in script.get_script_method_list():
		var method_name := str(m["name"])
		if method_name.begins_with("test_") and not methods.has(method_name):
			methods.append(method_name)
	for method_name in methods:
		var case: Variant = script.new()
		case.tree = self
		case.current_test = method_name
		case.before_each()
		var result: Variant = await case.call(method_name)
		case.after_each()
		var label := "%s::%s" % [path.get_file(), method_name]
		if result != true:
			_failed.append("%s: abortado (ver SCRIPT ERROR arriba) o falta `return done()`" % label)
			print("  ✗ %s (abortado)" % method_name)
		elif not case.failures.is_empty():
			for f in case.failures:
				_failed.append("%s: %s" % [label, f])
			print("  ✗ %s" % method_name)
			for f in case.failures:
				print("      - " + f)
		else:
			_passed += 1
			print("  ✓ %s" % method_name)


func _find_tests(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("No se puede abrir %s" % dir_path)
		return out
	for sub in dir.get_directories():
		if not SKIP_DIRS.has(sub):
			out.append_array(_find_tests(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out


func _filter_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			return arg.trim_prefix("--filter=")
	return ""
