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
