---
name: godot-mobile-web
description: Use when a Godot game targets phones, tablets or browsers: touch controls, notches and safe areas, screen sizes and orientation, battery and pausing, Android or iOS exports, web builds, hosting on itch.io or GitHub Pages, or testing in Chrome, Firefox and Edge.
---

# Phones, tablets and browsers

Measured on Godot 4.7.2 (Android and web exports built and run here; no iOS, no Android device); sources and the
measurements: `${CLAUDE_PLUGIN_ROOT}/docs/mobile-web.md`.

## 1. What C# can target in Godot 4.7

| Platform | C# | Notes |
|---|---|---|
| Web | **no** | the export stops: "Exporting to Web is currently not supported in Godot 4 when using C#/.NET". A web build needs a GDScript game (or a GDScript demo). `doctor` fails a C# project with a Web preset |
| Android | experimental | use a **Gradle** build (AAB for Google Play): 39 MB here on net8.0. The prebuilt template needs `net9.0` and made a 102 MB APK full of static `.a` files. `doctor` fails the prebuilt route on net8.0 |
| iOS | experimental | export only on macOS with Xcode; Apple wants the iOS 26 SDK (Xcode 26) for uploads since April 2026 |

## 2. Every screen: `layout`

`layout.json` in the project turns on the `layout` runner. It lays out each scene, headless, on a portrait phone
(1080x2400), a landscape phone, a tablet and a 3440x1440 ultrawide, and fails on controls that are:
- **off-screen**;
- **unsafe-area**: under the notch, the status bar or the home indicator;
- **small-target**: under 48 dp on touch (Android 48 dp, Apple 44 pt), under 24 CSS px with a mouse (WCAG 2.2).

```json
{ "scenes": ["res://ui/menu.tscn", "res://ui/hud.tscn"],
  "profiles": ["phone_portrait", "phone_landscape", "tablet", "ultrawide", "foldable:1812x2176@374:touch:insets=0,96,0,48"] }
```

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Runners layout -Json -Quiet
```

A UI designed at 1280x720 and shown on a portrait phone shrinks: a 64 px button became 21 dp. Design phone UI in
portrait (or choose the base size for the orientation the game ships in).

**Safe areas.** `DisplayServer.GetDisplaySafeArea()` works on Android and iOS only; it returns the whole window
elsewhere, in **screen** pixels. `GetDisplayCutouts()` is Android only, and browsers report no notch at all. Keep the UI in
a `SafeArea` autoload's rectangle. The runner calls its `SetInsets` with each profile's notch, so a game that uses one
passes, and one that ignores the notch is caught. `--safe-area=0,128,0,66` after `--` fakes a notch on desktop.

```csharp
public partial class SafeArea : Node   // autoload named SafeArea
{
    [Signal] public delegate void ChangedEventHandler();
    private Rect2I _override;

    public void SetInsets(int left, int top, int right, int bottom)   // window pixels; zeros remove the fake notch
    {
        Vector2I window = GetTree().Root.Size;
        _override = left + top + right + bottom > 0 ? new Rect2I(left, top, window.X - left - right, window.Y - top - bottom) : new Rect2I();
        EmitSignal(SignalName.Changed);
    }

    public Rect2I WindowRect()
    {
        var window = new Rect2I(Vector2I.Zero, GetTree().Root.Size);
        if (_override.HasArea()) return _override;
        if (!OS.HasFeature("mobile")) return window;
        Rect2I safe = DisplayServer.GetDisplaySafeArea();   // screen pixels
        safe.Position -= DisplayServer.WindowGetPosition();
        return safe.Intersection(window);
    }

