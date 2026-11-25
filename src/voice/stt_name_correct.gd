class_name SttNameCorrect
extends RefCounted
## Правка имён после локального STT. Эвристика: одно явное совпадение со словарём дела.
## Короткие слова — не больше одной правки, длинные — до двух, и только при общем префиксе.
## Порог зафиксирован тестами: «пауло» → «Павла», «права» / «палку» / «пару» не трогаются.


const MAX_EDIT_SHORT := 1
const MAX_EDIT_LONG := 2
const SHORT_LIMIT := 4
const MIN_PREFIX := 2
const MIN_STEM := 4
const MIN_GAP := 1

const ENDINGS: PackedStringArray = [
	"ой", "ей", "ом", "ем", "ах", "ях", "ам", "ям", "ов", "ев", "ым", "им", "ью",
	"а", "я", "у", "ю", "е", "о", "ы", "и",
]

const DIGRAPHS: Array = [
	["shch", "щ"], ["sch", "щ"], ["yo", "ё"], ["zh", "ж"], ["kh", "х"],
	["ts", "ц"], ["ch", "ч"], ["sh", "ш"], ["yu", "ю"], ["ya", "я"], ["ye", "е"],
]

const LETTERS := {
	"a": "а", "b": "б", "c": "к", "d": "д", "e": "е", "f": "ф", "g": "г",
	"h": "х", "i": "и", "j": "й", "k": "к", "l": "л", "m": "м", "n": "н",
	"o": "о", "p": "п", "q": "к", "r": "р", "s": "с", "t": "т", "u": "у",
	"v": "в", "w": "в", "x": "кс", "y": "ы", "z": "з",
}


static func correct(text: String, case_data: CaseData, state: GameState) -> String:
	if case_data == null or text.strip_edges() == "":
		return text
	var entries := _entries(case_data, state)
	if entries.is_empty():
		return text
	var out: PackedStringArray = PackedStringArray()
	for token in text.split(" ", false):
		out.append(_correct_token(str(token), entries))
	return " ".join(out)


static func _entries(case_data: CaseData, state: GameState) -> Array:
	var seen := {}
	var entries: Array = []
	for agent in case_data.agents:
		_add_phrase(entries, seen, agent.name)
	if state != null:
		for evidence in case_data.evidence:
			if state.unlocked_evidence.has(evidence.id):
				_add_phrase(entries, seen, evidence.title)
	return entries


static func _add_phrase(entries: Array, seen: Dictionary, phrase: String) -> void:
	var clean := phrase.strip_edges()
	if clean == "":
		return
	_add_word(entries, seen, clean)
	for part in clean.split(" ", false):
		_add_word(entries, seen, str(part))


static func _add_word(entries: Array, seen: Dictionary, word: String) -> void:
	var display := word.strip_edges()
	var fold := display.to_lower()
	if fold == "" or seen.has(fold):
		return
	seen[fold] = true
	entries.append({"display": display, "fold": fold})


static func _correct_token(token: String, entries: Array) -> String:
	var peeled := _peel(token)
	var core := str(peeled["core"])
	if core == "":
		return token
	var folded := _to_cyrillic(core)
	var best_display := ""
	var best_dist := 99
	var second := 99
	for entry in entries:
		var dist := _distance(folded, str(entry["fold"]))
		if dist < 0:
			continue
		var display := str(entry["display"])
		if dist < best_dist:
			second = best_dist
			best_dist = dist
			best_display = display
		elif dist == best_dist and display != best_display:
			second = dist
			best_display = ""
		elif dist < second:
			second = dist
	if best_display == "":
		return token
	if second < 99 and best_dist + MIN_GAP > second:
		return token
	return "%s%s%s" % [str(peeled["lead"]), best_display, str(peeled["tail"])]


static func _distance(token: String, fold: String) -> int:
	if token == fold:
		return 0
	if _stem_hit(token, fold):
		return 1
	var limit := _max_edit(token.length())
	if limit <= 0 or absi(token.length() - fold.length()) > limit:
		return -1
	var dist := _levenshtein(token, fold)
	if dist <= 0 or dist > limit:
		return -1
	if _prefix_len(token, fold) < MIN_PREFIX:
		return -1
	return dist


static func _max_edit(length: int) -> int:
	if length <= 2:
		return 0
	if length <= SHORT_LIMIT:
		return MAX_EDIT_SHORT
	return MAX_EDIT_LONG


static func _stem_hit(token: String, fold: String) -> bool:
	if fold.contains(" ") or token.contains(" "):
		return false
	var stem := _stem(fold)
	if stem.length() < MIN_STEM or not token.begins_with(stem):
		return false
	var rest := token.substr(stem.length())
	return rest == "" or ENDINGS.has(rest)


static func _stem(fold: String) -> String:
	for ending in ENDINGS:
		var stem_len := fold.length() - ending.length()
		if stem_len >= MIN_STEM and fold.ends_with(ending):
			return fold.substr(0, stem_len)
	return fold


static func _prefix_len(left: String, right: String) -> int:
	var limit := mini(left.length(), right.length())
	var index := 0
	while index < limit and left.unicode_at(index) == right.unicode_at(index):
		index += 1
	return index


static func _levenshtein(left: String, right: String) -> int:
	var width := right.length() + 1
	var prev: Array[int] = []
	prev.resize(width)
	for column in width:
		prev[column] = column
	for row in left.length():
		var current: Array[int] = []
		current.resize(width)
		current[0] = row + 1
		var left_code := left.unicode_at(row)
		for column in right.length():
			var cost := 0 if left_code == right.unicode_at(column) else 1
			current[column + 1] = mini(mini(current[column] + 1, prev[column + 1] + 1), prev[column] + cost)
		prev = current
	return prev[width - 1]


static func _to_cyrillic(token: String) -> String:
	var lower := token.to_lower()
	if not _has_latin(lower):
		return lower
	var out := ""
	var index := 0
	while index < lower.length():
		var matched := false
		for pair in DIGRAPHS:
			var source := str(pair[0])
			if lower.substr(index, source.length()) == source:
				out += str(pair[1])
				index += source.length()
				matched = true
				break
		if matched:
			continue
		var piece := lower.substr(index, 1)
		out += str(LETTERS.get(piece, piece))
		index += 1
	return out


static func _has_latin(token: String) -> bool:
	for index in token.length():
		var code := token.unicode_at(index)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			return true
	return false


static func _peel(token: String) -> Dictionary:
	var start := 0
	var finish := token.length()
	while start < finish and not _is_letter(token.unicode_at(start)):
		start += 1
	while finish > start and not _is_letter(token.unicode_at(finish - 1)):
		finish -= 1
	return {
		"lead": token.substr(0, start),
		"core": token.substr(start, finish - start),
		"tail": token.substr(finish),
	}


static func _is_letter(code: int) -> bool:
	if code >= 65 and code <= 90:
		return true
	if code >= 97 and code <= 122:
		return true
	if code >= 0x0400 and code <= 0x04FF:
		return true
	return false
