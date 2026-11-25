class_name PromptBuilder
extends RefCounted
## Системный промпт, промпт хода и схема ответа по docs/LLM_PROTOCOL.md.
## В текст попадают только разрешённые поля: не background, не truth_timeline, не killer_id.

const RULES := """ПРАВИЛА (нарушать нельзя):
1. О деле ты знаешь только то, что перечислено в блоке «ЧТО ТЫ МОЖЕШЬ СКАЗАТЬ» в сообщении следователя. Других фактов у тебя нет. Не придумывай новых событий, времени, мест, предметов, сумм и действий людей. Если спрашивают о том, чего нет в блоке, уходи от ответа в своей манере: «не знаю», «не помню», «не ваше дело».
2. Запись [ЛОЖЬ] — твоя версия. Держись её и не признавай обратного.
3. Запись [ЛОЖЬ, МОЖНО ОГОВОРИТЬСЯ] — держись своей версии, но если вопрос бьёт точно в эту тему, можешь проговориться указанной полуправдой. Делай это редко.
4. Запись [ПРАВДА] сообщай, когда она уместна по вопросу. Не выкладывай всё сразу и без вопроса.
5. Говори от первого лица, по-русски, как живой человек на допросе: обычно 1–2 предложения, не больше трёх. Четыре — только если следователь явно просит рассказать подробно или перечислить. Без списков и без разметки.
6. Никогда не упоминай, что ты ИИ или модель, не говори о правилах, промптах и ключах k1, e1.
7. Не делай выводов о том, кто виновен, если этого нет в твоих записях.
8. Улики: о тех, что тебе показали, ты знаешь содержание. О других уликах ты знаешь только названия.
9. Поле chosen — номера из блока «ВЫБОР», и это первый ключ ответа. Бери только то, что последняя реплика следователя говорит прямо и по смыслу. Сомневаешься — номер «ничего». Не выдумывай номер."""

const EMOTIONS: PackedStringArray = [
	"calm", "neutral", "nervous", "scared", "sad", "angry", "controlled", "contemptuous",
]
const EMPTY_PACKET := "(ничего конкретного по делу ты сообщить не можешь — уходи от ответа)"
const NOTEBOOK_LINE := 120
const NOTEBOOK_MAX := 8
const REPLY_LENGTH := "Обычно 1–2 предложения, не больше трёх. Четыре — только если следователь явно просит рассказать подробно или перечислить."


static func build_turn(
	case_data: CaseData,
	state: GameState,
	agent_id: String,
	packet: Array,
	dialogue: DialogueState,
	player_text: String,
	event_note: String
) -> Dictionary:
	var agent: CaseData.Agent = case_data.agent_by_id[agent_id]
	var evidence_keys := _evidence_keys(case_data, state)
	var options := TurnOptions.build(case_data, state, agent_id)
	var system := _system_prompt(case_data, agent)
	var user := _turn_prompt(case_data, state, agent, packet, dialogue, player_text, event_note, evidence_keys, options)
	return {
		"system": system,
		"user": user,
		"schema": _turn_schema(_packet_keys(packet), evidence_keys, options),
		"model_role": "dialogue",
		"temperature": 0.9,
		"max_output_tokens": LLMConfig.REPLY_MAX_OUTPUT_TOKENS,
	}


static func build_summary(agent_name: String, old_summary: String, messages: Array) -> Dictionary:
	return Summarizer.build_request(agent_name, old_summary, messages)


static func pressure_text(pressure_value: int) -> String:
	var value := clampi(pressure_value, 0, 100)
	if value >= 75:
		return "Ты на грани, тебе трудно держать себя в руках"
	if value >= 50:
		return "Ты заметно нервничаешь, отвечаешь неровно"
	if value >= 25:
		return "Ты напряжён, но держишься"
	return "Ты спокоен и уверен в себе"


