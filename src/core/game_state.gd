class_name GameState
extends RefCounted
## Изменяемое состояние партии. Без правил.

var pressure: Dictionary = {}
var emotion: Dictionary = {}
var unlocked_evidence: Array[String] = []
var shown: Dictionary = {}
var broken_lies: Array[String] = []
var fact_levels: Dictionary = {}
var heard: Array[Dictionary] = []
var contradictions: Array[String] = []
## Ход, на котором противоречие нашлось. Старые сохранения этого поля не имеют.
var contradiction_turns: Dictionary = {}
## Улики, которые нужный персонаж сам назвал. Старые сохранения поля не имеют.
var evidence_mentions: Array[String] = []
## Сколько раз персонаж уже касался темы закрытой улики. Старые сохранения поля не имеют.
var topic_touches: Dictionary = {}
## Пересказы: «лжец|факт|basic|full». Старые сохранения поля не имеют.
var retold: Array[String] = []
## Предъявления против показания. Старые сохранения поля не имеют.
var confrontations: Array[Dictionary] = []
## События ленты. Не входят в реплики и в промпт. Старые сохранения поля не имеют.
var feed_events: Array[Dictionary] = []
var talked_to: Array[String] = []
var accusation: Dictionary = {
	"killer_ok": false,
	"motive_ok": false,
	"method_ok": false,
	"attempts": 0,
}
var dialogues: Dictionary = {}
var turn: int = 0
var case_id: String = ""
var case_version_hash: String = ""


func to_dict() -> Dictionary:
	return {
		"pressure": pressure.duplicate(true),
		"emotion": emotion.duplicate(true),
		"unlocked_evidence": unlocked_evidence.duplicate(),
		"shown": shown.duplicate(true),
		"broken_lies": broken_lies.duplicate(),
		"fact_levels": fact_levels.duplicate(true),
		"heard": heard.duplicate(true),
		"contradictions": contradictions.duplicate(),
		"contradiction_turns": contradiction_turns.duplicate(true),
		"evidence_mentions": evidence_mentions.duplicate(),
		"topic_touches": topic_touches.duplicate(true),
		"retold": retold.duplicate(),
		"confrontations": confrontations.duplicate(true),
		"feed_events": feed_events.duplicate(true),
		"talked_to": talked_to.duplicate(),
		"accusation": accusation.duplicate(true),
		"dialogues": dialogues.duplicate(true),
		"turn": turn,
		"case_id": case_id,
		"case_version_hash": case_version_hash,
	}


static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.pressure = _int_map(data.get("pressure", {}))
	state.emotion = _string_map(data.get("emotion", {}))
	state.unlocked_evidence = _string_list(data.get("unlocked_evidence", []))
	state.shown = _shown_map(data.get("shown", {}))
	state.broken_lies = _string_list(data.get("broken_lies", []))
	state.fact_levels = _string_map(data.get("fact_levels", {}))
	state.heard = _heard_list(data.get("heard", []))
	state.contradictions = _string_list(data.get("contradictions", []))
	state.contradiction_turns = _int_map(data.get("contradiction_turns", {}))
	state.evidence_mentions = _string_list(data.get("evidence_mentions", []))
	state.topic_touches = _int_map(data.get("topic_touches", {}))
	state.retold = _string_list(data.get("retold", []))
	state.confrontations = _confrontation_list(data.get("confrontations", []))
	state.feed_events = _event_list(data.get("feed_events", []))
	state.talked_to = _string_list(data.get("talked_to", []))
	state.accusation = _accusation(data.get("accusation", {}))
	state.dialogues = (data.get("dialogues", {}) as Dictionary).duplicate(true)
	state.turn = int(data.get("turn", 0))
	state.case_id = str(data.get("case_id", ""))
	state.case_version_hash = str(data.get("case_version_hash", ""))
	return state


static func _int_map(value: Variant) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for key in value:
			result[str(key)] = int(value[key])
	return result


static func _string_map(value: Variant) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for key in value:
			result[str(key)] = str(value[key])
	return result


static func _string_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


static func _shown_map(value: Variant) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for key in value:
			result[str(key)] = _string_list(value[key])
	return result


static func _heard_list(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is not Dictionary:
				continue
			var body := item as Dictionary
			result.append({
				"agent_id": str(body.get("agent_id", "")),
				"fact_id": str(body.get("fact_id", "")),
				"form": str(body.get("form", "")),
				"turn": int(body.get("turn", 0)),
			})
	return result


static func _event_list(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for item in value:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


static func _confrontation_list(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for item in value:
		if item is not Dictionary:
			continue
		var body := item as Dictionary
		var also: Array[String] = []
		var raw_also: Variant = body.get("also_broken", [])
		if raw_also is Array:
			for fact_id in raw_also:
				also.append(str(fact_id))
		result.append({
			"turn": int(body.get("turn", 0)),
			"agent_id": str(body.get("agent_id", "")),
			"statement_id": str(body.get("statement_id", "")),
			"evidence_id": str(body.get("evidence_id", "")),
			"verdict": str(body.get("verdict", "")),
			"also_broken": also,
		})
	return result


static func _accusation(value: Variant) -> Dictionary:
	var body: Dictionary = value if value is Dictionary else {}
	return {
		"killer_ok": body.get("killer_ok", false) == true,
		"motive_ok": body.get("motive_ok", false) == true,
		"method_ok": body.get("method_ok", false) == true,
		"attempts": int(body.get("attempts", 0)),
	}
