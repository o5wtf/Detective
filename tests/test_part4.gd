extends TestCase


func test_builtin_round_trip_keeps_the_game_and_only_adds_roman() -> void:
	var source: Dictionary = _read("res://cases/rain_over_shadow.json")
	var exported := CaseDocument.open(source).export_raw()
	assert_eq(_breaks(source), _breaks(exported))
	assert_eq(_forms(source), _forms(exported))
	var changed := []
	for evidence in exported.get("evidence", []):
		var evidence_id := str((evidence as Dictionary).get("id", ""))
		var before := _evidence(source, evidence_id)
		var facts_same: bool = before.get("related_fact_ids") == (evidence as Dictionary).get("related_fact_ids")
		var agents_same: bool = before.get("related_agent_ids") == (evidence as Dictionary).get("related_agent_ids")
		if not facts_same or not agents_same:
			changed.append(evidence_id)
	assert_eq(changed, ["ev_crime_scene"])
	assert_eq(( _evidence(exported, "ev_crime_scene").get("related_agent_ids") as Array), ["roman_petrov"])
	for code in ["arkady_kitchen", "mira_knife", "mira_return"]:
		assert_eq(str(_contradiction(exported, code).get("fact_b_form", "")), "truth")
	var parsed := CaseLoader.parse(exported)
	assert_true(parsed.ok)
	for tone in [0, 15]:
		var actual := SimHarness.run(parsed.case_data, tone)
		var golden: Dictionary = _read("res://tests/golden/rain_over_shadow_sim_%d.json" % tone)
		assert_eq(_sorted(actual["broken_lies"]), _sorted(golden["broken_lies"]))
		assert_eq(_sorted(actual["contradictions"]), _sorted(golden["contradictions"]))
		assert_eq(_sorted(actual["unlocked_evidence"]), _sorted(golden["unlocked_evidence"]))
		for fact_id in golden["fact_levels"]:
			assert_eq(str(actual["fact_levels"].get(fact_id, "")), str(golden["fact_levels"][fact_id]), fact_id)
		for agent_id in golden["pressure"]:
			var expected := int(golden["pressure"][agent_id])
			if str(agent_id) == "roman_petrov":
				expected += Balance.EVIDENCE_KEY
			assert_eq(int(actual["pressure"].get(agent_id, -1)), expected, str(agent_id))


