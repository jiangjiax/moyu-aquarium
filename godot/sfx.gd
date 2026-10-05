class_name Sfx
extends RefCounted
## 音效：直接用代码合成 PCM，不打包音频文件。和 pixel_art.gd 一个思路——
## 几十毫秒的小声音，为它找素材、管版权不划算。
##
## 声音要跟画面一个调子：短、软、低频为主，挂在桌面上响一下不吓人。

const RATE := 22050

static var _cache := {}


## 新鱼入水：「啵」一声（正弦从低往高扫，像气泡破掉）+ 一小截水花噪声，
## 尾巴上再冒两个小气泡音
static func splash() -> AudioStreamWAV:
	if _cache.has("splash"):
		return _cache["splash"]
	var n := int(RATE * 0.55)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		# 水花：低通过的白噪声，快起快落
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
		v += lp * 0.9 * exp(-t / 0.07) * minf(t / 0.004, 1.0)
		# 主「啵」：180 → 620 Hz，80 ms 扫完
		var k := clampf(t / 0.08, 0.0, 1.0)
		ph += TAU * lerpf(180.0, 620.0, k * k) / RATE
		v += sin(ph) * 0.55 * exp(-t / 0.09) * minf(t / 0.003, 1.0)
		# 两个跟在后面的小气泡
		v += _blip(t - 0.17, 520.0, 980.0, 0.05) * 0.22
		v += _blip(t - 0.27, 700.0, 1300.0, 0.04) * 0.16
		buf[i] = v
	var wav := _to_wav(buf)
	_cache["splash"] = wav
	return wav


## 一个扫频的小气泡音，t < 0 时不响
static func _blip(t: float, f0: float, f1: float, dur: float) -> float:
	if t < 0.0 or t > dur * 4.0:
		return 0.0
	var k := clampf(t / dur, 0.0, 1.0)
	# 频率线性扫，相位按积分算，扫频时不会咔哒
	var ph := TAU * (f0 * t + (f1 - f0) * 0.5 * dur * k * k)
	return sin(ph) * exp(-t / (dur * 0.8)) * minf(t / 0.002, 1.0)


static func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
