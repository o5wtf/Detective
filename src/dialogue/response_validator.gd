class_name ResponseValidator
extends RefCounted
## Проверка ответа модели по docs/LLM_PROTOCOL.md, раздел 6.
## Ключи пакета переводятся в fact_id. Секреты в текст нарушения не попадают.

const TONE_MIN := -3
const TONE_MAX := 5
const REPLY_MAX := 700
const SERVICE_PHRASES: PackedStringArray = [
	"нейросеть", "языковая модель", "промпт",
]
const COMMON_WORDS: PackedStringArray = [
	"который", "которая", "которые", "которую", "потому", "говорил", "говорит",
	"сказала", "сказал", "человек", "просто", "сейчас", "ничего", "только",
	"всегда", "никогда", "вопрос", "ответа", "следователь",
]


static func validate(resp: Variant, packet: Array, context: Dictionary) -> Dictionary:
	var local_fixes: bool = bool(context.get("local_fixes", true))
	var report := {
		"ok": true,
		"violations": PackedStringArray(),
		"fixes": PackedStringArray(),
		"statements": [] as Array[Dictionary],
		"tone": 0,
		"emotion": str(context.get("previous_emotion", "neutral")),
		"reply": "",
		"remark": "",
		"speech_tone": "",
		"pace": "",
		"spoken_reply": "",
		"mentioned_evidence": [] as Array[String],
		"requested_evidence": "",
		"cited_facts": [] as Array[String],
	}
	if resp is not Dictionary:
		_violate(report, "пустая реплика")
		return report
	var body := _normalize(resp as Dictionary)
	if not _has_types(body):
		if str(body.get("reply", "")).strip_edges() == "":
			_violate(report, "пустая реплика")
			return report
		if not local_fixes:
			_violate(report, "в ответе нет обязательных полей или типы неверные")
			return report
		_fill_defaults(body, context)
		_log_fix(report, "defaults")
	var by_key := _index_packet(packet)
	var stated: Array = body["stated"]
	var seen := {}
	for item in stated:
		if item is not Dictionary:
			if local_fixes:
				_log_fix(report, "drop stated")
			else:
				_violate(report, "элемент stated не объект")
			continue
		var key := str((item as Dictionary).get("key", ""))
		var form := str((item as Dictionary).get("form", ""))
		if key == "" or key == "none":
			continue
		if seen.has(key):
			continue
		seen[key] = true
		if not by_key.has(key):
			if local_fixes:
				_log_fix(report, "drop key=%s" % key)
			else:
				_violate(report, "ключ stated не из пакета")
			continue
		var entry: Dictionary = by_key[key]
		var mode := str(entry.get("mode", ""))
		if not _form_allowed(mode, form):
			if not local_fixes:
				_violate(report, "форма stated не подходит к записи пакета")
				continue
			var downgraded := _downgrade_form(mode, form)
			if downgraded == "":
				_log_fix(report, "drop form key=%s" % key)
				continue
			_log_fix(report, "form key=%s %s->%s" % [key, form, downgraded])
			form = downgraded
		report["statements"].append({
			"key": key,
			"fact_id": str(entry.get("fact_id", "")),
			"form": form,
		})
	var tagged := VocalTags.limit(_strip_markup(str(body["reply"])))
	if local_fixes:
		var limited := _limit_sentences(tagged, 4)
		if limited != tagged:
			_log_fix(report, "sentences")
			tagged = limited
		if tagged.length() > REPLY_MAX:
			_log_fix(report, "length")
			tagged = tagged.substr(0, REPLY_MAX).strip_edges()
	var reply := VocalTags.visible(tagged)
	report["spoken_reply"] = tagged
	report["reply"] = reply
	report["remark"] = str(body["remark"])
	var speech_tone := VoiceTone.normalize(str(body.get("tone", "")))
	report["pace"] = SpeechStyle.normalize_pace(str(body.get("pace", "")))
	if str(body.get("tone", "")).strip_edges() != "" and speech_tone == "":
		_log_fix(report, "tone")
	report["speech_tone"] = speech_tone
	if reply.strip_edges() == "":
		_violate(report, "пустая реплика")
	elif not local_fixes and (reply.length() < 1 or reply.length() > REPLY_MAX):
		_violate(report, "длина реплики не в пределах 1–700")
	if _has_service_word(reply):
		_violate(report, "в реплике служебное слово")
	if _leaks(reply, packet, context):
		_violate(report, "возможная утечка")
		if context.get("log_leaks", true) == true:
			_log_leak()
	_auto_state(report, reply, by_key)
	report["tone"] = _clamp_tone(body["player_tone"])
	var emotion := str(body["emotion"])
	if Balance.emotion_allowed(emotion):
		report["emotion"] = emotion
	var allowed_evidence := _allowed_evidence_keys(context)
	report["mentioned_evidence"] = _filter_evidence(body["mentioned_evidence"], allowed_evidence)
	report["requested_evidence"] = _filter_requested(body["requested_evidence"], allowed_evidence)
	report["cited_facts"] = _filter_citations(body.get("cited_facts", []), context, report, local_fixes)
	return report


