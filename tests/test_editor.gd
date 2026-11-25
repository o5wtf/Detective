extends TestCase


func test_example_copy_is_byte_exact_and_named_by_id() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var id := CaseLibrary.example_id()
	var path := CaseLibrary.published_path(id)
	assert_true(path.ends_with("%s.json" % id))
	assert_eq(FileAccess.get_file_as_bytes(path), FileAccess.get_file_as_bytes(CaseLibrary.BUILTIN))
	_restore_roots()


func test_new_builtin_hash_replaces_the_copy_and_drops_the_save() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var id := CaseLibrary.example_id()
	var slot := SaveState.slot_path(id)
	var had := FileAccess.file_exists(slot)
	var previous := FileAccess.get_file_as_bytes(slot) if had else PackedByteArray()
	DirAccess.make_dir_recursive_absolute(SaveState.DIR)
	var marker := FileAccess.open(slot, FileAccess.WRITE)
	marker.store_string("{\"format\":1}")
	marker.close()
	CaseLibrary._write_text(CaseLibrary.hash_path(id), "deadbeef")
	CaseLibrary.ensure_example()
	assert_eq(FileAccess.get_file_as_bytes(CaseLibrary.published_path(id)), FileAccess.get_file_as_bytes(CaseLibrary.BUILTIN))
	assert_false(FileAccess.file_exists(slot))
	if had:
		var restore := FileAccess.open(slot, FileAccess.WRITE)
		restore.store_buffer(previous)
		restore.close()
	_restore_roots()


func test_example_is_view_only_until_copy_and_has_no_delete() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var home := EditorHome.new()
	root.add_child(home)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var id := CaseLibrary.example_id()
	assert_true(home.find_child("Delete_%s" % id, true, false) == null)
	assert_true(home.find_child("Restore_%s" % id, true, false) != null)
	var editor := CaseEditor.new()
	root.add_child(editor)
	editor.open_id(id)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(editor.find_child("ExampleLock", true, false) != null)
	var title := editor.find_child("TitleEdit", true, false) as LineEdit
	assert_false(title.editable)
	assert_eq(title.placeholder_text, "Дождь над «Тенью»")
	var help := editor.find_child("BriefingHelp", true, false) as Button
	help.pressed.emit()
	var popup := editor.find_child("HelpPopup", true, false)
	assert_true(popup.visible)
	assert_true(str((editor.find_child("HelpText", true, false) as Label).text).contains("ВСЕ персонажи"))
	var fresh := CaseLibrary.copy_case(id)
	assert_false(fresh == id)
	assert_false(CaseLibrary.is_example(fresh))
	var again := CaseLibrary.copy_case(id)
	assert_false(again == fresh)
	var first_title := str(CaseLibrary.read_source(fresh).get("title", ""))
	var second_title := str(CaseLibrary.read_source(again).get("title", ""))
	assert_true(first_title.ends_with("(копия)"))
	assert_true(second_title.ends_with("(копия 2)"))
	assert_true(editor.find_child("MethodOptions", true, false) != null)
	assert_true(editor.find_child("MotiveOptions", true, false) != null)
	var method := editor.find_child("methodText0", true, false) as LineEdit
	assert_eq(method.placeholder_text, "Кухонный нож из клуба")
	var help_row := (editor.find_child("ProfanityHelp", true, false) as Button).get_parent()
	assert_true(help_row is HBoxContainer)
	assert_true((editor.find_child("FillerHelp", true, false) as Button).get_parent() is HBoxContainer)
	assert_true((editor.find_child("RelationsHelp", true, false) as Button).get_parent() is HBoxContainer)
	assert_true(editor.find_child("CancelPublish", true, false) != null)
	var confirm := home.find_child("ConfirmBox", true, false) as Control
	assert_true(confirm.custom_minimum_size.x >= 420.0)
	editor.free()
	home.free()
	_restore_roots()


