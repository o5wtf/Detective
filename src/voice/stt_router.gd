class_name SttRouter
extends SttBackend
## gemini — облако. parakeet — локальный путь, который сам уходит в облако, если библиотеки нет.


var cloud: SttBackend
var local: LocalStt


func set_hint(text: String) -> void:
	if cloud != null and cloud.has_method("set_hint"):
		cloud.set_hint(text)


func transcribe(wav: PackedByteArray) -> Dictionary:
	if SettingsStore.load_current().stt_backend == "parakeet" and local != null:
		return await local.transcribe(wav)
	var started := Time.get_ticks_msec()
	var result := {"ok": false, "text": "", "error": "offline", "usage": {}}
	if cloud != null:
		result = await cloud.transcribe(wav)
	else:
		await (Engine.get_main_loop() as SceneTree).process_frame
	TurnTiming.note_stt("gemini", Time.get_ticks_msec() - started, "", -1)
	return result


func cancel_listen() -> void:
	if cloud != null:
		cloud.cancel_listen()
	if local != null:
		local.cancel_listen()
