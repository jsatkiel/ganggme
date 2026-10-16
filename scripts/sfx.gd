extends RefCounted
## Placeholder sounds generated in code (no audio files needed yet).

const RATE := 22050

static var _shot: AudioStreamWAV
static var _tick: AudioStreamWAV
static var _hurt: AudioStreamWAV


static func gunshot() -> AudioStreamWAV:
	if _shot == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var lp := 0.0
		var samples := PackedFloat32Array()
		for i in int(RATE * 0.35):
			var t := float(i) / RATE
			var noise := rng.randf_range(-1.0, 1.0)
			lp = lerpf(lp, noise, 0.35)
			var crack := noise * exp(-t * 60.0) * 0.7
			var body := lp * exp(-t * 14.0) * 0.9
			var thump := sin(TAU * 70.0 * t) * exp(-t * 20.0) * 0.8
			samples.append(crack + body + thump)
		_shot = _wav(samples)
	return _shot


static func hit_tick() -> AudioStreamWAV:
	if _tick == null:
		var samples := PackedFloat32Array()
		for i in int(RATE * 0.06):
			var t := float(i) / RATE
			samples.append(sin(TAU * 1700.0 * t) * exp(-t * 70.0) * 0.6)
		_tick = _wav(samples)
	return _tick


static func hurt() -> AudioStreamWAV:
	if _hurt == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var samples := PackedFloat32Array()
		for i in int(RATE * 0.2):
			var t := float(i) / RATE
			samples.append((sin(TAU * 110.0 * t) * 0.7 + rng.randf_range(-0.3, 0.3)) * exp(-t * 18.0))
		_hurt = _wav(samples)
	return _hurt


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