func test_starting_agent_moves_first_and_hidden_keys_survive() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var raw := CaseLibrary.read_source(CaseLibrary.example_id())
	var agents: Array = raw.get("agents", [])
	var last: Dictionary = agents[agents.size() - 1]
	raw["starting_agent_id"] = str(last.get("id", ""))
	var doc := CaseDocument.open(raw)
	assert_eq(str((doc.raw.get("agents", [])[0] as Dictionary).get("id", "")), str(last.get("id", "")))
	var exported := doc.export_raw()
	assert_eq(str(exported.get("starting_agent_id", "")), str(last.get("id", "")))
	assert_eq(_count(exported, "breaks_with"), _count(raw, "breaks_with"))
	assert_eq(_count(exported, "background"), _count(raw, "background"))
	assert_eq(_count(exported, "is_key"), _count(raw, "is_key"))
	assert_eq(_count(exported, "tags"), _count(raw, "tags"))
	_restore_roots()


func test_draft_does_not_change_hash_and_publish_warns() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var id := CaseLibrary.copy_case(CaseLibrary.example_id())
	var raw := CaseLibrary.read_source(id)
	assert_true(CaseLibrary.publish(id, raw, true).get("ok", false))
	var before := SaveState.file_hash(CaseLibrary.published_path(id))
	raw["title"] = "Черновая правка"
	assert_true(CaseLibrary.write_draft(id, raw))
	assert_eq(SaveState.file_hash(CaseLibrary.published_path(id)), before)
	var slot := SaveState.slot_path(id)
	var marker := FileAccess.open(slot, FileAccess.WRITE)
	marker.store_string("{}")
	marker.close()
	var blocked := CaseLibrary.publish(id, raw, false)
	assert_true(blocked.get("warn", false))
	assert_eq(SaveState.file_hash(CaseLibrary.published_path(id)), before)
	var done := CaseLibrary.publish(id, raw, true)
	assert_true(done.get("ok", false))
	assert_false(SaveState.exists(id))
	assert_false(SaveState.file_hash(CaseLibrary.published_path(id)) == before)
	_restore_roots()


func test_documents_copy_and_failure_notice() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var id := CaseLibrary.copy_case(CaseLibrary.example_id())
	var raw := CaseLibrary.read_source(id)
	CaseLibrary.documents_fail = "нет папки"
	var failed := CaseLibrary.publish(id, raw, true)
	assert_true(failed.get("ok", false))
	assert_true(str(failed.get("notice", "")).contains("Документы"))
	assert_true(FileAccess.file_exists(CaseLibrary.published_path(id)))
	CaseLibrary.documents_fail = ""
	CaseLibrary.documents_root = "user://editor-test/documents"
	var ok := CaseLibrary.publish(id, raw, true)
	assert_eq(str(ok.get("notice", "")), "")
	assert_true(FileAccess.file_exists("user://editor-test/documents/%s.json" % id))
	_restore_roots()


func test_secrets_do_not_land_in_case_files() -> void:
	_use_temp()
	var previous := _settings()
	SettingsStore.save_value("llm", "api_key", "MARKER-SECRET-VALUE")
	var raw := CaseLibrary.new_case()
	raw["api_key"] = "MARKER-SECRET-VALUE"
	raw["title"] = "MARKER-SECRET-VALUE"
	var id := str(raw.get("id", ""))
	assert_true(CaseLibrary.write_draft(id, raw))
	assert_true(CaseLibrary.publish(id, raw, true).get("ok", false))
	raw["briefing"] = "Вторая публикация"
	raw["secret"] = "MARKER-SECRET-VALUE"
	assert_true(CaseLibrary.publish(id, raw, true).get("ok", false))
	var state := GameState.new()
	state.case_id = id
	state.dialogues["agent_1"] = {"messages": [{"text": "MARKER-SECRET-VALUE"}]}
	assert_true(SaveState.write_state(state))
	for path in [
		CaseLibrary.draft_path(id),
		CaseLibrary.published_path(id),
		CaseLibrary.prev_path(id),
		"user://editor-test/documents/%s.json" % id,
		SaveState.slot_path(id),
	]:
		assert_true(FileAccess.file_exists(path), path)
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("MARKER-SECRET-VALUE"), path)
	SaveState.discard(id)
	_restore_settings(previous)
	_restore_roots()


