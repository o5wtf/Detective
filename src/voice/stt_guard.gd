class_name SttGuard
extends RefCounted
## Отдельный STT: мусор, эхо подсказки и название закрытой улики в ход не идут.


static func reject(text: String, case_data: CaseData, state: GameState, hint: String) -> bool:
	if SpeechJunk.is_junk(text):
		return true
	var sources := PackedStringArray()
	if hint.strip_edges() != "":
		sources.append(hint)
	if case_data != null and case_data.briefing.strip_edges() != "":
		sources.append(case_data.briefing)
	if SpeechJunk.is_echo(text, sources):
		return true
	return HiddenTerms.mentioned(text, HiddenTerms.build(case_data, state))
