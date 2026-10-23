# Phones, tablets and browsers: what was measured

The research behind the `godot-mobile-web` skill, the `layout` runner, `export -Run` for Web presets and `doctor`'s Web and
Android checks, gathered on 2026-10-21 with Godot 4.7.2 (mono and standard builds) on Linux. Android exports were built
and inspected here; nothing ran on a phone (no device, and no KVM for an emulator), and iOS needs macOS.

## Sources

| Source | What it gave |
|---|---|
| [Godot docs 4.7: Exporting for the Web](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html) | No C# on the web; single-threaded export the default since 4.3; COOP/COEP for threads; hosts that compress (GitHub Pages) and do not (itch.io); WebGL 2 only; audio, fullscreen, gamepad and background-tab limits |
| [Godot docs 4.7: Exporting for Android](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html), [Gradle builds](https://docs.godotengine.org/en/4.7/tutorials/export/android_gradle_build.html) | SDK and JDK versions, keystore variables (keystore and key passwords must match), folders starting with `_` skipped by Gradle builds |
| Godot 4.7.2 source: `platform/web/export/export_plugin.cpp`, `platform/android/export/export_plugin.cpp`, `os_web.cpp`, `base_button.cpp`, `ProjectSettings.xml`, `DisplayServer.xml` | The C# web refusal, net9.0 for prebuilt C# Android, minSdk 24 and targetSdk 36, the asynchronous IndexedDB sync, multitouch buttons, touch emulation defaults, which platforms implement safe areas and cutouts |
| [Android: page sizes](https://developer.android.com/guide/practices/page-sizes) (updated 2026-10-16), [target API](https://developer.android.com/google/play/requirements/target-sdk) | 16 KB pages required for updates from 1 February 2027; target API 36 for new apps and updates since 31 August 2026 |
| [Android accessibility](https://developer.android.com/guide/topics/ui/accessibility/apps), Apple Human Interface Guidelines (Buttons), [WCAG 2.2 SC 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) | 48x48 dp, 44x44 pt, 24x24 CSS px |
| [Apple: upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) | iOS 26 SDK for uploads since April 2026 (search summary; the page was not read directly) |
| [CrazyGames technical requirements](https://docs.crazygames.com/requirements/technical/) | 50 MB initial download, 20 MB for the mobile homepage |
| [coi-serviceworker](https://github.com/gzuidhof/coi-serviceworker) (MIT) | The other way to get cross-origin isolation on hosts without headers |
| [Virtual Joystick for Godot 4](https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot) (MIT) | An on-screen stick add-on |
| "Controlling Carnage: Effective Side-Scroller Controls on Mobile" (Roadhouse Interactive, GDC; [notes](gdc/controlling-carnage.md)) | Hit pads larger than the drawn buttons, no dead spot under a thumb, sliding between pads, the largest pad for jump, fading art, a tighter layout under 7 inches; the C# example's `Controls/TouchPads.cs` and `TouchControls.cs` |
| Zach Gage, "Controls You Can Feel" (GDC talk on touch controls; [notes](gdc/controls-you-can-feel.md)) | 75 x 75 pt for buttons pressed without looking (Super Crate Box), 44 pt for buttons looked at, nothing under 40 pt; sticks as the weak option; swipe up, not down. The `small-control` check (`minControlDp`) and the skill's thumb-control rules |

## Measured here

| What | Result |
|---|---|
| C# Web export (mono editor, the C# example) | exit 1: "Exporting to Web is currently not supported in Godot 4 when using C#/.NET"; the mono templates have no web zips |
| Single-threaded web build | starts in Chromium (SwiftShader WebGL 2) in 1.5 to 3.5 s, with or without COOP/COEP headers |
| Threads build without headers | never starts: "missing features: Cross-Origin Isolation, SharedArrayBuffer"; with headers it starts |
| PWA option "Ensure Cross Origin Isolation Headers" | works, but the first load stalled ("Service worker already exists") until a second reload |
| Web size (GDScript example) | `index.wasm` 37.7 MB, 9.7 MB gzip, 6.8 MB brotli; the whole folder 38 MB, 9.9 MB gzip |
| Exporting into `res://build/web` | the next export packed the exported icons: `index.pck` grew from 2.7 KB to 26.8 KB |
| A call on null in `_ready` | release build: silent, the function carries on; debug build: `SCRIPT ERROR` with a backtrace |
| `user://` on the web | `/userfs`, IndexedDB; a counter survived a reload; the sync starts on the next frame after the file closes |
| Touch in Chromium (Playwright, 412x915 at 2.625x) | `InputEventScreenTouch` plus an emulated mouse button; positions in device pixels; `ScreenGetDpi()` 252 |
| Safe area on the web | the whole window; no cutouts |
| Headless Firefox on a GitHub Linux runner (no GPU) | the engine never starts: "missing features: WebGL2", also with `webgl.force-enabled`; Chromium (SwiftShader) and the runner's Edge start it. With `HYPEDOT_WEB_HEADED=1` and a window under Xvfb (`libgl1-mesa-dri`), Firefox passes every check |
| Audio unlock | could not be reproduced: headless and headed Chromium started the AudioContext without a gesture |
| Android APK (GDScript) | 26.4 MB, 14 s; minSdk 24, targetSdk 36, arm64-v8a; `zipalign -c -P 16` passed; every `.so` aligned to 16 KB |
| Android export without `import_etc2_astc` | refused: "ETC2/ASTC texture compression is required for Android export" |
| Android export without an icon | succeeds, but logs `ERROR: No project icon specified` (the kit now ignores the line; `doctor` warns) |
| `ANDROID_HOME`/`JAVA_HOME` with an existing editor settings file | ignored ("Invalid Android SDK path"); a fresh `XDG_CONFIG_HOME` makes them apply |
| C# Android, prebuilt template, net8.0 | refused: "the export template only supports 'net9.0'"; with net9.0 and .NET 9: a 102 MB APK with about 60 MB of static `.a` files |
| C# Android, Gradle AAB, net8.0 | 39 MB, no `.a` files, signed; 34 s with a warm Gradle cache (the first Gradle build hit HTTP 429 from Maven Central once) |
| Godot headless | exit 134 (abort) after finished exports or imports, 4 times in 23 runs: `Parameter "singleton" is null` at shutdown |
| `layout` runner, headless and with a display | identical output; 0.4 s for a menu |
| `TouchScreenButton` in 4.7.2 | a `Node2D` (`ClassDB.get_parent_class`), so the runner measures it apart from Controls. Touches hit its shape, centred on the texture when `shape_centered` is on and there is a texture, around the node's origin when there is none; without a shape, the texture's rectangle (checked with `InputEventScreenTouch` at points inside and outside) |

## C# safe area

The `SafeArea` autoload in the skill, and the container that applies it (verified with the `layout` runner: the fixture's
fixed menu passes on every profile only when `SetInsets` reaches it).

```csharp
public partial class SafeMargins : MarginContainer   // anchor it full rect; children stay inside the safe area
{
    [Export] public int Extra { get; set; }
    private SafeArea _safeArea = null!;

    public override void _Ready()
    {
        _safeArea = GetNode<SafeArea>("/root/SafeArea");
        _safeArea.Changed += Apply;
        Apply();
    }

    public override void _ExitTree() => _safeArea.Changed -= Apply;

    private void Apply()
    {
        Rect2 view = GetViewportRect();
        Rect2 safe = _safeArea.CanvasRect();
        AddThemeConstantOverride("margin_left", Mathf.CeilToInt(safe.Position.X - view.Position.X) + Extra);
        AddThemeConstantOverride("margin_top", Mathf.CeilToInt(safe.Position.Y - view.Position.Y) + Extra);
        AddThemeConstantOverride("margin_right", Mathf.CeilToInt(view.End.X - safe.End.X) + Extra);
        AddThemeConstantOverride("margin_bottom", Mathf.CeilToInt(view.End.Y - safe.End.Y) + Extra);
    }
}
```

The autoload also connects `GetTree().Root.SizeChanged` to its `Changed` signal and reads `--safe-area=L,T,R,B` from
`OS.GetCmdlineUserArgs()` in `_Ready`, so a desktop run can fake a notch.

## Mistakes an agent is likely to make

1. Trying to export a C# game to the web, or "fixing" it with settings.
2. A threads build hosted on itch.io or GitHub Pages: a blank "missing features" page.
3. Exporting into the project, so the next export packs the last one.
4. Smoke-testing a release web build, which hides script errors.
5. Expecting `ANDROID_HOME`/`JAVA_HOME` to configure a headless export when editor settings exist.
6. Forgetting `import_etc2_astc` (the export refuses) and the icon.
7. C# on Android with the prebuilt template on net8.0; and the .NET first-run banner read as the target framework (`DOTNET_NOLOGO=1`).
8. A portrait game left in the default landscape orientation, or with an unswapped viewport.
9. Reading `GetDisplaySafeArea()` as canvas coordinates, or expecting it on web and desktop, or cutouts on iOS.
10. Treating `ScreenGetDpi()` on Android as exact, or the emulated mouse as multitouch.
11. Expecting `low_processor_mode` to help a game that redraws every frame.
12. Believing an automated browser proves the audio unlock.
13. Trusting Godot's exit code alone: 4.7.2 headless can abort with 134 after finishing. `export` runs a crashed export
    again, up to twice, after deleting what it left (`exports[].retried`); a crash on every run still fails.
