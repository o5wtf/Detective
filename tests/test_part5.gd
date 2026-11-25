extends TestCase


const FIXTURE := "res://tests/fixtures/turn_flow.json"


func test_sandbox_leaves_the_game_the_save_and_the_key_alone() -> void:
	assert_true(Game.open_case(FIXTURE).ok)
	assert_true(SaveState.write_state(Game.state))
	var slot := SaveState.slot_path(Game.state.case_id)
	var before_bytes := FileAccess.get_file_as_bytes(slot)
	var before_state := Game.state.to_dict()
	var token := Game._turn_token
	var previous := _settings()
	SettingsStore.save_value("llm", "api_key", "sandbox-key-marker")
	SettingsStore.save_value("llm", "provider", "mock")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var sandbox := Sandbox.new()
	root.add_child(sandbox)
	assert_true(sandbox.open_draft(raw))
	assert_eq(sandbox.state.turn, 0)
	assert_true(sandbox.state.broken_lies.is_empty())
	assert_true(sandbox.state.talked_to.is_empty())
	assert_false(sandbox.state == Game.state)
	assert_false(sandbox.case_data == Game.case_data)
	var mock := MockLLMClient.new()
	LLM.add_child(mock)
	var old_client: Variant = LLM.client
	LLM.client = mock
	mock.enqueue(_reply("Я держусь своей версии."))
	await sandbox.ask("a", "Где вы были?")
	assert_eq(Game._turn_token, token)
	assert_false(Game.is_busy)
	assert_eq(Game.state.to_dict(), before_state)
	assert_eq(FileAccess.get_file_as_bytes(slot), before_bytes)
	assert_eq(sandbox.state.turn, 1)
	assert_false(sandbox.is_busy)
	var blob := "\n".join(sandbox.log_lines)
	assert_false(blob.contains("sandbox-key-marker"))
	assert_false(JSON.stringify(sandbox.state.to_dict()).contains("sandbox-key-marker"))
	if is_instance_valid(old_client):
		LLM.client = old_client
	else:
		LLM.client = null
	mock.free()
	sandbox.free()
	_restore_settings(previous)


func test_ask_warning_has_cancel_and_warnings_start_collapsed() -> void:
	var editor := await _editor(_draft())
	var ask := editor.find_child("AskCharacter", true, false) as Button
	assert_true(ask.is_visible_in_tree())
	assert_true(ask.size.y > 0.0)
	ask.pressed.emit()
	var warn := editor.find_child("SpendWarn", true, false) as Control
	var cancel := editor.find_child("CancelAsk", true, false) as Button
	var text := editor.find_child("SpendText", true, false) as Label
	assert_true(warn.visible)
	assert_true(cancel.is_visible_in_tree())
	assert_true(cancel.size.y > 0.0)
	assert_eq(cancel.text, "Отмена")
	assert_true(text.text.contains("лимит API"))
	cancel.pressed.emit()
	assert_false(warn.visible)
	var toggle := editor.find_child("ToggleWarnings", true, false) as Button
	var body := editor.find_child("WarningsBody", true, false) as Control
	assert_true(toggle.is_visible_in_tree())
	assert_false(body.visible)
	toggle.pressed.emit()
	await _frame()
	assert_true(body.visible)
	assert_true(body.size.y > 0.0)
	editor.free()
	var copy := await _editor(_read("res://cases/rain_over_shadow.json"))
	var copy_body := copy.find_child("WarningsBody", true, false) as Control
	if copy_body != null:
		assert_false(copy_body.visible)
		var copy_toggle := copy.find_child("ToggleWarnings", true, false) as Button
		assert_true(copy_toggle.is_visible_in_tree())
	copy.free()


