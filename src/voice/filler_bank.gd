class_name FillerBank
extends RefCounted
## Короткие междометия, пока персонаж ещё не ответил.


const FILLER_DELAY_MS := 500
const DIRECTORY := "res://assets/voice/fillers"

static var delay_ms := -1
static var last_line := ""


static func delay() -> int:
	if delay_ms >= 0:
		return delay_ms
	return FILLER_DELAY_MS


static func standard_lines() -> PackedStringArray:
	return PackedStringArray([
		GameLanguage.text("filler_hm"),
		GameLanguage.text("filler_nu"),
		GameLanguage.text("filler_sekundu"),
	])


static func lines_for(agent: CaseData.Agent) -> PackedStringArray:
	var custom := PackedStringArray()
	if agent != null:
		for line in agent.filler_lines:
			var text := line.strip_edges()
			if text == "":
				continue
			custom.append(text)
			if custom.size() == 3:
				break
	if not custom.is_empty():
		return custom
	return standard_lines()


static func pick(lines: PackedStringArray) -> String:
	if lines.is_empty():
		return ""
	var choice := lines[0]
	if lines.size() > 1:
		var start := 0
		for index in lines.size():
			if lines[index] == last_line:
				start = (index + 1) % lines.size()
				break
		choice = lines[start]
	last_line = choice
	return choice


static func builtin_path(voice: String, text: String) -> String:
	var slug := ""
	var standards := standard_lines()
	var files := PackedStringArray(["hm", "nu", "sekundu"])
	for index in standards.size():
		if standards[index] == text and index < files.size():
			slug = files[index]
			break
	var folder := voice.strip_edges().to_lower()
	if slug == "" or folder == "":
		return ""
	var path := "%s/%s/%s.wav" % [DIRECTORY, folder, slug]
	if FileAccess.file_exists(path):
		return path
	return ""


static func allowed() -> bool:
	var store := SettingsStore.load_current()
	if not store.voice_enabled or not store.fillers:
		return false
	if store.voice_engine != "gemini":
		return false
	return not TtsQuota.is_chirp(_current_model())


static func controls_enabled() -> bool:
	var store := SettingsStore.load_current()
	if store.voice_engine != "gemini":
		return false
	return not TtsQuota.is_chirp(_current_model())


static func _current_model() -> String:
	return str(TtsQuota.choose(TtsQuota.now_unix()).get("model", ""))
