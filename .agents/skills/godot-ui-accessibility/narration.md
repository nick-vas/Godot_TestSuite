# Narrating the world (godot-ui-accessibility reference)

Screen readers read controls, not the world. To describe objects, places and tutorials, speak through `DisplayServer`.
Tested core: `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Access/Narration.cs`; the research:
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/loud-and-clear-low-vision.md`.

- Turn on Project Settings > Audio > General > Text To Speech (`audio/general/text_to_speech`, off by default). Off,
  speech starts on the first call, and that line is late or lost (Android waits up to 1 s; Linux can drop it). `doctor`
  warns about this.
- On demand only. One assist action speaks what is focused (hovered, aimed at, held) and the same action stops it. Never
  speak on hover, grab or focus by itself, because it drowns out the game. Use a tap, not a toggle: players forget a
  toggle is on. Tutorial prompts are the exception and speak when they appear.
- Focus moving to something else stops a description (`DisplayServer.TtsStop()`) and does not start another.
- Order: state, name, short description ("hovering, star shades, sunglasses with star-shaped lenses"). The short,
  always-present parts come first, so players can stop early. Leave out lore and jokes, as web alt text does: players
  take them for clues, and shorter lines are spoken sooner.
- Duck music and effects from the tap until the line ends or is cancelled. The dip shows the tap was heard, even while
  the engine is still generating speech, and the return shows the line is over. Duck other audio; never pause or delay it.

  ```csharp
  long _line;   // the utterance in progress
  int _music;

  public override void _Ready()
  {
      _music = AudioServer.GetBusIndex("Music");
      DisplayServer.TtsSetUtteranceCallback(DisplayServer.TtsUtteranceEvent.Ended, Callable.From<long>(Done));
      DisplayServer.TtsSetUtteranceCallback(DisplayServer.TtsUtteranceEvent.Canceled, Callable.From<long>(Done));
  }

  void Say(string text)
  {
      string[] voices = DisplayServer.TtsGetVoicesForLanguage(TranslationServer.GetLocale().Split('_')[0]);
      if (voices.Length == 0) return;   // no speech engine: show the text instead
      _line++;
      AudioServer.SetBusVolumeDb(_music, -12);   // from the tap, not the first word
      DisplayServer.TtsSpeak(text, voices[0], utteranceId: _line, interrupt: true);
  }

  void Done(long id) { if (id == _line) AudioServer.SetBusVolumeDb(_music, 0); }   // a replaced line reports too
  ```
- OS speech is not positional, so also play a short cue from an `AudioStreamPlayer3D` (or `2D`) at the object. Its
  direction and loudness say where the object is.
- More channels: a short vibration (`Input.StartJoyVibration`) when the cursor enters a new area or the hand reaches
  something usable; an outline on interactable and important static objects in a colour that contrasts with the scene
  (the contrast matters more than the hue); named areas placed by hand, announced while aiming and again on arrival.
- The mode can be turned on without sight, by a gesture or button press that needs no menu, and the game says how at
  first start.
