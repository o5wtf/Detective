class_name LLMConfig
extends RefCounted
## Ключ и модели. Ключ не пишется в логи.
## Порядок ключа: user://config.cfg, затем GEMINI_API_KEY, затем res://config/dev.cfg только в отладочной сборке.

const SETTINGS_VERSION := 12
const DEFAULT_DIALOGUE_MODEL := "gemini-3.5-flash-lite"
const DIALOGUE_MODELS: PackedStringArray = [
	"gemini-3.5-flash-lite",
	"gemini-3.1-flash-lite",
	"gemini-3.6-flash",
]
const DEFAULT_THINKING := "MINIMAL"
## Выход с запасом: при 800 токенах ответ обрывался, когда рассуждения занимали 639.
const REPLY_MAX_OUTPUT_TOKENS := 16384

var provider: String = "gemini"
var api_key: String = ""
var key_source: String = "none"
var dialogue_model: String = DEFAULT_DIALOGUE_MODEL
var summary_model: String = DEFAULT_DIALOGUE_MODEL
var thinking_level: String = DEFAULT_THINKING
var timeout_s: float = 45.0
var ping_timeout_s: float = 32.0
var min_interval_s: float = 0.0
var summary_after_reply: bool = true
var local_fixes: bool = true


static func live_smoke_enabled(env_key: String) -> bool:
	return env_key.strip_edges() != ""


static func is_dialogue_model(model: String) -> bool:
	return DIALOGUE_MODELS.has(model.strip_edges())


static func canonical_model(model: String) -> String:
	var name := model.strip_edges()
	if is_dialogue_model(name):
		return name
	return DEFAULT_DIALOGUE_MODEL


static var _cached: LLMConfig
static var _cached_hash: String = ""
static var _cached_env: String = ""


static func invalidate_cache() -> void:
	_cached = null
	_cached_hash = ""
	_cached_env = ""


static func load_settings() -> LLMConfig:
	var env := OS.get_environment("GEMINI_API_KEY")
	var digest := _file_hash()
	if _cached != null and digest == _cached_hash and env == _cached_env:
		return _cached.detached()
	_migrate_saved_settings()
	var user_text := _read_text("user://config.cfg")
	var debug := OS.is_debug_build()
	var dev_text := _read_text("res://config/dev.cfg") if debug else ""
	var config := from_sources(user_text, env, dev_text, debug)
	config.dialogue_model = canonical_model(config.dialogue_model)
	config.summary_model = config.dialogue_model
	_cached = config
	_cached_hash = _file_hash()
	_cached_env = env
	return config.detached()


func detached() -> LLMConfig:
	var copy := LLMConfig.new()
	copy.provider = provider
	copy.api_key = api_key
	copy.key_source = key_source
	copy.dialogue_model = dialogue_model
	copy.summary_model = summary_model
	copy.thinking_level = thinking_level
	copy.timeout_s = timeout_s
	copy.ping_timeout_s = ping_timeout_s
	copy.min_interval_s = min_interval_s
	copy.summary_after_reply = summary_after_reply
	copy.local_fixes = local_fixes
	return copy


static func from_sources(user_text: String, env_key: String, dev_text: String, debug: bool) -> LLMConfig:
	var config := LLMConfig.new()
	var user := _section(user_text)
	var dev := _section(dev_text) if debug else {}
	config.provider = _first_string(user, dev, "provider", "gemini")
	config.dialogue_model = _first_string(user, dev, "dialogue_model", DEFAULT_DIALOGUE_MODEL)
	config.summary_model = config.dialogue_model
	config.thinking_level = _thinking_level(_first_string(user, dev, "thinking_level", DEFAULT_THINKING))
	config.timeout_s = _first_number(user, dev, "timeout_s", 45.0)
	config.ping_timeout_s = _first_number(user, dev, "ping_timeout_s", 32.0)
	config.min_interval_s = 0.0
	config.summary_after_reply = _first_bool(user, dev, "summary_after_reply", true)
	config.local_fixes = _first_bool(user, dev, "local_fixes", true)
	var user_key := str(user.get("api_key", "")).strip_edges()
	var env := env_key.strip_edges()
	var dev_key := str(dev.get("api_key", "")).strip_edges()
	if user_key != "":
		config.api_key = user_key
		config.key_source = "user"
	elif env != "":
		config.api_key = env
		config.key_source = "env"
	elif debug and dev_key != "":
		config.api_key = dev_key
		config.key_source = "dev"
	return config


