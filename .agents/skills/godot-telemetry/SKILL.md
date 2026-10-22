---
name: godot-telemetry
description: Use when a Godot game reports crashes or errors, sends analytics or gameplay events, adds Sentry or another crash service, asks players for data consent, or has to answer a data export or deletion request.
---

# Crash reports and telemetry in Godot 4 (C#)

Know when the game breaks and how it is played, without collecting anything a player did not agree to or anything
that identifies them. The tested pieces are in `${CLAUDE_PLUGIN_ROOT}/examples/breakout`:
`src/Breakout.Core/Telemetry/` (`TelemetryClient`, `TelemetrySchema`, `CrashFingerprint`, `SessionMarker`) and
`game/Diagnostics/Diagnostics.cs`, with tests in `tests/Breakout.Core.Tests/` and `game/test/gdunit4/DiagnosticsTest.cs`.
Sources, tests and what is unconfirmed: `${CLAUDE_PLUGIN_ROOT}/docs/telemetry.md`. This is engineering, not legal advice:
have a lawyer read the privacy notice and the consent flow before release.

## 1. Two jobs, two tools

- **Crashes and errors**: Sentry's Godot addon (`sentry-godot`, MIT, Godot 4.5+). One addon covers GDScript, the engine
  and C#: it brings Sentry's .NET SDK itself; do not add that package too (its analyzer warns `SENTRYGD1001`). Native
  crashes go through Crashpad, which writes a minidump from a separate process. GlitchTip (MIT) accepts the same reports
  if you host it yourself.
- **Gameplay events** (levels finished, settings changed): a small client of your own with a fixed schema, like
  Breakout's `TelemetryClient`. Do not push them through the crash service.

## 2. Consent first

- Analytics needs opt-in consent. A game that reads device information or a stored id and sends it needs it even when
  nothing is personal (ePrivacy Art. 5(3); EDPB Guidelines 2/2023). Crash reporting may rest on legitimate interest
  (GDPR Art. 6(1)(f)), but the safe default, and the one Breakout uses, is consent for each.
- Ask in the game's own settings: a separate switch for crash reports and for analytics, both off until the player
  turns them on, the game fully playable either way. Withdrawing is in the same place and as easy (Art. 7(3)); it stops
  recording and deletes what is still on the device (`SetConsent(..., Consent.Refused)` does).
- Record which version of the privacy notice the answer was for (`policyVersion`); a new notice asks again.
- Children: below 13 to 16, depending on the country (GDPR Art. 8), consent comes from a parent; in the US under 13 (COPPA)
  only crash and diagnostics ids for "internal operations" are exempt. A game for children collects crashes at most.
- Sentry has no consent setting. Turn `auto_init` off and call `SentrySdk.Init` after the player agrees (`SentrySdk.Close()`
  on withdrawal). `doctor` warns when the addon starts on its own (`auto_init`), attaches the whole log (`attach_log`,
  on by default) or sends personal data (`send_default_pii`).

## 3. What may be sent

- No free text, ever: player names, chat, file paths, exception messages and log lines carry personal data. Breakout's
  schema has no string kind except fixed labels; a field whose name sounds personal (`player_email`, `device_id`,
  `chat_text`) is refused when the schema is built, and an event that does not match exactly throws.
- No device or account ids: not `OS.GetUniqueId()`, not a SteamID, not the machine name. A random session id, new each
  launch, is enough to group a session's events, and the player can see it.