static func needs_regeneration(report: Dictionary) -> bool:
	if report.get("ok", true):
		return false
	for item in report.get("violations", PackedStringArray()):
		var text := str(item)
		if text == "возможная утечка" or text == "в реплике служебное слово" or text == "пустая реплика":
			return true
	return false


static func repair_note(violations: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var leak := false
	for item in violations:
		if item == "возможная утечка":
			leak = true
		else:
			parts.append(item)
	if leak:
		parts.append("ты назвал сведения, которых нет в твоём списке, — не называй точного времени, чисел и подробностей, которых там нет")
	return "ИСПРАВЬ ОТВЕТ: %s. Говори только то, что есть в блоке «ЧТО ТЫ МОЖЕШЬ СКАЗАТЬ»." % ", ".join(parts)


static func fallback_reply(pressure_value: int) -> String:
	match Balance.band(pressure_value):
		"tense":
			return "Я не буду об этом говорить."
		"nervous", "breaking":
			return "Спросите что-нибудь другое."
		_:
			return "…Мне нечего добавить."


static func _normalize(body: Dictionary) -> Dictionary:
	var copy := body.duplicate(true)
	if copy.get("stated") is Dictionary:
		copy["stated"] = [copy["stated"]]
	if copy.get("stated") == null and copy.has("stated"):
		copy["stated"] = []
	if copy.get("mentioned_evidence") is String:
		copy["mentioned_evidence"] = [copy["mentioned_evidence"]]
	var ready := copy.has("reply") and copy.has("remark") and copy.has("emotion") and copy.has("player_tone") and copy.has("stated")
	if ready:
		if not copy.has("mentioned_evidence") or copy["mentioned_evidence"] == null:
			copy["mentioned_evidence"] = []
		if not copy.has("requested_evidence"):
			copy["requested_evidence"] = null
		if copy.get("cited_facts") is String:
			copy["cited_facts"] = [copy["cited_facts"]]
		elif not copy.has("cited_facts") or copy["cited_facts"] == null:
			copy["cited_facts"] = []
	var tone: Variant = copy.get("player_tone", 0)
	if tone is String and str(tone).is_valid_float():
		copy["player_tone"] = int(float(tone))
	if copy.has("emotion") and copy["emotion"] is String:
		copy["emotion"] = str(copy["emotion"]).strip_edges().to_lower()
	return copy


static func _has_types(body: Dictionary) -> bool:
	if not body.has_all(["player_tone", "reply", "remark", "emotion", "stated", "mentioned_evidence", "requested_evidence"]):
		return false
	if not (body["player_tone"] is int or body["player_tone"] is float):
		return false
	if body["reply"] is not String or body["remark"] is not String or body["emotion"] is not String:
		return false
	if body["stated"] is not Array or body["mentioned_evidence"] is not Array or body.get("cited_facts") is not Array:
		return false
	var requested: Variant = body["requested_evidence"]
	return requested == null or requested is String


static func _index_packet(packet: Array) -> Dictionary:
	var indexed := {}
	for entry in packet:
		if entry is Dictionary:
			indexed[str((entry as Dictionary).get("key", ""))] = entry
	return indexed


static func _downgrade_form(mode: String, form: String) -> String:
	var ladder: PackedStringArray = ["full", "basic", "lie"]
	var start := ladder.find(form)
	if start < 0:
		start = 0
	for index in range(start, ladder.size()):
		if _form_allowed(mode, ladder[index]):
			return ladder[index]
	return ""


static func _limit_sentences(reply: String, limit: int) -> String:
	var pattern := RegEx.new()
	pattern.compile("[^.!?…]+[.!?…]+|[^.!?…]+$")
	var sentences: PackedStringArray = PackedStringArray()
	for match in pattern.search_all(reply):
		var sentence := match.get_string().strip_edges()
		if sentence != "":
			sentences.append(sentence)
	if sentences.size() <= limit:
		return reply
	return " ".join(sentences.slice(0, limit))


static func _fill_defaults(body: Dictionary, context: Dictionary) -> void:
	if not (body.get("player_tone") is int or body.get("player_tone") is float):
		body["player_tone"] = 0
	if body.get("remark") is not String:
		body["remark"] = ""
	if body.get("emotion") is not String:
		body["emotion"] = str(context.get("previous_emotion", "neutral"))
	if body.get("stated") is not Array:
		body["stated"] = []
	if body.get("mentioned_evidence") is not Array:
		body["mentioned_evidence"] = []
	if not body.has("requested_evidence"):
		body["requested_evidence"] = null
	if body.get("cited_facts") is not Array:
		body["cited_facts"] = []


static func _log_fix(report: Dictionary, message: String) -> void:
	print("validator fix %s" % message)
	var fixes: PackedStringArray = report.get("fixes", PackedStringArray())
	fixes.append(message)
	report["fixes"] = fixes


static func _form_allowed(mode: String, form: String) -> bool:
	match mode:
		"lie":
			return form == "lie"
		"lie_or_basic":
			return form == "lie" or form == "basic"
		"basic":
			return form == "basic"
		"full":
			return form == "basic" or form == "full"
		_:
			return false


static func _strip_markup(text: String) -> String:
	var without := text.replace("*", "").replace("#", "")
	var bullet := RegEx.new()
	bullet.compile("^\\s*(?:[-•]|\\d+\\.)\\s+")
	var lines: PackedStringArray = PackedStringArray()
	for line in without.split("\n"):
		var match := bullet.search(line)
		if match != null:
			line = line.substr(match.get_end())
		lines.append(line)
	return "\n".join(lines).strip_edges()


static func _has_service_word(reply: String) -> bool:
	var lower := reply.to_lower()
	if lower.contains("ии") and _has_token(lower, "ии"):
		return true
	for phrase in SERVICE_PHRASES:
		if lower.contains(phrase):
			return true
	var keys := RegEx.new()
	keys.compile("(?i)\\b[ke]\\d+\\b")
	return keys.search(reply) != null


static func _has_token(text: String, token: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("(?<![а-яёa-z])%s(?![а-яёa-z])" % token)
	return pattern.search(text) != null


static func _leaks(reply: String, packet: Array, context: Dictionary) -> bool:
	var closed := _tokens(_closed_source(packet, context))
	var allowed := _tokens(_allowed_source(packet, context))
	var reply_tokens := _tokens(reply)
	for number in reply_tokens["numbers"]:
		if closed["numbers"].has(number) and not allowed["numbers"].has(number):
			return true
	var hits := 0
	for stem in reply_tokens["stems"]:
		if closed["stems"].has(stem) and not allowed["stems"].has(stem):
			hits += 1
	return hits > int(context.get("leak_max_stems", 1))


static func _closed_source(packet: Array, context: Dictionary) -> String:
	var case_data: CaseData = context.get("case_data")
	var agent_id := str(context.get("agent_id", ""))
	if case_data == null:
		return ""
	var in_packet := {}
	for entry in packet:
		if entry is Dictionary:
			in_packet[str((entry as Dictionary).get("fact_id", ""))] = entry
	var chunks: PackedStringArray = PackedStringArray()
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	if agent == null:
		return ""
	for fact in agent.facts:
		if not in_packet.has(fact.id):
			chunks.append(fact.content_basic)
			chunks.append(fact.content_full)
			chunks.append(fact.lie_text)
			continue
		var mode := str((in_packet[fact.id] as Dictionary).get("mode", ""))
		if mode == "basic" or mode == "lie_or_basic":
			chunks.append(fact.content_full)
		elif mode == "lie":
			chunks.append(fact.content_basic)
			chunks.append(fact.content_full)
	return "\n".join(chunks)


static func _allowed_source(packet: Array, context: Dictionary) -> String:
	var chunks: PackedStringArray = PackedStringArray()
	for word in COMMON_WORDS:
		chunks.append(word)
	for entry in packet:
		if entry is not Dictionary:
			continue
		var body := entry as Dictionary
		var mode := str(body.get("mode", ""))
		if mode == "lie" or mode == "lie_or_basic":
			chunks.append(str(body.get("lie_text", "")))
		if mode == "basic" or mode == "full" or mode == "lie_or_basic":
			chunks.append(str(body.get("content", "")))
	var case_data: CaseData = context.get("case_data")
	var state: GameState = context.get("state")
	var agent_id := str(context.get("agent_id", ""))
	if case_data != null:
		chunks.append(case_data.briefing)
		chunks.append(case_data.intro_atmosphere)
		var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
		if agent != null:
			chunks.append(agent.prompt_background)
			chunks.append(agent.personality)
			chunks.append(agent.wants)
			chunks.append(agent.fears)
			chunks.append(agent.own_version)
			chunks.append(agent.life_details)
			chunks.append(agent.greeting)
			for sample in agent.sample_lines:
				chunks.append(sample)
			chunks.append(agent.name)
			chunks.append(agent.role)
			for other_id in agent.relationships:
				chunks.append(str(agent.relationships[other_id]))
		if state != null:
			for evidence in case_data.evidence:
				var shown: Array = state.shown.get(evidence.id, [])
				if shown.has(agent_id):
					chunks.append(evidence.title)
					chunks.append(evidence.full_text)
	chunks.append(str(context.get("player_text", "")))
	var dialogue: DialogueState = context.get("dialogue")
	if dialogue != null:
		chunks.append(dialogue.summary)
		for message in dialogue.messages:
			chunks.append(str(message.get("text", "")))
	return "\n".join(chunks)


static func _tokens(text: String) -> Dictionary:
	var numbers := {}
	var stems := {}
	var time_re := RegEx.new()
	time_re.compile("\\d{1,2}:\\d{2}")
	var without_times := text
	for match in time_re.search_all(text):
		numbers[match.get_string()] = true
		without_times = without_times.replace(match.get_string(), " ")
	var number_re := RegEx.new()
	number_re.compile("\\d+[.,]\\d+|\\d{2,}")
	for match in number_re.search_all(without_times):
		numbers[match.get_string()] = true
	var word_re := RegEx.new()
	word_re.compile("[A-Za-zА-Яа-яЁё]{7,}")
	for match in word_re.search_all(text):
		stems[match.get_string().to_lower().substr(0, 6)] = true
	return {"numbers": numbers, "stems": stems}


static func _auto_state(report: Dictionary, reply: String, by_key: Dictionary) -> void:
	var reply_numbers: Dictionary = _tokens(reply)["numbers"]
	var already := {}
	for statement in report["statements"]:
		already[str(statement["key"])] = true
	for number in reply_numbers:
		var owner := ""
		var hits := 0
		for key in by_key:
			if _entry_text(by_key[key]).contains(str(number)):
				hits += 1
				owner = str(key)
		if hits != 1 or already.has(owner):
			continue
		var entry: Dictionary = by_key[owner]
		var form := _auto_form(str(entry.get("mode", "")), str(number), entry)
		if form == "" or not _form_allowed(str(entry.get("mode", "")), form):
			continue
		report["statements"].append({
			"key": owner,
			"fact_id": str(entry.get("fact_id", "")),
			"form": form,
		})
		already[owner] = true


static func _entry_text(entry: Dictionary) -> String:
	return "%s\n%s" % [str(entry.get("lie_text", "")), str(entry.get("content", ""))]


static func _auto_form(mode: String, number: String, entry: Dictionary) -> String:
	if mode == "lie" or mode == "lie_or_basic":
		return "lie"
	if mode == "basic":
		return "basic"
	if mode == "full":
		return "full" if str(entry.get("content", "")).contains(number) else "basic"
	return ""


static func _clamp_tone(value: Variant) -> int:
	return clampi(int(value), TONE_MIN, TONE_MAX)


static func _allowed_evidence_keys(context: Dictionary) -> Dictionary:
	var allowed := {}
	var keys: Variant = context.get("evidence_keys", [])
	if keys is PackedStringArray or keys is Array:
		for key in keys:
			allowed[str(key)] = true
	return allowed


static func _filter_citations(value: Variant, context: Dictionary, report: Dictionary, local_fixes: bool) -> Array[String]:
	var allowed := {}
	var keys: Variant = context.get("notebook_ids", [])
	if keys is PackedStringArray or keys is Array:
		for fact_id in keys:
			allowed[str(fact_id)] = true
	var result: Array[String] = []
	if value is not Array:
		return result
	for item in value:
		var fact_id := str(item)
		if fact_id == "" or fact_id == "none":
			continue
		if not allowed.has(fact_id):
			if local_fixes:
				_log_fix(report, "drop cited=%s" % fact_id)
			else:
				_violate(report, "cited_facts вне блокнота")
			continue
		if not result.has(fact_id):
			result.append(fact_id)
	return result


static func _filter_evidence(raw: Array, allowed: Dictionary) -> Array[String]:
	var kept: Array[String] = []
	for item in raw:
		var key := str(item)
		if key == "none" or key == "":
			continue
		if allowed.has(key):
			kept.append(key)
	return kept


static func _filter_requested(raw: Variant, allowed: Dictionary) -> String:
	if raw == null:
		return ""
	var key := str(raw)
	if key == "" or key == "none" or not allowed.has(key):
		return ""
	return key


static func _violate(report: Dictionary, message: String) -> void:
	report["ok"] = false
	var violations: PackedStringArray = report["violations"]
	violations.append(message)
	report["violations"] = violations


static func _log_leak() -> void:
	DirAccess.make_dir_absolute("user://logs")
	var path := "user://logs/leaks.log"
	var flags := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var file := FileAccess.open(path, flags)
	if file == null:
		return
	if flags == FileAccess.READ_WRITE:
		file.seek_end()
	file.store_line("leak")
	file.close()