func test_delete_and_restore_wait_for_confirmation() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var raw := CaseLibrary.new_case()
	var id := str(raw.get("id", ""))
	assert_true(CaseLibrary.write_draft(id, raw))
	var example := CaseLibrary.example_id()
	var slot := SaveState.slot_path(example)
	var had := FileAccess.file_exists(slot)
	var previous := FileAccess.get_file_as_bytes(slot) if had else PackedByteArray()
	DirAccess.make_dir_recursive_absolute(SaveState.DIR)
	var marker := FileAccess.open(slot, FileAccess.WRITE)
	marker.store_string("{}")
	marker.close()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var home := EditorHome.new()
	root.add_child(home)
	await (Engine.get_main_loop() as SceneTree).process_frame
	(home.find_child("Delete_%s" % id, true, false) as Button).pressed.emit()
	assert_true(FileAccess.file_exists(CaseLibrary.draft_path(id)))
	var dialog := home.find_child("ConfirmDialog", true, false) as Control
	assert_true(dialog.visible)
	assert_true(str((home.find_child("ConfirmText", true, false) as Label).text).contains("Удалить"))
	(home.find_child("ConfirmYes", true, false) as Button).pressed.emit()
	assert_false(FileAccess.file_exists(CaseLibrary.draft_path(id)))
	(home.find_child("RestoreExampleButton", true, false) as Button).pressed.emit()
	assert_true(FileAccess.file_exists(slot))
	assert_eq(str((home.find_child("ConfirmText", true, false) as Label).text), UiStrings.SAVE_RESET)
	(home.find_child("ConfirmYes", true, false) as Button).pressed.emit()
	assert_false(FileAccess.file_exists(slot))
	assert_eq(FileAccess.get_file_as_bytes(CaseLibrary.published_path(example)), FileAccess.get_file_as_bytes(CaseLibrary.BUILTIN))
	if had:
		var restore := FileAccess.open(slot, FileAccess.WRITE)
		restore.store_buffer(previous)
		restore.close()
	home.free()
	var picker := CasePicker.new()
	root.add_child(picker)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var start := picker.find_child("Start_%s" % example, true, false) as Button
	assert_eq(start.text, UiStrings.BEGIN)
	(picker.find_child("RestoreExampleButton", true, false) as Button).pressed.emit()
	assert_true((picker.find_child("ConfirmDialog", true, false) as Control).visible)
	picker.free()
	_restore_roots()


