extends TestCase


func test_lite_reply_types_are_coerced() -> void:
	var body := _body([])
	body["player_tone"] = "2"
	body["emotion"] = "Neutral"
	body.erase("requested_evidence")
	body.erase("mentioned_evidence")
	var report := ResponseValidator.validate(body, [_basic()], _context())
	assert_true(report["ok"])
	assert_eq(report["tone"], 2)
	assert_eq(report["emotion"], "neutral")


func test_speech_tone_is_separate_from_the_reply() -> void:
	var known := _body([])
	known["tone"] = "Саркастично"
	var report := ResponseValidator.validate(known, [_basic()], _context())
	assert_true(report["ok"])
	assert_eq(report["speech_tone"], "саркастично")
	assert_eq(report["reply"], "Короткий спокойный ответ.")
	assert_false(str(report["reply"]).contains("саркастично"))
	var unknown := _body([])
	unknown["tone"] = "яростно"
	var dropped := ResponseValidator.validate(unknown, [_basic()], _context())
	assert_true(dropped["ok"])
	assert_eq(dropped["speech_tone"], "")
	assert_eq(VoiceTone.for_speech("нервно", false), "")
	assert_eq(VoiceTone.for_speech("нервно", true), "нервно")
	assert_eq(VoiceTone.normalize("раздраженно"), "раздражённо")
	var styled := GeminiTtsBackend.build_request("Я был дома.", "Kore", VoiceTone.for_speech("нервно", true))
	assert_eq(styled["contents"][0]["parts"][0]["text"], "Я был дома.")
	assert_eq(styled["contents"][0]["parts"][0]["speechMetadata"]["style"], "нервно")
	var plain := GeminiTtsBackend.build_request("Я был дома.", "Kore", VoiceTone.for_speech("яростно", true))
	assert_false(plain["contents"][0]["parts"][0].has("speechMetadata"))


func test_vocal_tags_and_optional_pace_do_not_enter_the_reply() -> void:
	var body := _body([], "Я был дома. <sigh> Правда. <laugh> И <gasp> ещё. <whisper>")
	body["tone"] = "нервно"
	body["pace"] = "fast"
	var report := ResponseValidator.validate(body, [_basic()], _context())
	assert_true(report["ok"])
	assert_eq(report["reply"], "Я был дома. Правда. И ещё.")
	assert_eq(report["spoken_reply"], "Я был дома. <sigh> Правда. <laugh> И ещё.")
	assert_false(str(report["reply"]).contains("<"))
	assert_eq(report["speech_tone"], "нервно")
	assert_eq(report["pace"], "fast")
	var legacy := _body([])
	legacy.erase("tone")
	var old := ResponseValidator.validate(legacy, [_basic()], _context())
	assert_true(old["ok"])
	assert_eq(old["pace"], "")
	assert_eq(old["reply"], "Короткий спокойный ответ.")


func test_format_requires_fields() -> void:
	var report := ResponseValidator.validate({"reply": "Есть только реплика."}, [_basic()], _context())
	assert_true(report["ok"])
	assert_eq(report["reply"], "Есть только реплика.")


func test_stated_forms_follow_packet_mode() -> void:
	var lie := ResponseValidator.validate(_body([{"key": "k1", "form": "basic"}]), [_lie()], _context())
	assert_true(lie["ok"])
	assert_eq(lie["statements"][0]["form"], "lie")
	assert_true(",".join(lie["fixes"]).contains("basic->lie"))
	var both := ResponseValidator.validate(_body([
		{"key": "k1", "form": "basic"},
		{"key": "k1", "form": "full"},
		{"key": "none", "form": "full"},
		{"key": "k9", "form": "full"},
	]), [_full()], _context())
	assert_true(both["ok"])
	assert_eq(both["statements"].size(), 1)
	assert_eq(both["statements"][0]["fact_id"], "visible")
	assert_eq(both["statements"][0]["form"], "basic")
	var slip := ResponseValidator.validate(_body([{"key": "k1", "form": "basic"}]), [_slip()], _context())
	assert_true(slip["ok"])
	assert_eq(slip["statements"][0]["form"], "basic")


func test_service_words_are_violations() -> void:
	for word in ["нейросеть", "языковая модель", "промпт", "ИИ", "ключ k1", "улика e2"]:
		var report := ResponseValidator.validate(_body([], word), [_basic()], _context())
		assert_false(report["ok"], word)


func test_markup_is_removed_without_violation() -> void:
	var report := ResponseValidator.validate(_body([], "*Здравствуйте.*\n- Лишняя строка"), [_basic()], _context())
	assert_true(report["ok"])
	assert_false(str(report["reply"]).contains("*"))
	assert_false(str(report["reply"]).begins_with("-"))