- Crashes are grouped by a fingerprint (exception type and the game's top frames, hashed), not by their text.
- Coarsen at the source: language not locale, buckets not exact values.
- The server sees the IP address, which is personal data (CJEU Breyer, C-582/14): drop it at the edge and say so.
- Release builds map source paths to `/_/` (`<ContinuousIntegrationBuild>true</ContinuousIntegrationBuild>` for
  `ExportRelease`): otherwise every stack trace carries the developer's own paths, often their name. With Sentry, also
  turn `attach_log` off or scrub it, and filter in both `options.SetBeforeSend` (C# events) and `Native.SetBeforeSend`
  (engine and GDScript events): each covers only its own kind.

## 4. Catching errors in a C# Godot game

- A C# exception in `_Process`, a signal handler or an `async void` method does not stop the game: Godot logs it and
  goes on. `AppDomain.UnhandledException` never sees those. A Godot `Logger` does (4.5+):
  `OS.AddLogger(new ErrorCapture(client))`, where `_LogError` receives the exception text as `code` and
  `ExceptionUtils.LogException` as `function`.
- A `Logger` runs on the thread that failed, maybe several at once: no engine calls, no printing (it recurses), no
  throwing. Breakout's records one event per fingerprint and nothing else.
- Install it once, from the game's entry point. On Godot 4.7.2 mono, a process that had registered a C# `Logger`, even
  one removed again, hung at exit under coverlet (the kit's coverage), so scenes that tests instantiate must not.
- An exception on a thread you created kills the process (exit 134): write a marker file synchronously in
  `AppDomain.CurrentDomain.UnhandledException`. A `Task` nobody awaited reports only to `TaskScheduler.UnobservedTaskException`,
  late; await it, or `ContinueWith(..., OnlyOnFaulted)`.
- Native crashes run none of your code. Without Crashpad, a session marker notices them at the next start
  (`SessionMarker`: written at start, deleted on a clean quit). The release mono export printed no crash banner at all.
- Godot also writes `user://logs/godot.log` on desktop (five files kept); after a crash the previous run's log is the
  newest rotated one, not `godot.log`.

## 5. Sending without hurting the game

- `Track` only checks and queues; `FlushAsync` sends batches from a background task, never on the frame, and never
  holds up quitting more than a moment; what is left waits on disk for the next launch.
- A failed send keeps the events; events older than a week are dropped unsent. Sample whole sessions
  (`analyticsSampleRate`), never single events, so funnels stay whole; never sample crashes.
- Comparing two versions from these events (an A/B test): `godot-automation-hooks`, "Comparing two versions".
- For balance, send one summary per run on victory or death, so quiet players count too: the floor reached, the result,
  the difficulty and the floor each option was taken on (Breakout's `run_end`, `RunSummary`). Reading it without being
  fooled: `godot-automation-hooks`, "Reading balance from run data".
- With `using Godot;` and `using System.Net.Http;` in one file, `HttpClient` is ambiguous (CS0104): keep the transport in
  a file without `using Godot;`, or name `System.Net.Http.HttpClient` in full.

## 6. Keeping and deleting

- The GDPR sets no number of days; keep raw events only as long as their purpose needs, and say how long in the privacy
  notice. 90 days is Sentry's own default for errors on paid plans, a reasonable figure to state, not a legal one.
- Export (Art. 15 and 20) and erasure (Art. 17): `Export()` shows what the device holds and the session ids sent;
  `Erase()` clears the device and returns the ids the server must delete. With random ids and no account, the
  server cannot find a player's data any other way; whether to show the player an id for requests is a question for
  the lawyer (Art. 11).
- Store pages ask too: Google Play's Data safety form ("Crash logs", "Diagnostics") and Apple's privacy details. First-party
  crash and analytics data is not "tracking" for Apple's ATT prompt, but it must be declared.

## 7. Prove it

- [ ] nothing is recorded or sent before consent, and withdrawing deletes what is held (`TelemetryTests`)
- [ ] the schema refuses free text and personal-sounding fields; every event validates exactly
- [ ] an exception reaches the logger and becomes one fingerprinted event with no message text (`DiagnosticsTest`)
- [ ] a session that never quit cleanly is reported at the next start, only with consent
- [ ] `doctor` shows no Sentry warning; a release build's stack trace shows `/_/`, not a home folder
- [ ] the privacy notice states what, why, how long, where, and how to withdraw, export and delete