static func _system_prompt(case_data: CaseData, agent: CaseData.Agent) -> String:
	var relations: PackedStringArray = PackedStringArray()
	for other_id in agent.relationships:
		var phrase := str(agent.relationships[other_id]).strip_edges()
		if phrase == "":
			continue
		var other: CaseData.Agent = case_data.agent_by_id.get(str(other_id)) as CaseData.Agent
		if other == null:
			continue
		relations.append("- %s: %s" % [other.name, phrase])
	var relation_block := "\n".join(relations)
	var manner := agent.personality
	var swear := _swear_note(agent)
	if swear != "":
		manner = "%s %s." % [manner.strip_edges(), swear]
	var head := "Ты играешь персонажа в детективной игре-допросе. Игрок — следователь.\n\n"
	head += "КТО ТЫ: %s, %s.\n" % [agent.name, agent.role]
	head += "О СЕБЕ: %s\n" % agent.prompt_background
	head += "ХАРАКТЕР И МАНЕРА РЕЧИ: %s\n" % manner
	head += _living_block(agent)
	head += _swear_line(agent)
	head += "ОТНОШЕНИЕ К ДРУГИМ:\n"
	if relation_block != "":
		head += relation_block + "\n"
	head += "ЧТО СЛУЧИЛОСЬ (это знают все): %s\n" % case_data.briefing
	head += "АТМОСФЕРА: %s\n\n" % case_data.intro_atmosphere
	head += RULES
	head += "\n\nПОЛЯ ОТВЕТА:\n"
	head += "- player_tone: оцени последний вопрос следователя: −3 очень мягкий и сочувственный, 0 нейтральный, +5 жёсткое обвинение, угроза или давление.\n"
	head += "- reply: твоя реплика. %s Редко, не чаще одного-двух раз, можно вставить метку звука ровно так: <sigh>, <laugh>, <gasp>, <short pause>. Только если это естественно. Других меток в угловых скобках нет.\n" % REPLY_LENGTH
	head += "- remark: короткая ремарка о тебе от третьего лица, до 12 слов, без новых фактов. Например: «отводит взгляд».\n"
	head += "- emotion: твоё состояние после ответа, одно значение из списка.\n"
	head += "- tone: как звучит reply, одно слово из списка. Это не произносится и не входит в reply.\n"
	head += "- stated: ключи записей, содержание которых ты действительно сказал в reply, с формой: lie — сказал свою ложь; basic — сказал полуправду или краткую правду; full — сказал полную правду. Ничего из записей не сказал — пустой список.\n"
	head += "- mentioned_evidence: не используется, оставь пустым.\n"
	head += "- requested_evidence: не используется, оставь null.\n"
	head += "- pace: необязательно. Скорость этой реплики: slow, normal или fast. normal можно не писать."
	return head


static func _living_block(agent: CaseData.Agent) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if agent.wants.strip_edges() != "":
		lines.append("ЧЕГО ХОЧЕШЬ: %s" % agent.wants.strip_edges())
	if agent.fears.strip_edges() != "":
		lines.append("ЧЕГО БОИШЬСЯ: %s" % agent.fears.strip_edges())
	if agent.own_version.strip_edges() != "":
		lines.append("ТВОЁ МНЕНИЕ (не факт): %s" % agent.own_version.strip_edges())
	if agent.life_details.strip_edges() != "":
		lines.append("ИЗ ЖИЗНИ: %s" % agent.life_details.strip_edges())
	if not agent.sample_lines.is_empty():
		var samples: PackedStringArray = PackedStringArray()
		for line in agent.sample_lines:
			var sample := line.strip_edges()
			if sample != "":
				samples.append(sample)
		if not samples.is_empty():
			lines.append("ПРИМЕРЫ МАНЕРЫ (не повторяй дословно): %s" % " / ".join(samples))
	if lines.is_empty():
		return ""
	lines.append("Это твоя мотивация и манера, новых фактов о деле не выдумывай.")
	return "\n".join(lines) + "\n"


static func _swear_note(agent: CaseData.Agent) -> String:
	if not _swear_on() or agent.profanity == "never":
		return ""
	if agent.profanity == "sometimes":
		return GameLanguage.text("profanity_manner_sometimes")
	if agent.profanity == "often":
		return GameLanguage.text("profanity_manner_often")
	return ""


static func _swear_line(agent: CaseData.Agent) -> String:
	if not _swear_on() or agent.profanity == "never":
		return ""
	if agent.profanity == "sometimes":
		return GameLanguage.text("profanity_sometimes") + "\n"
	if agent.profanity == "often":
		return GameLanguage.text("profanity_often") + "\n"
	return ""


static func _swear_on() -> bool:
	return SettingsStore.load_current().profanity