func test_derivation_translates_fills_and_preserves_pressure() -> void:
	var raw := _base()
	var fact: Dictionary = (((raw.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	fact.erase("breaks_with")
	fact["breaks_lie_on"] = ["evidence", "pressure"]
	var doc := CaseDocument.open(raw)
	var opened: Dictionary = (((doc.raw.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	assert_true(opened.has("breaks_with"))
	var exported := doc.export_raw()
	var saved: Dictionary = (((exported.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	assert_eq(saved.get("breaks_lie_on"), ["evidence", "pressure"])
	saved["content_basic"] = ""
	saved["lie_type"] = "must_lie"
	var again := CaseDocument.open(exported)
	((((again.raw.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0] as Dictionary)["content_basic"] = ""
	var filled := again.export_raw()
	var body: Dictionary = (((filled.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	assert_eq(str(body.get("content_basic", "")), str(body.get("content_full", "")))
	var before_fill := again.raw
	var must_texts := _texts(EditorChecks.collect(before_fill))
	assert_false(must_texts.has("Пустая «Оговорка»"))
	var truth := _base()
	((((truth.get("agents") as Array)[1] as Dictionary).get("facts") as Array)[0] as Dictionary)["content_basic"] = ""
	var truth_out := CaseDocument.open(truth).export_raw()
	var truth_fact: Dictionary = (((truth_out.get("agents") as Array)[1] as Dictionary).get("facts") as Array)[0]
	assert_eq(str(truth_fact.get("content_basic", "")), str(truth_fact.get("content_full", "")))
	assert_false(EditorChecks.collect(truth).any(func(issue: Dictionary) -> bool: return str(issue.get("text", "")) == "Пусто «Что он расскажет»"))
	(((raw.get("agents") as Array)[0] as Dictionary) as Dictionary)["relationships"] = {"agent_2": "   ", "agent_1": ""}
	var links: Dictionary = (((CaseDocument.open(raw).export_raw().get("agents") as Array)[0] as Dictionary).get("relationships", {}))
	assert_false(links.has("agent_2"))
	assert_false(links.has("agent_1"))


func test_switch_and_contradiction_form_and_related_ids() -> void:
	var raw := _base()
	var doc := CaseDocument.open(raw)
	doc.set_fact_kind(0, 0, "cannot_lie")
	var fact: Dictionary = (((doc.raw.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	assert_eq(fact.get("is_lie"), false)
	assert_eq(str(fact.get("lie_type", "")), "cannot_lie")
	assert_false(fact.has("breaks_with"))
	doc.set_fact_kind(0, 0, "can_lie")
	fact = (((doc.raw.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	assert_eq(str(fact.get("lie_type", "")), "can_lie")
	doc.add_contradiction(str(fact.get("id", "")), "fact_truth", true, "Он сказал одно, она другое.")
	var row: Dictionary = (doc.raw.get("contradictions") as Array)[0]
	assert_eq(str(row.get("fact_b_form", "")), "truth_full")
	row["fact_b_form"] = "lie"
	var kept := doc.export_raw()
	assert_eq(str(((kept.get("contradictions") as Array)[0] as Dictionary).get("fact_b_form", "")), "lie")
	row["fact_b_form"] = "basic"
	var normalized := CaseDocument.open(doc.raw).export_raw()
	assert_eq(str(((normalized.get("contradictions") as Array)[0] as Dictionary).get("fact_b_form", "")), "truth")
	var evidence: Dictionary = (normalized.get("evidence") as Array)[0]
	assert_true((evidence.get("related_fact_ids") as Array).has("fact_lie"))


func test_cascade_removes_links_and_leaves_an_empty_condition() -> void:
	var raw := _base()
	(raw.get("evidence") as Array)[0]["unlock_condition"] = {"type": "lie_broken", "fact_id": "fact_lie"}
	var doc := CaseDocument.open(raw)
	assert_false(doc.usage_lines("fact", "fact_lie").is_empty())
	doc.remove_item("fact", "fact_lie")
	var evidence: Dictionary = (doc.raw.get("evidence") as Array)[0]
	assert_eq(evidence.get("unlock_condition"), {"AND": []})
	var texts := _texts(EditorChecks.collect(doc.raw))
	assert_true(texts.has("Улика осталась без условия"))
	doc.undo()
	evidence = (doc.raw.get("evidence") as Array)[0]
	assert_eq((evidence.get("unlock_condition") as Dictionary).get("fact_id"), "fact_lie")


func test_unsupported_condition_is_kept_and_a_real_block_round_trips() -> void:
	var raw := _base()
	(raw.get("evidence") as Array)[0]["unlock_condition"] = {"type": "pressure_on_agent", "agent_id": "agent_1", "min": 40}
	var issues: Array = EditorChecks.collect(raw)
	assert_true(_texts(issues).has("Неподдерживаемое условие"))
	assert_false(_texts(issues).has("Неподдерживаемое условие внутри «ИЛИ»"))
	var exported := CaseDocument.open(raw).export_raw()
	var kept: Dictionary = ((exported.get("evidence") as Array)[0] as Dictionary).get("unlock_condition", {})
	assert_eq(str(kept.get("type", "")), "pressure_on_agent")
	assert_eq(str(kept.get("agent_id", "")), "agent_1")
	assert_eq(int(kept.get("min", 0)), 40)
	raw = _base()
	(raw.get("evidence") as Array)[0]["unlock_condition"] = {"OR": [{"type": "pressure_on_agent", "agent_id": "agent_1"}, {"type": "dialogue_with", "agent_id": "agent_2"}]}
	assert_true(_texts(EditorChecks.collect(raw)).has("Неподдерживаемое условие внутри «ИЛИ»"))
	var doc := CaseDocument.open(_base())
	doc.set_unlock(0, {"type": "inconsistency_created", "contradiction_id": ""})
	doc.add_contradiction("fact_lie", "fact_truth", false, "Две версии одного вечера.")
	var contradiction_id := str(((doc.raw.get("contradictions") as Array)[0] as Dictionary).get("id", ""))
	doc.set_unlock(0, {"type": "inconsistency_created", "contradiction_id": contradiction_id})
	var saved := doc.export_raw()
	assert_true(CaseValidator.validate(saved).is_empty())
	assert_eq(((saved.get("evidence") as Array)[0] as Dictionary).get("unlock_condition"), {"type": "inconsistency_created", "contradiction_id": contradiction_id})
	raw = _base()
	(raw.get("evidence") as Array)[0]["unlock_condition"] = {"type": "inconsistency_created"}
	assert_true(_texts(EditorChecks.collect(raw)).has("Неподдерживаемое условие"))


func test_new_case_filled_through_fields_and_a_wide_case_validate() -> void:
	var doc := CaseDocument.open(CaseLibrary.new_case())
	doc.set_field("title", "Новое")
	doc.set_field("briefing", "Короткий брифинг.")
	doc.set_field("truth_timeline", "Вечером.")
	doc.set_field("killer_id", "agent_1")
	doc.set_field("method_options", [{"id": "method_1", "text": "Нож"}, {"id": "method_2", "text": "Яд"}])
	doc.set_field("motive_options", [{"id": "motive_1", "text": "Деньги"}, {"id": "motive_2", "text": "Месть"}])
	doc.set_agent_field(0, "name", "Ирина")
	doc.set_agent_field(0, "role", "Жена")
	doc.set_agent_field(0, "personality", "Говорит тихо.")
	doc.set_agent_field(0, "prompt_background", "Жена жертвы.")
	doc.set_agent_field(1, "name", "Павел")
	doc.set_agent_field(1, "role", "Бармен")
	doc.set_agent_field(1, "personality", "Говорит много.")
	doc.set_agent_field(1, "prompt_background", "Работает в клубе.")
	var lie := doc.add_fact(0)
	doc.set_fact_field(0, 0, "content_full", "Он должен деньги.")
	doc.set_fact_field(0, 0, "content_basic", "Был долг.")
	doc.set_fact_kind(0, 0, "must_lie")
	doc.set_fact_field(0, 0, "lie_text", "Долгов нет.")
	var evidence_id := doc.add_evidence()
	doc.set_evidence_field(0, "title", "Нож")
	doc.set_evidence_field(0, "type", "object")
	doc.set_evidence_field(0, "short_description", "Нож с кухни.")
	doc.set_evidence_field(0, "full_text", "На лезвии нет отпечатков.")
	doc.set_evidence_field(0, "related_agent_ids", ["agent_1"])
	doc.set_fact_field(0, 0, "related_evidence_ids", [evidence_id])
	doc.set_fact_field(0, 0, "breaks_with", [[{"type": "evidence_shown", "evidence_id": evidence_id}]])
	doc.add_fact(1)
	doc.set_fact_field(1, 0, "content_full", "Видел нож.")
	doc.set_fact_field(1, 0, "content_basic", "Видел нож.")
	var saved := doc.export_raw()
	assert_eq(lie, "fact_1")
	assert_true(CaseValidator.validate(saved).is_empty(), str(CaseValidator.validate(saved)))
	assert_true(CaseValidator.publish_errors(saved).is_empty())
	for index in 8:
		doc.add_agent()
		var at := index + 2
		doc.set_agent_field(at, "name", "Имя %d" % at)
		doc.set_agent_field(at, "role", "Роль")
		doc.set_agent_field(at, "personality", "Манера")
		doc.set_agent_field(at, "prompt_background", "Предыстория")
		doc.add_fact(at)
		doc.set_fact_field(at, 0, "content_full", "Показание")
		doc.set_fact_field(at, 0, "content_basic", "Показание")
	for index in 14:
		var created := doc.add_evidence()
		var slot := index + 1
		doc.set_evidence_field(slot, "title", "Улика %d" % slot)
		doc.set_evidence_field(slot, "type", "document")
		doc.set_evidence_field(slot, "short_description", "Подпись")
		doc.set_evidence_field(slot, "full_text", "Содержание")
		doc.set_evidence_field(slot, "related_agent_ids", ["agent_1"])
		assert_false(created == "")
	var wide := doc.export_raw()
	assert_eq((wide.get("agents") as Array).size(), 10)
	assert_eq((wide.get("evidence") as Array).size(), 15)
	assert_true(CaseValidator.validate(wide).is_empty(), str(CaseValidator.validate(wide)))


func test_cards_are_visible_help_is_inline_and_delete_can_be_cancelled() -> void:
	var editor := await _editor(_base())
	var tabs := editor.find_child("EditorTabs", true, false) as TabContainer
	tabs.current_tab = 1
	await _frame()
	var card := editor.find_child("Fact_fact_lie", true, false) as Control
	assert_true(card.is_visible_in_tree())
	assert_true(card.size.y > 0.0)
	var help := editor.find_child("FactsHelp", true, false) as Button
	assert_true(help.get_parent() is HBoxContainer)
	assert_true(help.is_visible_in_tree())
	tabs.current_tab = 2
	await _frame()
	var title := editor.find_child("EvTitle_ev_1", true, false) as Control
	assert_true(title.is_visible_in_tree())
	assert_true(title.size.y > 0.0)
	var title_help := editor.find_child("EvTitleHelp_ev_1", true, false) as Button
	assert_true(title_help.get_parent() is HBoxContainer)
	var remove := editor.find_child("FactDelete_fact_lie", true, false) as Button
	tabs.current_tab = 1
	await _frame()
	remove = editor.find_child("FactDelete_fact_lie", true, false) as Button
	remove.pressed.emit()
	var dialog := editor.find_child("DeleteConfirm", true, false) as Control
	var cancel := editor.find_child("CancelDelete", true, false) as Button
	assert_true(dialog.visible)
	assert_true(cancel.is_visible_in_tree())
	assert_true(cancel.size.y > 0.0)
	assert_eq(cancel.text, "Отмена")
	var box := editor.find_child("DeleteConfirmBox", true, false) as Control
	assert_true(box.custom_minimum_size.x >= 420.0)
	cancel.pressed.emit()
	assert_false(dialog.visible)
	editor.free()


func test_every_section_seven_rule_jumps_to_a_visible_field() -> void:
	for spec in _rules():
		var raw := _base()
		_apply(raw, str(spec["code"]))
		var text := str(spec["text"])
		var issue: Dictionary = {}
		for item in EditorChecks.collect(raw):
			if str((item as Dictionary).get("text", "")) == text:
				issue = item
				break
		assert_false(issue.is_empty(), text)
		var editor := await _editor(raw)
		editor.goto_issue(issue)
		await _frame()
		var node_name := str((issue.get("target", {}) as Dictionary).get("node", ""))
		var node := editor.find_child(node_name, true, false) as Control
		assert_true(node != null, "%s -> %s" % [text, node_name])
		if node == null:
			editor.free()
			continue
		assert_true(node.is_visible_in_tree(), text)
		assert_true(node.size.y > 0.0, text)
		if str(issue.get("level", "")) == "warning":
			var warnings := editor.find_child("WarningsBody", true, false) as Control
			if warnings != null:
				warnings.visible = true
				await _frame()
		var jump := editor.find_child("GotoIssue", true, false) as Button
		assert_true(jump != null and jump.is_visible_in_tree(), text)
		editor.free()


func _editor(raw: Dictionary) -> CaseEditor:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var editor := CaseEditor.new()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.custom_minimum_size = Vector2(1280, 800)
	root.add_child(editor)
	editor._doc = CaseDocument.open(raw)
	editor._read_only = false
	editor.case_id = str(raw.get("id", ""))
	editor._build()
	await _frame()
	return editor


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _rules() -> Array:
	return [
		{"code": "title", "text": "Нет названия"},
		{"code": "briefing", "text": "Нет брифинга"},
		{"code": "no_agents", "text": "Нет персонажей"},
		{"code": "no_method", "text": "Нет вариантов способа"},
		{"code": "no_motive", "text": "Нет вариантов мотива"},
		{"code": "one_agent", "text": "Меньше 2 персонажей"},
		{"code": "killer", "text": "Убийца не выбран"},
		{"code": "true_method", "text": "Не отмечен верный способ"},
		{"code": "true_motive", "text": "Не отмечен верный мотив"},
		{"code": "name", "text": "Пусто имя"},
		{"code": "role", "text": "Пусто роль"},
		{"code": "personality", "text": "Пусто характер"},
		{"code": "background", "text": "Пусто предыстория"},
		{"code": "emotion", "text": "Эмоция не из списка"},
		{"code": "gender", "text": "Неверный пол"},
		{"code": "voice", "text": "Неверное имя голоса"},
		{"code": "profanity", "text": "Неверное значение «Ругается»"},
		{"code": "relationship", "text": "В отношениях удалённый персонаж или он сам"},
		{"code": "full", "text": "Пусто «Что он расскажет»"},
		{"code": "hedge", "text": "Пустая «Оговорка»"},
		{"code": "requires", "text": "«Полностью — только после показа улики» включено без связанных улик"},
		{"code": "lie_text", "text": "У лжи пустой текст лжи"},
		{"code": "truth_lie", "text": "У правды заполнен текст лжи"},
		{"code": "missing_prior", "text": "Ссылка на удалённое показание в «Только после того, как сломана ложь…»"},
		{"code": "missing_break", "text": "В наборе удалённая улика или показание"},
		{"code": "self_retell", "text": "Пересказ своего показания"},
		{"code": "empty_set", "text": "Пустой набор"},
		{"code": "bad_item", "text": "Неизвестный вид пункта"},
		{"code": "must_sets", "text": "У «Всегда врёт» нет ни одного набора"},
		{"code": "unreachable", "text": "Ни один набор не собрать"},
		{"code": "missing_side", "text": "Противоречие ссылается на удалённое показание"},
		{"code": "lie_form", "text": "Форма «Ложь» у правды"},
		{"code": "same_side", "text": "Обе стороны противоречия одинаковы"},
		{"code": "no_note", "text": "Нет текста для блокнота"},
		{"code": "ev_title", "text": "У улики пусто название"},
		{"code": "ev_type", "text": "У улики пусто тип"},
		{"code": "ev_short", "text": "У улики пусто подпись"},
		{"code": "ev_full", "text": "У улики пусто содержание"},
		{"code": "ev_person", "text": "Улика ссылается на удалённого персонажа или показание"},
		{"code": "cond_missing", "text": "Условие ссылается на удалённое"},
		{"code": "self_evidence", "text": "Улика ждёт показа самой себя"},
		{"code": "empty_group", "text": "Пустая группа «И»/«ИЛИ»"},
		{"code": "unsupported", "text": "Неподдерживаемое условие"},
		{"code": "bad_contradiction", "text": "«После найденного противоречия» с удалённым противоречием"},
		{"code": "lost_condition", "text": "Улика осталась без условия"},
		{"code": "lost_lie", "text": "Показание лишилось условия “после сломанной лжи”"},
		{"code": "dup_id", "text": "Повторяющийся или пустой id"},
		{"code": "can_sets", "text": "«Может соврать» без наборов «Чем можно сломать»"},
		{"code": "unused_evidence", "text": "Связанная улика лжи не входит ни в один набор"},
		{"code": "hedge_same", "text": "«Оговорка» совпадает с «Что он расскажет»"},
		{"code": "partial_same", "text": "«Неполное признание» пустое или совпадает с «Что он расскажет»"},
		{"code": "same_person", "text": "Противоречие между показаниями одного персонажа"},
		{"code": "or_unsupported", "text": "Неподдерживаемое условие внутри «ИЛИ»"},
		{"code": "timeline", "text": "Пустое «Как всё было»"},
		{"code": "no_facts", "text": "Персонаж без показаний"},
		{"code": "lonely_evidence", "text": "Улика без «Касается персонажей» и без связанных показаний"},
		{"code": "one_option", "text": "У способа или мотива только один вариант"},
		{"code": "no_evidence", "text": "В деле нет улик"},
		{"code": "no_breaks", "text": "Ни у одной лжи нет наборов «Чем можно сломать»"},
		{"code": "killer_lie", "text": "У убийцы нет ни одной лжи"},
		{"code": "digits", "text": "В полях «Живого персонажа» есть время или числа"},
	]


func _apply(raw: Dictionary, code: String) -> void:
	var lie: Dictionary = (((raw.get("agents") as Array)[0] as Dictionary).get("facts") as Array)[0]
	var truth: Dictionary = (((raw.get("agents") as Array)[1] as Dictionary).get("facts") as Array)[0]
	var evidence: Dictionary = (raw.get("evidence") as Array)[0]
	var who: Dictionary = (raw.get("agents") as Array)[0]
	match code:
		"title":
			raw["title"] = ""
		"briefing":
			raw["briefing"] = ""
		"no_agents":
			raw["agents"] = []
		"no_method":
			raw["method_options"] = []
		"no_motive":
			raw["motive_options"] = []
		"one_agent":
			(raw.get("agents") as Array).pop_back()
		"killer":
			raw["killer_id"] = ""
		"true_method":
			raw["true_method_id"] = "missing"
		"true_motive":
			raw["true_motive_id"] = "missing"
		"name":
			who["name"] = ""
		"role":
			who["role"] = ""
		"personality":
			who["personality"] = ""
		"background":
			who["prompt_background"] = ""
		"emotion":
			who["starting_emotion"] = "joyful"
		"gender":
			who["gender"] = "other"
		"voice":
			who["tts_voice"] = "NotAVoice"
		"profanity":
			who["profanity"] = "oftenly"
		"relationship":
			who["relationships"] = {"agent_1": "сам"}
		"full":
			lie["content_full"] = ""
		"hedge":
			lie["lie_type"] = "can_lie"
			lie["content_basic"] = ""
		"requires":
			lie["requires_evidence"] = true
			lie["related_evidence_ids"] = []
		"lie_text":
			lie["lie_text"] = ""
		"truth_lie":
			truth["lie_text"] = "Это не ложь."
		"missing_prior":
			lie["requires_broken_lies"] = ["fact_missing"]
		"missing_break":
			lie["breaks_with"] = [[{"type": "evidence_shown", "evidence_id": "ev_missing"}]]
		"self_retell":
			lie["breaks_with"] = [[{"type": "testimony_retold", "fact_id": "fact_lie"}]]
		"empty_set":
			lie["breaks_with"] = [[]]
		"bad_item":
			lie["breaks_with"] = [[{"type": "nope"}]]
		"must_sets":
			lie["breaks_with"] = []
		"unreachable":
			lie["breaks_with"] = [[{"type": "testimony_retold", "fact_id": "fact_other", "form": "truth_full"}]]
			truth["is_lie"] = true
			truth["lie_type"] = "must_lie"
			truth["lie_text"] = "Не видел."
			truth["breaks_with"] = [[{"type": "testimony_retold", "fact_id": "fact_lie", "form": "truth_full"}]]
		"missing_side":
			raw["contradictions"] = [{"id": "con_1", "fact_a_id": "fact_lie", "fact_a_form": "lie", "fact_b_id": "fact_missing", "fact_b_form": "truth", "description": "Текст"}]
		"lie_form":
			raw["contradictions"] = [{"id": "con_1", "fact_a_id": "fact_truth", "fact_a_form": "lie", "fact_b_id": "fact_lie", "fact_b_form": "truth", "description": "Текст"}]
		"same_side":
			raw["contradictions"] = [{"id": "con_1", "fact_a_id": "fact_lie", "fact_a_form": "lie", "fact_b_id": "fact_lie", "fact_b_form": "lie", "description": "Текст"}]
		"no_note":
			raw["contradictions"] = [{"id": "con_1", "fact_a_id": "fact_lie", "fact_a_form": "lie", "fact_b_id": "fact_truth", "fact_b_form": "truth", "description": ""}]
		"ev_title":
			evidence["title"] = ""
		"ev_type":
			evidence["type"] = ""
		"ev_short":
			evidence["short_description"] = ""
		"ev_full":
			evidence["full_text"] = ""
		"ev_person":
			evidence["related_agent_ids"] = ["agent_missing"]
		"cond_missing":
			evidence["unlock_condition"] = {"type": "dialogue_with", "agent_id": "agent_missing"}
		"self_evidence":
			evidence["unlock_condition"] = {"type": "evidence_shown", "evidence_id": "ev_1"}
		"empty_group":
			evidence["unlock_condition"] = {"AND": []}
		"unsupported":
			evidence["unlock_condition"] = {"type": "pressure_on_agent", "agent_id": "agent_1"}
		"bad_contradiction":
			evidence["unlock_condition"] = {"type": "inconsistency_created", "contradiction_id": "con_missing"}
		"lost_condition":
			evidence["unlock_condition"] = {"OR": []}
		"lost_lie":
			lie["requires_broken_lies"] = [""]
		"dup_id":
			truth["id"] = "fact_lie"
		"can_sets":
			lie["lie_type"] = "can_lie"
			lie["breaks_with"] = []
			lie["content_basic"] = "Оговорка короче."
		"unused_evidence":
			lie["breaks_with"] = [[{"type": "testimony_retold", "fact_id": "fact_truth"}]]
		"hedge_same":
			lie["lie_type"] = "can_lie"
			lie["content_basic"] = str(lie.get("content_full", ""))
		"partial_same":
			lie["requires_evidence"] = true
			lie["content_basic"] = str(lie.get("content_full", ""))
		"same_person":
			raw["contradictions"] = [{"id": "con_1", "fact_a_id": "fact_lie", "fact_a_form": "lie", "fact_b_id": "fact_lie", "fact_b_form": "truth", "description": "Сам себе"}]
		"or_unsupported":
			evidence["unlock_condition"] = {"OR": [{"type": "pressure_on_agent", "agent_id": "agent_1"}, {"type": "dialogue_with", "agent_id": "agent_2"}]}
		"timeline":
			raw["truth_timeline"] = ""
		"no_facts":
			who["facts"] = []
		"lonely_evidence":
			evidence["related_agent_ids"] = []
			lie["related_evidence_ids"] = []
			lie["breaks_with"] = [[{"type": "testimony_retold", "fact_id": "fact_truth"}]]
		"one_option":
			raw["method_options"] = [{"id": "method_1", "text": "Нож"}]
		"no_evidence":
			raw["evidence"] = []
			lie["breaks_with"] = []
			lie["is_lie"] = false
			lie["lie_type"] = "cannot_lie"
		"no_breaks":
			lie["is_lie"] = false
			lie["lie_type"] = "cannot_lie"
			lie["breaks_with"] = []
			lie["lie_text"] = ""
		"killer_lie":
			raw["killer_id"] = "agent_2"
		"digits":
			who["wants"] = "Уйти в 01:10"


func _base() -> Dictionary:
	return {
		"id": "case_rules",
		"title": "Дело",
		"briefing": "Ночь в клубе.",
		"truth_timeline": "Ночью.",
		"killer_id": "agent_1",
		"victory_condition": "correct_accusation",
		"intro_atmosphere": "",
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


func _texts(issues: Array) -> Dictionary:
	var found := {}
	for issue in issues:
		found[str((issue as Dictionary).get("text", ""))] = true
	return found


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed


func _breaks(raw: Dictionary) -> Dictionary:
	var found := {}
	for agent in raw.get("agents", []):
		for fact in (agent as Dictionary).get("facts", []):
			if (fact as Dictionary).get("is_lie", false) == true:
				found[str((fact as Dictionary).get("id", ""))] = (fact as Dictionary).get("breaks_lie_on")
	return found


func _forms(raw: Dictionary) -> Dictionary:
	var found := {}
	for row in raw.get("contradictions", []):
		found[str((row as Dictionary).get("id", ""))] = str((row as Dictionary).get("fact_b_form", ""))
	return found


func _evidence(raw: Dictionary, evidence_id: String) -> Dictionary:
	for evidence in raw.get("evidence", []):
		if str((evidence as Dictionary).get("id", "")) == evidence_id:
			return evidence
	return {}


func _contradiction(raw: Dictionary, contradiction_id: String) -> Dictionary:
	for row in raw.get("contradictions", []):
		if str((row as Dictionary).get("id", "")) == contradiction_id:
			return row
	return {}


func _sorted(value: Variant) -> Array:
	var copy: Array = value
	copy = copy.duplicate()
	copy.sort()
	return copy
