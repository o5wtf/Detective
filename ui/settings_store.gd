class_name SettingsStore
extends RefCounted
## user://config.cfg. Ключ хранится в файле настроек и не печатается.

const PATH := "user://config.cfg"

var provider: String = "gemini"
var api_key: String = ""
var dialogue_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var text_scale: float = 1.0
## Строка времени хода на допросе. Включена, чтобы замер был виден без отдельной настройки.
var timing_debug: bool = true
## Системная озвучка реплик. Выключена, пока игрок сам её не включит.
var voice_enabled: bool = false
## system | gemini. По умолчанию системный голос, без подмены при сбое Gemini.
var voice_engine: String = "system"
## Модель Google TTS. Цепочка идёт вниз от выбранной.
var tts_model: String = "gemini-3.8-flash-lite-tts"
## При суточной квоте переходить к следующей модели вниз по списку.
var tts_auto: bool = true
## JSON сервисного аккаунта Cloud Text-to-Speech. В логи не пишется.
var chirp_key: String = ""
## Интонация синтеза. Включена, пока игрок её не выключит.
var voice_intonation: bool = true
## Голосовой ввод. Выключен, пока игрок сам его не включит.
var mic_enabled: bool = false
## push_to_talk | hands_free. По умолчанию удержание кнопки.
var mic_mode: String = "push_to_talk"
## Пауза тишины, после которой фраза уходит на распознавание.
var mic_pause_ms: int = 700
## Число давления рядом с ремаркой. В обычной игре скрыто.
var developer: bool = false
## gemini | system. По умолчанию облачное распознавание.
var stt_backend: String = "gemini"

static var _cached: SettingsStore
static var _cached_hash: String = ""
static var _cached_env: String = ""


static func invalidate_cache() -> void:
	_cached = null
	_cached_hash = ""
	_cached_env = ""
	LLMConfig.invalidate_cache()


static func load_current() -> SettingsStore:
	var env := OS.get_environment("GEMINI_API_KEY")
	var digest := _file_hash()
	if _cached != null and digest == _cached_hash and env == _cached_env:
		return _cached.detached()
	var store := SettingsStore.new()
	var config := LLMConfig.load_settings()
	store.provider = config.provider
	store.api_key = config.api_key
	store.dialogue_model = config.dialogue_model
	var file := ConfigFile.new()
	var loaded := file.load(PATH) == OK
	if loaded and file.has_section_key("ui", "text_scale"):
		store.text_scale = clampf(float(file.get_value("ui", "text_scale")), 0.85, 1.4)
	if loaded and file.has_section_key("llm", "timing_debug"):
		store.timing_debug = bool(file.get_value("llm", "timing_debug"))
	if loaded and file.has_section_key("voice", "enabled"):
		store.voice_enabled = bool(file.get_value("voice", "enabled"))
	if loaded and file.has_section_key("voice", "engine"):
		store.voice_engine = canonical_engine(str(file.get_value("voice", "engine")))
	if loaded and file.has_section_key("voice", "tts_model"):
		store.tts_model = str(file.get_value("voice", "tts_model"))
	if loaded and file.has_section_key("voice", "tts_auto"):
		store.tts_auto = bool(file.get_value("voice", "tts_auto"))
	if loaded and file.has_section_key("voice", "chirp_key"):
		store.chirp_key = str(file.get_value("voice", "chirp_key"))
	if loaded and file.has_section_key("voice", "intonation"):
		store.voice_intonation = bool(file.get_value("voice", "intonation"))
	if loaded and file.has_section_key("mic", "enabled"):
		store.mic_enabled = bool(file.get_value("mic", "enabled"))
	if loaded and file.has_section_key("mic", "mode"):
		store.mic_mode = "hands_free" if str(file.get_value("mic", "mode")) == "hands_free" else "push_to_talk"
	if loaded and file.has_section_key("mic", "pause_ms"):
		store.mic_pause_ms = clampi(int(file.get_value("mic", "pause_ms")), 400, 2000)
	if loaded and file.has_section_key("llm", "developer"):
		store.developer = bool(file.get_value("llm", "developer"))
	store.stt_backend = "gemini"
	if loaded and str(file.get_value("mic", "stt", "gemini")) == "system":
		file.set_value("mic", "stt", "gemini")
		file.save(PATH)
		invalidate_cache()
	_cached = store
	_cached_hash = _file_hash()
	_cached_env = env
	return store.detached()


