class_name DialogueState
extends RefCounted
## История и резюме разговора с одним агентом.

var messages: Array[Dictionary] = []
var summary: String = ""
var summarized_count: int = 0


func recent(n: int = 6) -> Array[Dictionary]:
	if n <= 0 or messages.is_empty():
		return []
	if messages.size() <= n:
		return messages.duplicate(true)
	return messages.slice(messages.size() - n, messages.size())


## За окном из 6 последних реплик лежит не меньше 6 ещё не свёрнутых.
func needs_summary() -> bool:
	return maxi(0, messages.size() - 6 - summarized_count) >= 6


func append_message(role: String, text: String, turn: int, remark: String = "", evidence_id: String = "") -> void:
	var message := {
		"role": role,
		"text": text,
		"remark": remark,
		"turn": turn,
	}
	if evidence_id != "":
		message["evidence_id"] = evidence_id
	messages.append(message)


func to_dict() -> Dictionary:
	return {
		"messages": messages.duplicate(true),
		"summary": summary,
		"summarized_count": summarized_count,
	}


static func from_dict(data: Dictionary) -> DialogueState:
	var dialogue := DialogueState.new()
	dialogue.summary = str(data.get("summary", ""))
	dialogue.summarized_count = int(data.get("summarized_count", 0))
	var raw: Variant = data.get("messages", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				dialogue.messages.append((item as Dictionary).duplicate(true))
	return dialogue