static func create_client(config: LLMConfig) -> LLMClient:
	if config.provider == "mock":
		return MockLLMClient.new()
	var client := GeminiClient.new()
	client.apply_config(config)
	return client


static func _migrate_saved_settings() -> void:
	var path := "user://config.cfg"
	if not FileAccess.file_exists(path):
		return
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	var changed := false
	var model := str(file.get_value("llm", "dialogue_model", "")).strip_edges()
	if model != "" and not is_dialogue_model(model):
		file.set_value("llm", "dialogue_model", DEFAULT_DIALOGUE_MODEL)
		file.set_value("llm", "summary_model", DEFAULT_DIALOGUE_MODEL)
		changed = true
	var version := int(file.get_value("llm", "settings_version", 0))
	if version < SETTINGS_VERSION:
		if not file.has_section_key("voice", "enabled"):
			file.set_value("voice", "enabled", false)
		if not file.has_section_key("voice", "engine"):
			file.set_value("voice", "engine", "system")
		elif str(file.get_value("voice", "engine", "")) != "gemini":
			file.set_value("voice", "engine", "system")
		if not file.has_section_key("voice", "intonation"):
			file.set_value("voice", "intonation", true)
		if not file.has_section_key("mic", "enabled"):
			file.set_value("mic", "enabled", false)
		if not file.has_section_key("mic", "mode"):
			file.set_value("mic", "mode", "push_to_talk")
		if not file.has_section_key("mic", "stt") or str(file.get_value("mic", "stt", "")) == "system":
			file.set_value("mic", "stt", "gemini")
		if file.has_section_key("mic", "stt_offline"):
			file.erase_section_key("mic", "stt_offline")
		var engine := str(file.get_value("voice", "engine", "system"))
		if version < 9 and (engine == "gemini" or not file.has_section_key("voice", "tts_model")):
			file.set_value("voice", "tts_model", "gemini-3.8-flash-lite-tts")
		elif not file.has_section_key("voice", "tts_model"):
			file.set_value("voice", "tts_model", "gemini-3.8-flash-lite-tts")
		if version < 9 and (engine == "gemini" or not file.has_section_key("voice", "tts_auto")):
			file.set_value("voice", "tts_auto", true)
		elif not file.has_section_key("voice", "tts_auto"):
			file.set_value("voice", "tts_auto", true)
		if not file.has_section_key("mic", "pause_ms"):
			file.set_value("mic", "pause_ms", 700)
		if not file.has_section_key("llm", "developer"):
			file.set_value("llm", "developer", false)
		file.set_value("llm", "settings_version", SETTINGS_VERSION)
		changed = true
	if changed:
		invalidate_cache()
		file.save(path)


static func _file_hash() -> String:
	var path := "user://config.cfg"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


static func _thinking_level(raw: String) -> String:
	var level := raw.strip_edges().to_upper()
	if level == "MINIMAL" or level == "LOW":
		return level
	return DEFAULT_THINKING


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func _section(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var file := ConfigFile.new()
	if file.parse(text) != OK:
		return {}
	var values := {}
	if not file.has_section("llm"):
		return values
	for key in file.get_section_keys("llm"):
		values[key] = file.get_value("llm", key)
	return values


static func _first_string(user: Dictionary, dev: Dictionary, key: String, fallback: String) -> String:
	if user.has(key) and str(user[key]).strip_edges() != "":
		return str(user[key]).strip_edges()
	if dev.has(key) and str(dev[key]).strip_edges() != "":
		return str(dev[key]).strip_edges()
	return fallback


static func _first_number(user: Dictionary, dev: Dictionary, key: String, fallback: float) -> float:
	if user.has(key):
		return float(user[key])
	if dev.has(key):
		return float(dev[key])
	return fallback


static func _first_bool(user: Dictionary, dev: Dictionary, key: String, fallback: bool) -> bool:
	if user.has(key):
		return bool(user[key])
	if dev.has(key):
		return bool(dev[key])
	return fallback