func test_pause_saves_the_draft_and_menu_continue_resets_voice() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var id := CaseLibrary.copy_case(CaseLibrary.example_id())
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var editor := CaseEditor.new()
	root.add_child(editor)
	editor.open_id(id)
	var title := editor.find_child("TitleEdit", true, false) as LineEdit
	title.text = "После паузы"
	title.focus_exited.emit()
	editor.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(FileAccess.get_file_as_string(CaseLibrary.draft_path(id)).contains("После паузы"))
	var method := editor.find_child("methodText0", true, false) as LineEdit
	method.text = "Кухонный нож"
	method.focus_exited.emit()
	editor.flush_autosave()
	var saved := CaseLibrary.read_source(id)
	assert_eq(str((saved.get("method_options", [])[0] as Dictionary).get("text", "")), "Кухонный нож")
	editor.free()
	Speaker.queue.enqueue("menu-continue", "текст")
	assert_false(Speaker.queue.pending.is_empty())
	var main := (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await (Engine.get_main_loop() as SceneTree).process_frame
	Speaker.queue.enqueue("menu-continue", "текст")
	main._on_continue()
	assert_true(Speaker.queue.pending.is_empty())
	assert_eq(Speaker.queue.current_id, "")
	main.free()
	_restore_roots()


func test_empty_case_list_offers_restore() -> void:
	_use_temp()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var picker := CasePicker.new()
	root.add_child(picker)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(picker.find_child("EmptyCases", true, false) != null)
	assert_true(picker.find_child("RestoreExampleButton", true, false) != null)
	picker.free()
	_restore_roots()


func test_undo_keeps_twenty_steps() -> void:
	var raw := {"id": "case_undo", "title": "Старт", "agents": [{"id": "agent_1", "name": "А"}]}
	var doc := CaseDocument.open(raw)
	for index in 20:
		doc.set_field("title", "Шаг %d" % index)
	for index in 20:
		assert_true(doc.undo())
	assert_eq(str(doc.raw.get("title", "")), "Старт")
	for index in 21:
		doc.set_field("title", "Дальше %d" % index)
	for index in 20:
		assert_true(doc.undo())
	assert_false(str(doc.raw.get("title", "")) == "Старт")


func test_autosave_writes_the_draft_only() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var id := CaseLibrary.copy_case(CaseLibrary.example_id())
	var raw := CaseLibrary.read_source(id)
	assert_true(CaseLibrary.publish(id, raw, true).get("ok", false))
	var before := FileAccess.get_file_as_bytes(CaseLibrary.published_path(id))
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var editor := CaseEditor.new()
	root.add_child(editor)
	editor.open_id(id)
	var title := editor.find_child("TitleEdit", true, false) as LineEdit
	title.text = "Автосохранено"
	title.focus_exited.emit()
	editor._timer.wait_time = 0.05
	editor._schedule()
	await (Engine.get_main_loop() as SceneTree).create_timer(0.2).timeout
	assert_true(FileAccess.get_file_as_string(CaseLibrary.draft_path(id)).contains("Автосохранено"))
	assert_eq(FileAccess.get_file_as_bytes(CaseLibrary.published_path(id)), before)
	editor.free()
	_restore_roots()


func test_back_shows_retry_when_the_draft_cannot_be_saved() -> void:
	_use_temp()
	CaseLibrary.ensure_example()
	var id := CaseLibrary.copy_case(CaseLibrary.example_id())
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var editor := CaseEditor.new()
	root.add_child(editor)
	editor.open_id(id)
	CaseLibrary.draft_fail = true
	assert_true(editor.consume_back())
	await (Engine.get_main_loop() as SceneTree).process_frame
	var failed := editor.find_child("SaveFailed", true, false) as Control
	var retry := editor.find_child("RetrySave", true, false) as Button
	var leave := editor.find_child("ExitWithoutSaving", true, false) as Button
	assert_true(failed.visible)
	assert_true(retry.visible)
	assert_true(leave.visible)
	assert_true(retry.size.y > 0.0)
	assert_true(leave.size.y > 0.0)
	assert_true(failed.get_global_rect().encloses(retry.get_global_rect()))
	assert_true(failed.get_global_rect().encloses(leave.get_global_rect()))
	assert_eq(str((editor.find_child("SaveFailedText", true, false) as Label).text), UiStrings.SAVE_FAILED)
	CaseLibrary.draft_fail = false
	var left := {"gone": false}
	editor.leave_pressed.connect(func() -> void: left["gone"] = true)
	(editor.find_child("RetrySave", true, false) as Button).pressed.emit()
	assert_true(left["gone"])
	editor.free()
	_restore_roots()


func test_character_card_saves_fillers_and_profanity() -> void:
	_use_temp()
	var raw := CaseLibrary.new_case()
	var id := str(raw.get("id", ""))
	assert_true(CaseLibrary.write_draft(id, raw))
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var editor := CaseEditor.new()
	root.add_child(editor)
	editor.open_id(id)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var filler := editor.find_child("Filler1", true, false) as LineEdit
	filler.text = "Эх…"
	filler.focus_exited.emit()
	var tone := editor.find_child("ProfanityChoice", true, false) as OptionButton
	tone.select(2)
	tone.item_selected.emit(2)
	assert_true(editor.flush_autosave())
	var saved := CaseLibrary.read_source(id)
	var agent: Dictionary = saved.get("agents", [])[0]
	assert_eq(str((agent.get("filler_lines", []) as Array)[0]), "Эх…")
	assert_eq(str(agent.get("profanity", "")), "often")
	var lines := FillerBank.lines_for(_agent_from(agent))
	assert_eq(lines[0], "Эх…")
	editor.keyboard_inset = 300
	editor._keep_visible(filler)
	var up := editor.find_child("AgentUp", true, false) as Button
	assert_true(up != null)
	editor.free()
	_restore_roots()


func _agent_from(agent: Dictionary) -> CaseData.Agent:
	var raw := {
		"id": "mini",
		"title": "Т",
		"briefing": "Б",
		"killer_id": "agent_1",
		"true_motive_id": "motive_1",
		"true_method_id": "method_1",
		"motive_options": [{"id": "motive_1", "text": "м"}],
		"method_options": [{"id": "method_1", "text": "с"}],
		"agents": [agent, CaseLibrary._blank_agent("agent_2")],
		"evidence": [],
		"contradictions": [],
	}
	(raw["agents"][1] as Dictionary)["name"] = "Б"
	(raw["agents"][0] as Dictionary)["name"] = "А"
	(raw["agents"][0] as Dictionary)["role"] = "роль"
	(raw["agents"][1] as Dictionary)["role"] = "роль"
	(raw["agents"][0] as Dictionary)["personality"] = "характер"
	(raw["agents"][1] as Dictionary)["personality"] = "характер"
	(raw["agents"][0] as Dictionary)["prompt_background"] = "предыстория"
	(raw["agents"][1] as Dictionary)["prompt_background"] = "предыстория"
	var loaded := CaseLoader.parse(raw)
	assert_true(loaded.ok, str(loaded.errors))
	return loaded.case_data.agents[0]


var _cases := ""
var _drafts := ""
var _docs := ""
var _fail := ""


func _use_temp() -> void:
	_cases = CaseLibrary.cases_root
	_drafts = CaseLibrary.drafts_root
	_docs = CaseLibrary.documents_root
	_fail = CaseLibrary.documents_fail
	CaseLibrary.cases_root = "user://editor-test/cases"
	CaseLibrary.drafts_root = "user://editor-test/drafts"
	CaseLibrary.documents_root = "user://editor-test/documents"
	CaseLibrary.documents_fail = ""
	CaseLibrary.draft_fail = false
	_wipe("user://editor-test")


func _restore_roots() -> void:
	CaseLibrary.cases_root = _cases if _cases != "" else "user://cases"
	CaseLibrary.drafts_root = _drafts if _drafts != "" else "user://case_drafts"
	CaseLibrary.documents_root = _docs
	CaseLibrary.documents_fail = _fail
	CaseLibrary.draft_fail = false


func _wipe(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var dir := DirAccess.open(abs)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := "%s/%s" % [path, name]
		if dir.current_is_dir():
			_wipe(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()


func _settings() -> String:
	var path := SettingsStore.PATH
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _restore_settings(previous: String) -> void:
	var path := SettingsStore.PATH
	if previous == "":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(previous)
		file.close()
	SettingsStore.invalidate_cache()


func _count(value: Variant, key: String) -> int:
	var count := 0
	if value is Dictionary:
		var body := value as Dictionary
		if body.has(key):
			count += 1
		for child in body.values():
			count += _count(child, key)
	elif value is Array:
		for child in value:
			count += _count(child, key)
	return count