func test_leak_number_and_stems() -> void:
	var packet := [_basic()]
	var context := _context()
	context["case_data"] = _leak_case()
	context["agent_id"] = "a"
	var number := ResponseValidator.validate(_body([], "Это было в 19:00."), packet, context)
	assert_false(number["ok"])
	assert_true(_has_violation(number, "возможная утечка"))
	var stems := ResponseValidator.validate(_body([], "Он открыл хранилище и сразу признался."), packet, context)
	assert_false(stems["ok"])
	var one := ResponseValidator.validate(_body([], "Он только открыл хранилище."), packet, context)
	assert_true(one["ok"])
	assert_true(FileAccess.file_exists("user://logs/leaks.log"))


func test_living_fields_count_as_allowed_source() -> void:
	var packet := [_basic()]
	var context := _context()
	var data := _leak_case()
	var agent: CaseData.Agent = data.agent_by_id["a"]
	agent.wants = "Он открыл хранилище и сразу признался."
	context["case_data"] = data
	context["agent_id"] = "a"
	var report := ResponseValidator.validate(_body([], "Он открыл хранилище и сразу признался."), packet, context)
	assert_true(report["ok"], ",".join(report["violations"]))


func test_auto_add_when_reply_names_one_packet_number() -> void:
	var entry := _basic()
	entry["content"] = "Встреча назначена на 19:00."
	var report := ResponseValidator.validate(_body([], "Я пришёл в 19:00."), [entry], _context())
	assert_true(report["ok"])
	assert_eq(report["statements"].size(), 1)
	assert_eq(report["statements"][0]["fact_id"], "visible")
	assert_eq(report["statements"][0]["form"], "basic")


func test_tone_is_clamped_and_emotion_falls_back() -> void:
	var high := ResponseValidator.validate(_body([], "Спокойный ответ.", 8, "neutral"), [_basic()], _context())
	assert_true(high["ok"])
	assert_eq(high["tone"], 5)
	var low := ResponseValidator.validate(_body([], "Спокойный ответ.", -9, "neutral"), [_basic()], _context())
	assert_eq(low["tone"], -3)
	var context := _context()
	context["previous_emotion"] = "nervous"
	var emotion := ResponseValidator.validate(_body([], "Спокойный ответ.", 0, "joyful"), [_basic()], context)
	assert_true(emotion["ok"])
	assert_eq(emotion["emotion"], "nervous")
	var dropped := ResponseValidator.validate(_body_with_evidence(), [_basic()], context)
	assert_eq(dropped["mentioned_evidence"], ["e1"])
	assert_eq(dropped["requested_evidence"], "")


func test_extra_sentences_are_trimmed_locally() -> void:
	var reply := "Первое. Второе. Третье. Четвёртое. Пятое."
	var report := ResponseValidator.validate(_body([], reply), [_basic()], _context())
	assert_true(report["ok"])
	assert_false(str(report["reply"]).contains("Пятое"))
	assert_true(",".join(report["fixes"]).contains("sentences"))


func _body(stated: Array, reply: String = "Короткий спокойный ответ.", tone: int = 0, emotion: String = "neutral") -> Dictionary:
	return {
		"player_tone": tone,
		"reply": reply,
		"remark": "кивает",
		"emotion": emotion,
		"stated": stated,
		"mentioned_evidence": [],
		"requested_evidence": null,
	}


func _body_with_evidence() -> Dictionary:
	var body := _body([])
	body["mentioned_evidence"] = ["e1", "e9", "none"]
	body["requested_evidence"] = "e9"
	return body


func _context() -> Dictionary:
	return {
		"previous_emotion": "neutral",
		"leak_max_stems": 1,
		"log_leaks": true,
		"player_text": "Что скажете?",
		"evidence_keys": ["e1"],
	}


func _basic() -> Dictionary:
	return {"key": "k1", "fact_id": "visible", "mode": "basic", "lie_text": "", "content": "Краткая версия без чисел."}


func _full() -> Dictionary:
	return {"key": "k1", "fact_id": "visible", "mode": "full", "lie_text": "", "content": "Полная версия без чисел."}


func _lie() -> Dictionary:
	return {"key": "k1", "fact_id": "hidden", "mode": "lie", "lie_text": "Меня там не было.", "content": "Меня там не было."}


func _slip() -> Dictionary:
	return {
		"key": "k1",
		"fact_id": "slip",
		"mode": "lie_or_basic",
		"lie_text": "Никого не видел.",
		"content": "Кажется, кто-то проходил.",
	}


func _leak_case() -> CaseData:
	var data := CaseData.new()
	var agent := CaseData.Agent.new()
	agent.id = "a"
	agent.prompt_background = "Живёт рядом."
	agent.personality = "Говорит коротко."
	var closed := CaseData.Fact.new()
	closed.id = "secret"
	closed.content_basic = "Краткая закрытая версия."
	closed.content_full = "В хранилище он признался ровно в 19:00."
	agent.facts.append(closed)
	data.agents.append(agent)
	data.agent_by_id["a"] = agent
	data.fact_by_id["secret"] = closed
	data.briefing = "Короткий брифинг."
	return data


func _has_violation(report: Dictionary, text: String) -> bool:
	for item in report["violations"]:
		if str(item) == text:
			return true
	return false