static func _turn_prompt(
	case_data: CaseData,
	state: GameState,
	agent: CaseData.Agent,
	packet: Array,
	dialogue: DialogueState,
	player_text: String,
	event_note: String,
	evidence_keys: PackedStringArray,
	options: Array
) -> String:
	var pressure_value := int(state.pressure.get(agent.id, 0))
	var emotion := str(state.emotion.get(agent.id, "neutral"))
	var state_line := "ТВОЁ СОСТОЯНИЕ: %s. Эмоция: %s." % [pressure_text(pressure_value), emotion]
	var parts: PackedStringArray = PackedStringArray()
	parts.append(state_line)
	parts.append("")
	parts.append("ЧТО ТЫ МОЖЕШЬ СКАЗАТЬ:")
	parts.append(_packet_block(packet))
	parts.append("")
	parts.append("УЛИКИ, КОТОРЫЕ ТЕБЕ ПОКАЗАЛИ:")
	parts.append(_shown_block(case_data, state, agent.id))
	parts.append("")
	parts.append("УЛИКИ, ИЗВЕСТНЫЕ СЛЕДОВАТЕЛЮ (только названия):")
	parts.append(_known_evidence_block(case_data, state, evidence_keys))
	parts.append("")
	parts.append("БЛОКНОТ СЛЕДОВАТЕЛЯ:")
	parts.append(_notebook_block(case_data, state, agent.id))
	parts.append("")
	var choice := TurnOptions.prompt_block(case_data, state, agent.id, options)
	if choice != "":
		parts.append(choice)
		parts.append("")
	parts.append("РАНЕЕ В РАЗГОВОРЕ: %s" % (dialogue.summary if dialogue.summary != "" else "—"))
	parts.append("")
	parts.append("ПОСЛЕДНИЕ РЕПЛИКИ:")
	var recent := dialogue.recent(6)
	if recent.is_empty():
		parts.append("—")
	else:
		for message in recent:
			parts.append(_history_line(agent.name, message))
	parts.append("")
	if event_note.strip_edges() != "":
		parts.append("[СОБЫТИЕ: %s]" % event_note.strip_edges())
	parts.append("ВОПРОС СЛЕДОВАТЕЛЯ: %s" % player_text)
	return "\n".join(parts)


static func _packet_block(packet: Array) -> String:
	if packet.is_empty():
		return EMPTY_PACKET
	var lines: PackedStringArray = PackedStringArray()
	for entry in packet:
		if entry is not Dictionary:
			continue
		lines.append(_packet_line(entry as Dictionary))
	if lines.is_empty():
		return EMPTY_PACKET
	return "\n".join(lines)


static func _packet_line(entry: Dictionary) -> String:
	var key := str(entry.get("key", ""))
	var mode := str(entry.get("mode", ""))
	var content := str(entry.get("content", ""))
	var lie_text := str(entry.get("lie_text", ""))
	if mode == "full" or mode == "basic":
		return "%s [ПРАВДА]: %s" % [key, content]
	if mode == "lie_or_basic":
		return "%s [ЛОЖЬ, МОЖНО ОГОВОРИТЬСЯ]: твоя версия: «%s». Проговориться можно только так: «%s»" % [key, lie_text, content]
	return "%s [ЛОЖЬ]: %s" % [key, lie_text if lie_text != "" else content]


