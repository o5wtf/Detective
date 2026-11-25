class_name SaveState
extends RefCounted
## Одна партия на дело: user://saves/<case_id>.json.
## В файле нет ключа API.

const FORMAT := 1
const DIR := "user://saves"


static func file_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


static func case_id_from_path(path: String) -> String:
	var loaded := CaseLoader.load_case(path)
	if not loaded.ok or loaded.case_data == null:
		return ""
	return loaded.case_data.id


static func exists(case_id: String) -> bool:
	return case_id != "" and FileAccess.file_exists(slot_path(case_id))


static func slot_path(case_id: String) -> String:
	return "%s/%s.json" % [DIR, _safe(case_id)]


static var fail_before_rename: bool = false


static func write_state(state: GameState) -> bool:
	if state == null or state.case_id.strip_edges() == "":
		return false
	DirAccess.make_dir_recursive_absolute(DIR)
	var envelope := {
		"format": FORMAT,
		"case_id": state.case_id,
		"case_version_hash": state.case_version_hash,
		"state": _without_secrets(state.to_dict()),
	}
	var dest := slot_path(state.case_id)
	var temp := dest + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	file.close()
	if fail_before_rename:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false
	var dest_abs := ProjectSettings.globalize_path(dest)
	var temp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(dest):
		var bak := dest_abs + ".bak"
		if DirAccess.rename_absolute(dest_abs, bak) != OK:
			DirAccess.remove_absolute(temp_abs)
			return false
		if DirAccess.rename_absolute(temp_abs, dest_abs) != OK:
			DirAccess.rename_absolute(bak, dest_abs)
			DirAccess.remove_absolute(temp_abs)
			return false
		DirAccess.remove_absolute(bak)
		return true
	return DirAccess.rename_absolute(temp_abs, dest_abs) == OK


static func read(case_id: String) -> Dictionary:
	var path := slot_path(case_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing"}
	var text := FileAccess.get_file_as_string(path).strip_edges()
	if not text.begins_with("{"):
		return {"ok": false, "reason": "corrupt"}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or parsed is not Dictionary:
		return {"ok": false, "reason": "corrupt"}
	var body := parsed as Dictionary
	if not body.has("format") or int(body.get("format", -1)) != FORMAT:
		return {"ok": false, "reason": "version"}
	if body.get("state") is not Dictionary:
		return {"ok": false, "reason": "corrupt"}
	return {
		"ok": true,
		"reason": "",
		"case_id": str(body.get("case_id", "")),
		"hash": str(body.get("case_version_hash", "")),
		"state": body.get("state"),
	}


static func discard(case_id: String) -> void:
	var path := slot_path(case_id)
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _safe(case_id: String) -> String:
	var out := ""
	for index in case_id.length():
		var ch := case_id[index]
		var ok := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-"
		out += ch if ok else "_"
	if out == "":
		return "case"
	return out


static func without_secrets(value: Variant) -> Variant:
	return _without_secrets(value)


static func _secret_key(name: String) -> bool:
	return name == "api_key" or name == "gemini_api_key" or name == "chirp_key" or name == "private_key" or name == "key" or name == "token" or name == "secret"


static func _without_secrets(value: Variant) -> Variant:
	if value is Dictionary:
		var copy := {}
		for key in value:
			var name := str(key)
			if _secret_key(name):
				continue
			copy[key] = _without_secrets(value[key])
		return copy
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_without_secrets(item))
		return items
	if value is String:
		return _scrub_secret_text(value)
	return value


static func _scrub_secret_text(text: String) -> String:
	var store := SettingsStore.load_current()
	if store.api_key.length() >= 8 and text == store.api_key:
		return ""
	if store.chirp_key.length() >= 8 and text == store.chirp_key:
		return ""
	return text