    // What Controls use: the safe rectangle after stretching.
    public Rect2 CanvasRect() => GetTree().Root.GetFinalTransform().AffineInverse() * new Rect2(WindowRect().Position, WindowRect().Size);
}
```

A full-rect `MarginContainer` sets its four `margin_*` theme constants from `CanvasRect()` on `Changed` (and on
`Root.SizeChanged`). The GDScript version is in the kit's `tests/layout-fixture`; the C# `SafeArea` and `SafeMargins` are in `docs/mobile-web.md`.

**Orientation.** The default is landscape (`display/window/handheld/orientation`; an exported APK said
`screenOrientation=0`). A portrait game must set it, and also its viewport size: Godot does not swap them.

## 3. Touch

- `input_devices/pointing/emulate_mouse_from_touch` is on by default: the **first** finger also arrives as a mouse,
  so mouse-only code works with one finger and never with two.
- Track fingers by `InputEventScreenTouch.Index` and `InputEventScreenDrag.Index`.
- Godot 4.7's buttons track a touch index, so two `Button`s can be held at once, for example move and jump
  (changelog GH-110893; not tried on a device).
- `TouchScreenButton` (a Node2D with an `Action`, `PassbyPress`, and shown on touchscreens only) still suits on-screen
  game controls.
- Virtual stick: write a Control that takes one touch index inside its rectangle and maps the offset to
  `Input.ActionPress(action, strength)`. Or use MarcoFazioRandom's MIT "Virtual Joystick" add-on (record it in `assets.json`).
- Android gestures (`InputEventMagnifyGesture`, `InputEventPanGesture`) need `enable_pan_and_scale_gestures`. Turn on
  `emulate_touch_from_mouse` to try touch code with a mouse.
- Test touch like any input (`godot-input`): `Input.ParseInputEvent(new InputEventScreenTouch { Index = 1, Position = p,
  Pressed = true })`, then wait a frame. Use two indices for two fingers.
- Touch targets: 48 dp minimum (above). Xbox's accessibility guidelines ask for 15 mm on phones (`godot-ui-accessibility`).
  `ScreenGetDpi()` on Android is a bucket (160, 240, 320, 480...), so dp is exact and millimetres are approximate.

## 4. Battery, heat and the app lifecycle

- Cap the frame rate (`application/run/max_fps`, 30 for slow games) rather than relying on `low_processor_mode`, which
  only helps apps that rarely redraw.
- `display/window/energy_saving/keep_screen_on` is on by default; turn it off for idle games and menus.
- Android frame pacing (Swappy) is on by default.
- Godot 4.7 has no thermal API (Android's thermal headroom needs a plugin).
- **Save on `NotificationApplicationPaused`** (Android and iOS). iOS gives about 5 seconds and then kills the app
  (`godot-saves`). Pause the game there and resume on `NotificationApplicationResumed`.
- `OS.GetMemoryInfo()` gives physical, free and available memory for telemetry. Godot has no memory budget API.

## 5. Android export

- **Tools:** JDK 17 or newer (21 worked), and the SDK's `platform-tools`, `build-tools;35.0.1` and `platforms;android-35`.
  The NDK and CMake were not needed for APK or Gradle builds.
- **Editor settings:** `ANDROID_HOME` and `JAVA_HOME` only seed **new** editor settings. An existing
  `editor_settings-4.7.tres` wins ("Invalid Android SDK path"). In CI, point `XDG_CONFIG_HOME` at an empty folder (Linux),
  or write `export/android/android_sdk_path` and `java_sdk_path` into it. Set `DOTNET_NOLOGO=1`: .NET's first-run banner
  was read as the target framework.
- **Required:** `rendering/textures/vram_compression/import_etc2_astc=true` (without it the export refuses), and a
  project icon (without one, the build uses Godot's icon). `doctor` checks both.
- **Signing:** `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `_USER` and `_PASSWORD` (the keystore and key passwords must
  match). Google Play wants an AAB, which needs a Gradle build: `--install-android-build-template`, then
  `gradle_build/use_gradle_build=true` and `gradle_build/export_format=1`. It uses about 1.2 GB of Gradle cache, and
  Maven Central can answer 429 on shared runners, so retry once.
- **Google Play:** new apps and updates must target API 36 since 31 August 2026; 4.7's default target is 36, minimum 24.
  From 1 February 2027, updates must support 16 KB memory pages. 4.7.2's libraries passed `zipalign -c -P 16`.
- **Launch tests** need a device or an emulator with KVM (GitHub's Linux runners have it); none ran here.

## 6. iOS, in concept

macOS and Xcode only. `application/min_ios_version` defaults to 15.0. The preset's `privacy/*` options fill
`PrivacyInfo.xcprivacy`, so declare what the game collects (`godot-legal`). The home indicator and status bar are hidden
by default. `ScreenSetOrientation` works only when the orientation setting is sensor.

## 7. Web builds (GDScript)

- **Renderer:** Compatibility only (WebGL 2); Forward+ and Mobile do not run, and there is no WebGPU. Safari has WebGL 2
  issues.
- **Threads:** keep Thread Support **off** (the default since 4.3). A threads build shows "missing features: Cross-Origin
  Isolation, SharedArrayBuffer" unless the server sends COOP and COEP headers, and itch.io and GitHub Pages send none.
  The PWA option "Ensure Cross Origin Isolation Headers" works around it, but needed a second reload here. `doctor`
  warns about threads builds.
- **Size:** the engine alone is 38 MB, 9.9 MB gzipped (GitHub Pages compresses; itch.io does not). `export` reports
  `exports[].web` (`rawMb`, `gzipMb`). Web portals cap downloads; CrazyGames, for example, allows 50 MB, or 20 MB for
  its mobile homepage.
- **Export outside the project.** An export into `res://build/...` gets imported, and the next export packs it (the
  `.pck` grew tenfold here). `export` adds a `.gdignore` to an output folder inside the project; `doctor` warns about
  presets that export into it.
- **Saves:** `user://` is IndexedDB, and it survived a reload. The write to IndexedDB happens a frame after the file
  closes, so call `JavaScriptBridge.force_fs_sync()` after a save that must survive closing
  the tab. Private windows do not keep it.
- **Audio** needs a click or key press first in most browsers (not reproducible in automated Chromium). Bus effects do
  not run on the web (`godot-audio`).
- **Input:** fullscreen and mouse capture work only from inside an input event. Gamepads appear after their first
  button press. A background tab pauses the game.
- **Test in browsers:** `export -Preset Web -Run -Browser chromium,firefox,msedge` exports a **debug** build too and
  opens it in each browser. Release builds hide script errors: a call on null does nothing and the game carries on.
  The run fails (`web-run-failed`) when the engine does not start, or on any page error, failed request or `ERROR` /
  `SCRIPT ERROR` line. Without the browser it fails with `no-browser`; `npx playwright install --with-deps firefox`
  installs one. `chrome` and `msedge` use the browsers installed on the machine.

## 8. Done means

- [ ] `layout` passes on every profile the game ships for, with the real notch insets
- [ ] two-finger input tested (`ParseInputEvent` with two indices); every on-screen control is at least 48 dp
- [ ] the game saves on pause and resumes cleanly; the frame rate is capped where it can be
- [ ] Android: `doctor` clean; an AAB signed; target API 36
- [ ] Web: `export -Run -Browser chromium,firefox,msedge` passes; the gzipped size fits the portal; a single-threaded build for itch.io
