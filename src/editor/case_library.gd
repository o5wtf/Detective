class_name CaseLibrary
extends RefCounted
## Опубликованные дела, черновики и побайтная копия примера.


const BUILTIN := "res://cases/rain_over_shadow.json"

static var cases_root := "user://cases"
static var drafts_root := "user://case_drafts"
static var documents_root := ""
static var documents_fail := ""
static var draft_fail := false


static func ensure_example() -> void:
	var builtin := FileAccess.get_file_as_bytes(BUILTIN)
	var fresh := _sha(builtin)
	var id := _id_in(builtin)
	if id == "":
		return
	var path := published_path(id)
	var stored := _read_text(hash_path(id)).strip_edges()
	var have := FileAccess.file_exists(path)
	var same := have and FileAccess.get_file_as_bytes(path) == builtin
	if have and stored == fresh and same:
		return
	if have and stored != "" and stored != fresh:
		SaveState.discard(id)
	elif have and not same:
		SaveState.discard(id)
	_write_bytes(path, builtin)
	_write_text(hash_path(id), fresh)


static func example_id() -> String:
	return _id_in(FileAccess.get_file_as_bytes(BUILTIN))


static func is_example(case_id: String) -> bool:
	return case_id != "" and case_id == example_id()


static func published_path(case_id: String) -> String:
	return "%s/%s.json" % [cases_root, SaveState._safe(case_id)]


static func draft_path(case_id: String) -> String:
	return "%s/%s.json" % [drafts_root, SaveState._safe(case_id)]


static func prev_path(case_id: String) -> String:
	return "%s/%s.prev.json" % [drafts_root, SaveState._safe(case_id)]


static func hash_path(case_id: String) -> String:
	return "%s/%s.sha256" % [cases_root, SaveState._safe(case_id)]


static func list_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var seen := {}
	for folder in [cases_root, drafts_root]:
		for name in _json_names(folder):
			var id := _id_of_file("%s/%s" % [folder, name])
			if id == "" or seen.has(id):
				continue
			seen[id] = true
			ids.append(id)
	return ids


static func status(case_id: String) -> String:
	if is_example(case_id):
		return "example"
	var published := FileAccess.file_exists(published_path(case_id))
	var draft := FileAccess.file_exists(draft_path(case_id))
	if published and draft:
		var same := FileAccess.get_file_as_bytes(published_path(case_id)) == FileAccess.get_file_as_bytes(draft_path(case_id))
		return "published" if same else "dirty"
	if draft:
		return "draft"
	if published:
		return "published"
	return ""


static func read_source(case_id: String) -> Dictionary:
	var path := draft_path(case_id)
	if not FileAccess.file_exists(path):
		path = published_path(case_id)
	return _read_dict(path)


static func write_draft(case_id: String, raw: Dictionary) -> bool:
	if draft_fail or is_example(case_id):
		return false
	return _write_dict(draft_path(case_id), raw)


static func publish(case_id: String, raw: Dictionary, force: bool = false) -> Dictionary:
	if is_example(case_id):
		return {"ok": false, "warn": false, "notice": ""}
	if SaveState.exists(case_id) and not force:
		return {"ok": false, "warn": true, "notice": ""}
	var path := published_path(case_id)
	if FileAccess.file_exists(path):
		_write_bytes(prev_path(case_id), FileAccess.get_file_as_bytes(path))
	if not _write_dict(path, raw):
		return {"ok": false, "warn": false, "notice": ""}
	_write_bytes(draft_path(case_id), FileAccess.get_file_as_bytes(path))
	if SaveState.exists(case_id):
		SaveState.discard(case_id)
	var notice := _write_documents(case_id, FileAccess.get_file_as_bytes(path))
	return {"ok": true, "warn": false, "notice": notice}


