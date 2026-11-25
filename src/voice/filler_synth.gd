class_name FillerSynth
extends RefCounted
## Синтез междометия для голоса, которого нет в res://. Только модели Gemini, не ход.


const ATTEMPTS := 3
const PAUSE_CAP_S := 2.0

static var instant := false
static var pauses: Array[float] = []


static func ensure(voice: String, text: String, busy: bool, fetch: Callable) -> Dictionary:
	var tried := PackedStringArray()
	var empty := PackedByteArray()
	if busy or not fetch.is_valid():
		return {"ok": false, "pcm": empty, "tried": tried, "model": ""}
	var model := str(TtsQuota.choose(TtsQuota.now_unix()).get("model", ""))
	var hops := 0
	while hops < 4 and model != "" and not TtsQuota.is_chirp(model):
		hops += 1
		var key := TtsCache.key_for(model, voice, "", text)
		var cached := TtsCache.read(key)
		if not cached.is_empty():
			return {"ok": true, "pcm": cached, "tried": tried, "model": model}
		var attempt := 0
		var daily := false
		while attempt < ATTEMPTS:
			attempt += 1
			tried.append(model)
			var pending: Variant = fetch.call(model, voice, text)
			var result: Dictionary = {}
			if pending is Dictionary:
				result = pending
			else:
				result = await pending
			if result.get("ok", false):
				var pcm: PackedByteArray = result.get("pcm", empty)
				if pcm.is_empty():
					return {"ok": false, "pcm": empty, "tried": tried, "model": model}
				TtsCache.write(key, pcm)
				return {"ok": true, "pcm": pcm, "tried": tried, "model": model}
			var err := str(result.get("error", ""))
			if err == "quota_daily":
				TtsQuota.mark_exhausted(model, TtsQuota.now_unix())
				daily = true
				break
			if err != "rate_limited" and err != "quota_minute":
				return {"ok": false, "pcm": empty, "tried": tried, "model": model}
			if attempt >= ATTEMPTS:
				return {"ok": false, "pcm": empty, "tried": tried, "model": model}
			var pause := minf(float(result.get("retry_after", 1.0)), PAUSE_CAP_S)
			if pause < 0.0:
				pause = 0.0
			pauses.append(pause)
			if instant:
				continue
			await (Engine.get_main_loop() as SceneTree).create_timer(pause).timeout
		if not daily:
			return {"ok": false, "pcm": empty, "tried": tried, "model": model}
		var nxt := TtsQuota.next_open(model, TtsQuota.now_unix())
		if nxt == "" or TtsQuota.is_chirp(nxt):
			return {"ok": false, "pcm": empty, "tried": tried, "model": model}
		model = nxt
	return {"ok": false, "pcm": empty, "tried": tried, "model": model}