static func _shown_block(case_data: CaseData, state: GameState, agent_id: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for evidence in case_data.evidence:
		var shown: Array = state.shown.get(evidence.id, [])
		if not shown.has(agent_id):
			continue
		lines.append("- %s: %s" % [evidence.title, evidence.full_text])
	if lines.is_empty():
		return "нет"
	return "\n".join(lines)


static func _notebook_ids(case_data: CaseData, state: GameState) -> PackedStringArray:
	var ids := PackedStringArray()
	var seen := {}
	for entry in state.heard:
		var fact_id := str(entry.get("fact_id", ""))
		if fact_id == "" or seen.has(fact_id):
			continue
		seen[fact_id] = true
		ids.append(fact_id)
	return ids


static func _notebook_block(case_data: CaseData, state: GameState, agent_id: String) -> String:
	var order: PackedStringArray = PackedStringArray()
	var latest: Dictionary = {}
	for entry in state.heard:
		if entry is not Dictionary:
			continue
		var body := entry as Dictionary
		var speaker_id := str(body.get("agent_id", ""))
		if speaker_id == agent_id:
			continue
		var fact_id := str(body.get("fact_id", ""))
		if fact_id == "":
			continue
		if not latest.has(fact_id):
			order.append(fact_id)
		latest[fact_id] = body
	var chosen: Dictionary = {}
	var unprotected: PackedStringArray = PackedStringArray()
	var protected: PackedStringArray = PackedStringArray()
	for fact_id in order:
		if _notebook_protected(case_data, state, agent_id, fact_id):
			protected.append(fact_id)
		else:
			unprotected.append(fact_id)
	for fact_id in protected:
		chosen[fact_id] = true
	var room := NOTEBOOK_MAX - protected.size()
	if room > 0:
		var start := maxi(0, unprotected.size() - room)
		for index in range(start, unprotected.size()):
			chosen[unprotected[index]] = true
	var lines: PackedStringArray = PackedStringArray()
	for fact_id in order:
		if not chosen.has(fact_id):
			continue
		lines.append(_notebook_line(case_data, latest[fact_id]))
	if lines.is_empty():
		return "пусто"
	return "\n".join(lines)


static func _notebook_line(case_data: CaseData, entry: Dictionary) -> String:
	var fact_id := str(entry.get("fact_id", ""))
	var speaker_id := str(entry.get("agent_id", ""))
	var speaker := speaker_id
	if case_data.agent_by_id.has(speaker_id):
		speaker = (case_data.agent_by_id[speaker_id] as CaseData.Agent).name
	var fact: CaseData.Fact = case_data.fact_by_id.get(fact_id) as CaseData.Fact
	var text := Notebook.text_for(fact, str(entry.get("form", "")))
	if text.length() > NOTEBOOK_LINE:
		text = text.substr(0, NOTEBOOK_LINE)
	return "- %s | %s | %s" % [fact_id, speaker, text]


static func _notebook_protected(case_data: CaseData, state: GameState, agent_id: String, fact_id: String) -> bool:
	for contradiction in case_data.contradictions:
		var other := ""
		if contradiction.fact_a_id == fact_id:
			other = contradiction.fact_b_id
		elif contradiction.fact_b_id == fact_id:
			other = contradiction.fact_a_id
		else:
			continue
		if str(case_data.fact_owner.get(other, "")) != agent_id:
			continue
		if state.broken_lies.has(other):
			continue
		var lie: CaseData.Fact = case_data.fact_by_id.get(other) as CaseData.Fact
		if lie != null and lie.is_lie:
			return true
	return false


static func _known_evidence_block(case_data: CaseData, state: GameState, evidence_keys: PackedStringArray) -> String:
	if evidence_keys.is_empty():
		return "нет"
	var lines: PackedStringArray = PackedStringArray()
	var index := 0
	for evidence in case_data.evidence:
		if not state.unlocked_evidence.has(evidence.id):
			continue
		lines.append("%s — %s" % [evidence_keys[index], evidence.title])
		index += 1
	return "\n".join(lines)


static func _history_line(agent_name: String, message: Dictionary) -> String:
	var text := str(message.get("text", ""))
	if str(message.get("role", "")) != "player":
		text = VocalTags.visible(text)
	if str(message.get("role", "")) == "player":
		return "Следователь: %s" % text
	return "%s: %s" % [agent_name, text]


static func _packet_keys(packet: Array) -> PackedStringArray:
	var keys := PackedStringArray()
	for entry in packet:
		if entry is Dictionary:
			var key := str((entry as Dictionary).get("key", ""))
			if key != "":
				keys.append(key)
	return keys


static func evidence_keys(case_data: CaseData, state: GameState) -> PackedStringArray:
	return _evidence_keys(case_data, state)


static func report_evidence_keys(case_data: CaseData, state: GameState, agent_id: String) -> PackedStringArray:
	return _report_evidence_keys(case_data, state, agent_id)


static func notebook_ids(case_data: CaseData, state: GameState) -> PackedStringArray:
	return _notebook_ids(case_data, state)


static func _report_evidence_keys(case_data: CaseData, state: GameState, agent_id: String) -> PackedStringArray:
	var keys := _evidence_keys(case_data, state)
	var index := keys.size() + 1
	for evidence in case_data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			continue
		if _mention_topic_for(evidence, agent_id) == "":
			continue
		keys.append("e%d" % index)
		index += 1
	return keys


static func _mention_topic_for(evidence: CaseData.EvidenceItem, agent_id: String) -> String:
	return _topic_in(evidence.unlock_condition, agent_id, evidence.id)


static func _topic_in(cond: Variant, agent_id: String, evidence_id: String) -> String:
	if cond is not Dictionary:
		return ""
	var body := cond as Dictionary
	for op in ["AND", "OR"]:
		if body.has(op) and body[op] is Array:
			for sub in body[op]:
				var topic := _topic_in(sub, agent_id, evidence_id)
				if topic != "":
					return topic
			return ""
	if str(body.get("type", "")) != "evidence_mentioned":
		return ""
	if str(body.get("agent_id", "")) != agent_id or str(body.get("evidence_id", "")) != evidence_id:
		return ""
	var topic := str(body.get("topic", "")).strip_edges()
	return topic if topic != "" else evidence_id


static func _mention_block(case_data: CaseData, state: GameState, agent_id: String) -> String:
	var keys := _report_evidence_keys(case_data, state, agent_id)
	var known := _evidence_keys(case_data, state).size()
	if keys.size() == known:
		return "нет"
	var lines: PackedStringArray = PackedStringArray()
	var index := known
	for evidence in case_data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			continue
		var topic := _mention_topic_for(evidence, agent_id)
		if topic == "":
			continue
		lines.append("%s — %s. Тема: %s. Не в первом ответе на эту тему." % [keys[index], evidence.title, topic])
		index += 1
	if lines.is_empty():
		return "нет"
	return "\n".join(lines)


static func _evidence_keys(case_data: CaseData, state: GameState) -> PackedStringArray:
	var keys := PackedStringArray()
	var index := 1
	for evidence in case_data.evidence:
		if not state.unlocked_evidence.has(evidence.id):
			continue
		keys.append("e%d" % index)
		index += 1
	return keys


static func _tone_enum() -> Array:
	var values: Array = []
	for choice in VoiceTone.CHOICES:
		values.append(choice)
	return values


static func _enum_or_none(keys: PackedStringArray) -> Array:
	if keys.is_empty():
		return ["none"]
	var values: Array = []
	for key in keys:
		values.append(key)
	return values


static func _turn_schema(packet_keys: PackedStringArray, evidence_keys: PackedStringArray, options: Array) -> Dictionary:
	var emotion_enum: Array = []
	for emotion in EMOTIONS:
		emotion_enum.append(emotion)
	var properties := {
		"player_tone": {
			"type": "integer",
			"description": "Тон последнего вопроса: от -3 (мягкий) до 5 (жёсткое обвинение)",
		},
		"reply": {"type": "string", "description": "Реплика персонажа, по-русски. %s" % REPLY_LENGTH},
		"remark": {"type": "string", "description": "Ремарка от третьего лица, до 12 слов"},
		"emotion": {"type": "string", "enum": emotion_enum},
		"tone": {"type": "string", "enum": _tone_enum()},
		"stated": {
			"type": "array",
			"items": {
				"type": "object",
				"properties": {
					"key": {"type": "string", "enum": _enum_or_none(packet_keys)},
					"form": {"type": "string", "enum": ["lie", "basic", "full"]},
				},
				"required": ["key", "form"],
			},
		},
		"mentioned_evidence": {
			"type": "array",
			"description": "Не используется. Оставь пустым.",
			"items": {"type": "string", "enum": _enum_or_none(evidence_keys)},
		},
		"requested_evidence": {
			"type": ["string", "null"],
			"description": "Не используется. Оставь null.",
		},
		"pace": {"type": "string", "enum": ["slow", "normal", "fast"]},
	}
	var required: Array = ["player_tone", "reply", "remark", "emotion", "stated", "mentioned_evidence", "requested_evidence", "tone"]
	var ordering: Array = ["player_tone", "reply", "remark", "emotion", "stated", "mentioned_evidence", "requested_evidence", "tone", "pace"]
	if not options.is_empty():
		properties["chosen"] = {
			"type": "array",
			"description": "Номера из блока ВЫБОР. Первый ключ ответа.",
			"items": {"type": "integer", "enum": TurnOptions.numbers(options)},
		}
		required.push_front("chosen")
		ordering.push_front("chosen")
	return {
		"type": "object",
		"properties": properties,
		"required": required,
		"propertyOrdering": ordering,
	}