func test_break_titles_ellipsis_topic_help_and_usage_plural() -> void:
	var raw := _draft()
	var lie: Dictionary = (((raw.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	var truth: Dictionary = (((raw.get("agents") as Array)[1] as Dictionary).get("facts") as Array)[0]
	var long := "Павел видел, как Аркадий заходил на кухню и долго стоял у ящика с ножами, а потом вышел без лимона."
	truth["content_full"] = long
	lie["breaks_with"] = [[{"type": "testimony_retold", "fact_id": "fact_truth"}]]
	(raw.get("evidence") as Array)[0]["unlock_condition"] = {
		"type": "evidence_mentioned",
		"agent_id": "agent_1",
		"evidence_id": "ev_1",
		"topic": "кто входил",
	}
	var editor := await _editor(raw)
	var tabs := editor.find_child("EditorTabs", true, false) as TabContainer
	tabs.current_tab = 1
	await _frame()
	var target := editor.find_child("BreakTarget_0_0_0", true, false) as OptionButton
	assert_true(target != null, "нет списка набора")
	var shown := target.get_item_text(target.selected)
	assert_true(shown.ends_with("…"), shown)
	assert_true(target.tooltip_text.contains("ящика с ножами"))
	var full := editor.find_child("BreakFull_0_0_0", true, false) as Label
	assert_true(full.text.contains("ящика с ножами"))
	assert_false(full.text.ends_with("…"))
	tabs.current_tab = 2
	await _frame()
	var help := editor.find_child("MentionHelp_ev_1", true, false) as Button
	assert_true(help.get_parent() is HBoxContainer)
	assert_true(help.is_visible_in_tree())
	editor.free()
	var doc := CaseDocument.open(raw)
	doc.set_unlock(0, {"type": "lie_broken", "fact_id": "fact_lie"})
	var phrase_host := CaseEditor.new()
	var one := doc.usage_lines("fact", "fact_lie")
	assert_eq(one.size(), 1)
	assert_eq(phrase_host._places_phrase(one.size()), "Используется в 1 месте")
	assert_eq(phrase_host._places_phrase(2), "Используется в 2 местах")
	assert_eq(phrase_host._places_phrase(5), "Используется в 5 местах")
	assert_eq(phrase_host._places_phrase(21), "Используется в 21 месте")
	doc.set_fact_field(1, 0, "requires_broken_lies", ["fact_lie"])
	var two := doc.usage_lines("fact", "fact_lie")
	assert_true(two.size() >= 2)
	assert_eq(phrase_host._places_phrase(two.size()), "Используется в %d местах" % two.size())


func _editor(raw: Dictionary) -> CaseEditor:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var editor := CaseEditor.new()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.custom_minimum_size = Vector2(1280, 800)
	root.add_child(editor)
	editor._doc = CaseDocument.open(raw)
	editor._read_only = false
	editor.case_id = str(raw.get("id", "case_rules"))
	editor._build()
	await _frame()
	return editor


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _draft() -> Dictionary:
	return {
		"id": "case_rules",
		"title": "Дело",
		"briefing": "Ночь в клубе.",
		"truth_timeline": "",
		"killer_id": "agent_1",
		"victory_condition": "correct_accusation",
		"motive_options": [{"id": "motive_1", "text": "Деньги"}, {"id": "motive_2", "text": "Месть"}],
		"true_motive_id": "motive_1",
		"method_options": [{"id": "method_1", "text": "Нож"}, {"id": "method_2", "text": "Яд"}],
		"true_method_id": "method_1",
		"agents": [
			{
				"id": "agent_1", "name": "Ирина", "role": "Жена", "gender": "", "tts_voice": "",
				"personality": "Говорит тихо.", "prompt_background": "Жена жертвы.",
				"starting_emotion": "neutral", "profanity": "never", "relationships": {},
				"facts": [{
					"id": "fact_lie", "content_full": "Он должен крупную сумму.", "content_basic": "Был долг.",
					"is_lie": true, "lie_type": "must_lie", "lie_text": "Долгов нет.",
					"related_evidence_ids": ["ev_1"], "requires_evidence": false,
					"breaks_lie_on": "evidence",
					"breaks_with": [[{"type": "evidence_shown", "evidence_id": "ev_1"}]],
				}],
			},
			{
				"id": "agent_2", "name": "Павел", "role": "Бармен", "gender": "", "tts_voice": "",
				"personality": "Говорит много.", "prompt_background": "Работает в клубе.",
				"starting_emotion": "neutral", "profanity": "never", "relationships": {},
				"facts": [{
					"id": "fact_truth", "content_full": "Видел нож на кухне.", "content_basic": "Видел нож.",
					"is_lie": false, "lie_type": "cannot_lie", "lie_text": "",
					"related_evidence_ids": [], "requires_evidence": false, "breaks_lie_on": null,
				}],
			},
		],
		"evidence": [{
			"id": "ev_1", "title": "Нож", "type": "object",
			"short_description": "Нож с кухни.", "full_text": "На лезвии нет отпечатков.",
			"related_fact_ids": ["fact_lie"], "related_agent_ids": ["agent_1"],
			"is_key": false, "unlock_condition": null,
		}],
		"contradictions": [],
	}


func _reply(text: String) -> Dictionary:
	return {
		"ok": true,
		"json": {
			"player_tone": 0,
			"reply": text,
			"remark": "",
			"emotion": "neutral",
			"stated": [{"key": "k1", "form": "lie"}],
			"mentioned_evidence": [],
			"requested_evidence": null,
		},
		"raw_text": "",
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
	}


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


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