func detached() -> SettingsStore:
	var copy := SettingsStore.new()
	copy.provider = provider
	copy.api_key = api_key
	copy.dialogue_model = dialogue_model
	copy.text_scale = text_scale
	copy.timing_debug = timing_debug
	copy.voice_enabled = voice_enabled
	copy.voice_engine = voice_engine
	copy.tts_model = tts_model
	copy.tts_auto = tts_auto
	copy.chirp_key = chirp_key
	copy.voice_intonation = voice_intonation
	copy.mic_enabled = mic_enabled
	copy.mic_mode = mic_mode
	copy.mic_pause_ms = mic_pause_ms
	copy.developer = developer
	copy.stt_backend = stt_backend
	return copy


static func _file_hash() -> String:
	if not FileAccess.file_exists(PATH):
		return ""
	return FileAccess.get_sha256(PATH)


static func canonical_engine(engine: String) -> String:
	return "gemini" if engine.strip_edges() == "gemini" else "system"


static func save_values(provider: String, api_key: String, dialogue_model: String, text_scale: float, timing_debug: Variant = null, voice_enabled: Variant = null, voice_engine: Variant = null, voice_intonation: Variant = null, mic_enabled: Variant = null, mic_mode: Variant = null, stt_backend: Variant = null, stt_offline: Variant = null, tts_model: Variant = null, tts_auto: Variant = null, chirp_key: Variant = null, mic_pause_ms: Variant = null, developer: Variant = null) -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("llm", "provider", provider)
	file.set_value("llm", "api_key", api_key)
	var model := LLMConfig.canonical_model(dialogue_model)
	file.set_value("llm", "dialogue_model", model)
	file.set_value("llm", "summary_model", model)
	file.set_value("llm", "settings_version", LLMConfig.SETTINGS_VERSION)
	file.set_value("ui", "text_scale", clampf(text_scale, 0.85, 1.4))
	if timing_debug != null:
		file.set_value("llm", "timing_debug", bool(timing_debug))
	if voice_enabled != null:
		file.set_value("voice", "enabled", bool(voice_enabled))
	if voice_engine != null:
		file.set_value("voice", "engine", canonical_engine(str(voice_engine)))
	if tts_model != null:
		file.set_value("voice", "tts_model", str(tts_model))
	if tts_auto != null:
		file.set_value("voice", "tts_auto", bool(tts_auto))
	if chirp_key != null:
		file.set_value("voice", "chirp_key", str(chirp_key))
	if voice_intonation != null:
		file.set_value("voice", "intonation", bool(voice_intonation))
	if mic_enabled != null:
		file.set_value("mic", "enabled", bool(mic_enabled))
	if mic_mode != null:
		file.set_value("mic", "mode", "hands_free" if str(mic_mode) == "hands_free" else "push_to_talk")
	if mic_pause_ms != null:
		file.set_value("mic", "pause_ms", clampi(int(mic_pause_ms), 400, 2000))
	if developer != null:
		file.set_value("llm", "developer", bool(developer))
	if stt_backend != null:
		file.set_value("mic", "stt", "gemini")
	invalidate_cache()
	file.save(PATH)


static func remember_thinking(model: String, level: String, role: String = "dialogue") -> void:
	if not LLMConfig.is_dialogue_model(model) and role == "dialogue":
		return
	if model.strip_edges() == "":
		return
	var file := ConfigFile.new()
	file.load(PATH)
	var accepted := _thinking_map(str(file.get_value("llm", "thinking_accepted", "")))
	accepted["%s|%s" % [model, role]] = level
	file.set_value("llm", "thinking_accepted", _thinking_text(accepted))
	invalidate_cache()
	file.save(PATH)


static func load_thinking() -> Dictionary:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return {}
	return _thinking_map(str(file.get_value("llm", "thinking_accepted", "")))


static func _thinking_map(raw: String) -> Dictionary:
	var accepted := {}
	for piece in raw.split(",", false):
		var pair := piece.split("=", true, 1)
		if pair.size() != 2:
			continue
		var key := pair[0].strip_edges()
		var level := pair[1].strip_edges()
		if not key.contains("|") or level == "":
			continue
		accepted[key] = level
	return accepted


static func _thinking_text(accepted: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key in accepted.keys():
		parts.append("%s=%s" % [str(key), str(accepted[key])])
	parts.sort()
	return ",".join(parts)


static func has_playable_key() -> bool:
	var store := load_current()
	return store.provider == "mock" or store.api_key.strip_edges() != ""
