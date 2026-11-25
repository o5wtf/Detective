class_name SpeechJunk
extends RefCounted
## Пустое, только цифры, время, знаки или явный не-речевой ответ не отправляются персонажу.


const MARKERS: PackedStringArray = [
	"[music]",
	"[silence]",
	"[noise]",
	"unintelligible",
	"неразборчиво",
	"(тишина)",
	"no speech",
]


static func is_junk(raw: String) -> bool:
	var text := raw.strip_edges().to_lower()
	if text == "":
		return true
	for marker in MARKERS:
		if text == marker:
			return true
	for index in text.length():
		if _is_letter(text.unicode_at(index)):
			return false
	return true


## Доля слов расшифровки, которые уже есть в подсказке или брифинге.
const ECHO_SHARE := 0.75
const ECHO_MIN_WORDS := 6


static func is_echo(transcript: String, sources: PackedStringArray) -> bool:
	var known := {}
	for source in sources:
		for word in _words(source):
			if word.length() >= 4:
				known[word] = true
	var mine: PackedStringArray = PackedStringArray()
	for word in _words(transcript):
		if word.length() >= 4:
			mine.append(word)
	if mine.size() < ECHO_MIN_WORDS:
		return false
	var hits := 0
	for word in mine:
		if known.has(word):
			hits += 1
	return float(hits) / float(mine.size()) >= ECHO_SHARE


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
	if code >= 65 and code <= 90:
		return true
	if code >= 97 and code <= 122:
		return true
	if code == 0x0401 or code == 0x0451:
		return true
	if code >= 0x0410 and code <= 0x044F:
		return true
	return false
