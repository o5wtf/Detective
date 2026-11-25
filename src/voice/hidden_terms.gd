class_name HiddenTerms
extends RefCounted
## Названия ещё не открытых улик. Имена и факты пакета сюда не входят.


static func build(case_data: CaseData, state: GameState) -> PackedStringArray:
	var titles := PackedStringArray()
	if case_data == null:
		return titles
	for evidence in case_data.evidence:
		if state != null and state.unlocked_evidence.has(evidence.id):
			continue
		var title := evidence.title.strip_edges()
		if title != "":
			titles.append(title)
	return titles


static func mentioned(text: String, titles: PackedStringArray) -> bool:
	var spoken := _words(text)
	if spoken.is_empty():
		return false
	for title in titles:
		for piece in _words(title):
			if piece.length() < 5:
				continue
			var stem := piece.substr(0, 5)
			for word in spoken:
				if word.length() >= 5 and word.substr(0, 5) == stem:
					return true
	return false


static func _words(text: String) -> PackedStringArray:
	var words := PackedStringArray()
	var current := ""
	var lower := text.to_lower()
	for index in lower.length():
		var code := lower.unicode_at(index)
		if _is_letter(code):
			current += char(code)
		elif current != "":
			words.append(current)
			current = ""
	if current != "":
		words.append(current)
	return words


static func _is_letter(code: int) -> bool:
	if code >= 97 and code <= 122:
		return true
	if code == 0x0451:
		return true
	if code >= 0x0430 and code <= 0x044F:
		return true
	return false
