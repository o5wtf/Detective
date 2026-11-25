class_name ModelDownload
extends Node
## Четыре файла Parakeet v3 int8 в user://. В APK их нет, ключ в запрос не входит.
## URL_PREFIX — единственное место, которое меняется при переходе на релиз GitHub.
## Имена файлов и SHA-256 при этом остаются.


signal progress_changed(received: int, total: int)
signal state_changed(status: String, detail: String)

const REVISION := "ed5d745623472f97cfc2e6c2916ee248798fc5a8"
const URL_PREFIX := "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/ed5d745623472f97cfc2e6c2916ee248798fc5a8"
const DEFAULT_DIR := "user://models/parakeet-v3"
const NEED_FREE := 800 * 1024 * 1024

const FILES: Array = [
	{"name": "encoder.int8.onnx", "sha256": "1afbe69c1ffdabee94755f42e4daf1d93549131a3da11356bda84fcef0f2c479", "size": 652282294},
	{"name": "decoder.int8.onnx", "sha256": "0222a86147299d4dee90edf95b6d13827edb42ad8b7c9cf0b2582f030937c0b5", "size": 11845274},
	{"name": "joiner.int8.onnx", "sha256": "cbd02f3696e9944970111fb439d9c3fd365a80374565f13f2b9c7007d253fc98", "size": 6355277},
	{"name": "tokens.txt", "sha256": "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d", "size": 93939},
]

static var storage_dir: String = DEFAULT_DIR
static var files_override: Array = []

var transport: Object = null
var free_override: int = -1
var running: bool = false
var _cancel: bool = false
var _epoch: int = 0
var _http: HTTPRequest


static func specs() -> Array:
	if not files_override.is_empty():
		return files_override
	return FILES


static func file_url(file_name: String) -> String:
	return "%s/%s" % [URL_PREFIX, file_name]


static func install_dir() -> String:
	return storage_dir


static func final_path(file_name: String) -> String:
	return "%s/%s" % [install_dir(), file_name]


static func part_path(file_name: String) -> String:
	return "%s/%s.part" % [install_dir(), file_name]


static func is_installed() -> bool:
	for spec in specs():
		var path := final_path(str(spec["name"]))
		if path.ends_with(".part") or not FileAccess.file_exists(path):
			return false
	return true


static func space_ok(free_bytes: int) -> bool:
	return free_bytes >= NEED_FREE


static func total_bytes() -> int:
	var total := 0
	for spec in specs():
		total += int(spec["size"])
	return total


static func resume_plan(part_bytes: int, accepts_range: bool) -> Dictionary:
	if part_bytes > 0 and accepts_range:
		return {"restart": false, "range": "bytes=%d-" % part_bytes}
	return {"restart": true, "range": ""}


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(install_dir())


static func delete_all() -> void:
	for spec in specs():
		var file_name := str(spec["name"])
		for path in [final_path(file_name), part_path(file_name), part_path(file_name) + ".chunk"]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


static func file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return 0
	var size := handle.get_length()
	handle.close()
	return size


static func commit_part(part: String, final: String, expected_sha: String) -> String:
	if not FileAccess.file_exists(part):
		return "missing"
	var actual := FileAccess.get_sha256(part)
	if actual != expected_sha.to_lower():
		DirAccess.remove_absolute(part)
		return "bad_hash"
	ensure_dir()
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final)
	if DirAccess.rename_absolute(part, final) != OK:
		return "rename"
	return ""


static func absorb(part: String, status: int, body: String, ranged: bool) -> String:
	if status == 206 and ranged:
		if not FileAccess.file_exists(part):
			var created := FileAccess.open(part, FileAccess.WRITE)
			if created == null:
				return "fail"
			created.close()
		if not _append_file(part, body):
			return "fail"
		if body != part and FileAccess.file_exists(body):
			DirAccess.remove_absolute(body)
		return "ok"
	if status == 200:
		if body == part:
			return "ok"
		if FileAccess.file_exists(part):
			DirAccess.remove_absolute(part)
		if DirAccess.rename_absolute(body, part) != OK:
			return "fail"
		return "ok"
	if body != "" and body != part and FileAccess.file_exists(body):
		DirAccess.remove_absolute(body)
	return "fail"


