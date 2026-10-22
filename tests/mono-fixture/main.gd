extends Node
# Measures the mono option godot-audio describes: AudioEffectStereoEnhance with pan_pullout 0 on the Master bus, switched
# with set_bus_effect_enabled. For a tone in the left channel only, both channels, and both in opposite phase, it prints
# the RMS of each output channel with the effect off and on, read back with an AudioEffectCapture after it:
#   @@mono <signal> <on|off> <left rms> <right rms>

func _ready() -> void:
	var enhance := AudioEffectStereoEnhance.new()
	enhance.pan_pullout = 0.0
	AudioServer.add_bus_effect(0, enhance)
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, capture)
	var player := AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100
	generator.buffer_length = 0.05  # short, so a new signal reaches the output quickly
	player.stream = generator
	add_child(player)
	await get_tree().process_frame
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var phase := 0.0
	for signal_name in ["left", "centre", "opposite"]:
		for enabled in [false, true]:
			AudioServer.set_bus_effect_enabled(0, 0, enabled)
			var l := 0.0
			var r := 0.0
			var n := 0
			var skipped := 0
			while n < 8820:  # 0.2 s measured, after 0.15 s for the change and the new signal to reach the output
				while playback.get_frames_available() > 0:
					phase += 440.0 / 44100.0
					var s := sin(phase * TAU) * 0.5
					match signal_name:
						"left": playback.push_frame(Vector2(s, 0.0))
						"centre": playback.push_frame(Vector2(s, s))
						_: playback.push_frame(Vector2(s, -s))
				await get_tree().process_frame
				for v in capture.get_buffer(capture.get_frames_available()):
					if skipped < 6615:
						skipped += 1
						continue
					l += v.x * v.x
					r += v.y * v.y
					n += 1
			print("@@mono %s %s %.4f %.4f" % [signal_name, "on" if enabled else "off", sqrt(l / max(n, 1)), sqrt(r / max(n, 1))])
	get_tree().quit()
