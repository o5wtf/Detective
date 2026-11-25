class_name SherpaNative
extends RefCounted
## Android-плагин sherpa-onnx. На Linux и в редакторе библиотеки нет:
## available() ложно, и локальный STT уходит в облако с причиной no_native.
## Модель с диска читает сам плагин, в фоновом потоке. Язык ему не передаётся.


const PLUGIN_NAME := "SherpaOnnx"


func available() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton(PLUGIN_NAME)


func load_model(dir: String) -> String:
	var plugin := _plugin()
	if plugin == null:
		return "no_native"
	var absolute := dir
	if dir.begins_with("user://") or dir.begins_with("res://"):
		absolute = ProjectSettings.globalize_path(dir)
	return str(plugin.call("start_load", absolute))


func load_state() -> String:
	var plugin := _plugin()
	if plugin == null:
		return "no_native"
	return str(plugin.call("load_state"))


func unload() -> void:
	var plugin := _plugin()
	if plugin != null:
		plugin.call("unload")


func transcribe_wav(wav: PackedByteArray) -> Dictionary:
	var plugin := _plugin()
	if plugin == null:
		return {"text": "", "crash": true}
	var raw := str(plugin.call("transcribe_wav", wav))
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return {
			"text": str(parsed.get("text", "")),
			"crash": bool(parsed.get("crash", false)),
		}
	return {"text": "", "crash": true}


func _plugin() -> Object:
	if not available():
		return null
	return Engine.get_singleton(PLUGIN_NAME)