static func _append_file(dest: String, src: String) -> bool:
	var incoming := FileAccess.open(src, FileAccess.READ)
	var outgoing := FileAccess.open(dest, FileAccess.READ_WRITE)
	if incoming == null or outgoing == null:
		return false
	outgoing.seek_end()
	while incoming.get_position() < incoming.get_length():
		var chunk := incoming.get_buffer(262144)
		if chunk.is_empty():
			break
		outgoing.store_buffer(chunk)
	incoming.close()
	outgoing.close()
	return true


func start() -> void:
	await _tick()
	if running:
		return
	if not space_ok(_free_space()):
		state_changed.emit("space", GameLanguage.text("model_space"))
		return
	running = true
	_cancel = false
	var epoch := _epoch
	state_changed.emit("running", GameLanguage.text("model_wifi"))
	ensure_dir()
	for spec in specs():
		if _cancel or epoch != _epoch:
			break
		var err := await _fetch_one(spec, epoch)
		if _cancel or epoch != _epoch:
			break
		if err != "":
			running = false
			var detail := GameLanguage.text("model_corrupt") if err == "bad_hash" else GameLanguage.text("model_stopped")
			state_changed.emit(err, detail)
			return
	running = false
	if _cancel or epoch != _epoch:
		state_changed.emit("cancelled", GameLanguage.text("model_stopped"))
		return
	if is_installed():
		_emit_progress(total_bytes())
		state_changed.emit("ready", GameLanguage.text("model_ready"))
	else:
		state_changed.emit("stopped", GameLanguage.text("model_stopped"))


func cancel() -> void:
	_cancel = true
	_epoch += 1
	if _http != null:
		_http.cancel_request()


func _fetch_one(spec: Dictionary, epoch: int) -> String:
	await _tick()
	var file_name := str(spec["name"])
	var expected_sha := str(spec["sha256"]).to_lower()
	var expected_size := int(spec["size"])
	var final := final_path(file_name)
	var part := part_path(file_name)
	if FileAccess.file_exists(final) and FileAccess.get_sha256(final) == expected_sha:
		return ""
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final)
	var attempt := 0
	while attempt < 2:
		attempt += 1
		if _cancel or epoch != _epoch:
			return "cancelled"
		var existing := file_size(part)
		if existing > expected_size:
			DirAccess.remove_absolute(part)
			existing = 0
		var ranged := existing > 0
		var headers := PackedStringArray()
		if ranged:
			var plan := resume_plan(existing, true)
			headers.append("Range: %s" % str(plan["range"]))
		var dest := part if not ranged else part + ".chunk"
		var response := await _request(file_url(file_name), headers, dest)
		if _cancel or epoch != _epoch:
			return "cancelled"
		var result_code := int(response.get("result", 1))
		var status := int(response.get("status", 0))
		if result_code != 0:
			return "stopped"
		if status == 416 and ranged:
			DirAccess.remove_absolute(part)
			continue
		if absorb(part, status, dest, ranged) != "ok":
			return "stopped"
		var size := file_size(part)
		if status == 200 and size != expected_size:
			DirAccess.remove_absolute(part)
			return "bad_hash"
		if size > expected_size:
			DirAccess.remove_absolute(part)
			return "bad_hash"
		if size < expected_size:
			return "partial"
		var committed := commit_part(part, final, expected_sha)
		if committed != "":
			return committed
		_emit_progress(_completed_bytes())
		return ""
	return "stopped"


func _request(url: String, headers: PackedStringArray, dest: String) -> Dictionary:
	if transport != null:
		var pending: Variant = transport.call("request", url, headers, dest)
		if pending is Dictionary:
			await _tick()
			return pending
		pending = await pending
		return pending
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 0
		_http.use_threads = true
		add_child(_http)
	_http.download_file = ProjectSettings.globalize_path(dest)
	_http.cancel_request()
	var err := _http.request(url, headers)
	if err != OK:
		return {"result": int(err), "status": 0}
	var completed: Variant = await _http.request_completed
	if completed is Array:
		return {"result": int(completed[0]), "status": int(completed[1])}
	return {"result": 1, "status": 0}


func _free_space() -> int:
	if free_override >= 0:
		return free_override
	var dir := DirAccess.open("user://")
	if dir == null:
		return NEED_FREE
	var left := dir.get_space_left()
	if left < 0:
		return NEED_FREE
	return left


func _completed_bytes() -> int:
	var total := 0
	for spec in specs():
		if FileAccess.file_exists(final_path(str(spec["name"]))):
			total += int(spec["size"])
	return total


func _emit_progress(received: int) -> void:
	progress_changed.emit(received, total_bytes())


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