static func copy_case(case_id: String) -> String:
	var raw := read_source(case_id)
	if raw.is_empty():
		return ""
	var copy: Dictionary = SaveState.without_secrets(raw)
	var fresh := unique_id()
	copy["id"] = fresh
	copy["title"] = _copy_title(str(copy.get("title", "")))
	if not _write_dict(draft_path(fresh), copy):
		return ""
	return fresh


static func delete_case(case_id: String) -> bool:
	if is_example(case_id):
		return false
	for path in [published_path(case_id), draft_path(case_id), prev_path(case_id), hash_path(case_id)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveState.discard(case_id)
	return true


static func restore_example() -> void:
	var id := example_id()
	SaveState.discard(id)
	for path in [published_path(id), hash_path(id)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ensure_example()


static func unique_id() -> String:
	var n := 0
	while true:
		var stamp := "%x%x" % [Time.get_ticks_msec(), randi()]
		var case_id := "case_%s" % stamp.substr(0, 12)
		n += 1
		if n > 1:
			case_id = "%s_%d" % [case_id, n]
		if not FileAccess.file_exists(published_path(case_id)) and not FileAccess.file_exists(draft_path(case_id)):
			return case_id
	return "case_fallback"


static func new_case() -> Dictionary:
	var case_id := unique_id()
	return {
		"id": case_id,
		"title": "",
		"briefing": "",
		"intro_atmosphere": "",
		"truth_timeline": "",
		"editor": {"timeline_text": ""},
		"killer_id": "",
		"victory_condition": "correct_accusation",
		"motive_options": [{"id": "motive_1", "text": ""}],
		"true_motive_id": "motive_1",
		"method_options": [{"id": "method_1", "text": ""}],
		"true_method_id": "method_1",
		"agents": [_blank_agent("agent_1"), _blank_agent("agent_2")],
		"evidence": [],
		"contradictions": [],
	}


static func _blank_agent(agent_id: String) -> Dictionary:
	return {
		"id": agent_id,
		"name": "",
		"role": "",
		"gender": "",
		"tts_voice": "",
		"voice_style": "",
		"greeting": "",
		"personality": "",
		"prompt_background": "",
		"starting_emotion": "neutral",
		"profanity": "never",
		"relationships": {},
		"facts": [],
	}


static func _copy_title(title: String) -> String:
	var base := title.strip_edges()
	if base == "":
		base = "Дело"
	if base.ends_with("(копия)"):
		return "%s (копия 2)" % base.trim_suffix(" (копия)").strip_edges()
	return "%s (копия)" % base


static func _write_documents(case_id: String, bytes: PackedByteArray) -> String:
	if documents_fail != "":
		return UiStrings.DOCUMENTS_FAIL % documents_fail
	var folder := documents_root
	if folder == "":
		var base := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if base == "":
			return UiStrings.DOCUMENTS_FAIL % "нет папки"
		folder = base.path_join("Detective")
	var path := "%s/%s.json" % [folder, SaveState._safe(case_id)]
	if _write_bytes(path, bytes):
		return ""
	var stamped := "%s/%s_%s.json" % [folder, SaveState._safe(case_id), Time.get_datetime_string_from_system().replace(":", "").replace(" ", "_")]
	if _write_bytes(stamped, bytes):
		return ""
	return UiStrings.DOCUMENTS_FAIL % "нет доступа"


static func _write_dict(path: String, raw: Dictionary) -> bool:
	var clean: Dictionary = SaveState.without_secrets(raw)
	return _write_text(path, JSON.stringify(clean, "\t"))


static func _read_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


static func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


static func _write_text(path: String, text: String) -> bool:
	return _write_bytes(path, text.to_utf8_buffer())


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func _id_in(bytes: PackedByteArray) -> String:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed is Dictionary:
		return str((parsed as Dictionary).get("id", ""))
	return ""


static func _id_of_file(path: String) -> String:
	return _id_in(FileAccess.get_file_as_bytes(path))


static func _json_names(folder: String) -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir == null:
		return names
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json") and not name.ends_with(".prev.json"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	return names
