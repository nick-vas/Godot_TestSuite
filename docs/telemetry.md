# Crash reports and telemetry: sources and measurements

The research behind the `godot-telemetry` skill, Breakout's `Telemetry/` and `Diagnostics/`, and `doctor`'s Sentry check,
gathered on 2026-10-21. Nothing was sent to a real service: every test used a listener on the machine itself. This is
engineering research, not legal advice.

## Sources

| Source | What it gave |
|---|---|
| [sentry-godot](https://github.com/getsentry/sentry-godot) 2.4.0 (MIT) and [its documentation](https://docs.sentry.io/platforms/godot/) | Godot 4.5+; one addon for GDScript, engine and C#; Crashpad for native crashes; `auto_init` and `attach_log` on by default; no consent setting; C# `SetBeforeSend` covers only managed events (`Native.SetBeforeSend` for the rest) |
| [Sentry data retention](https://docs.sentry.io/security-legal-pii/security/data-retention-periods/) | Errors kept 30 days (Developer plan) or 90 days (Team and Business): the source of the usual "90 days" |
| Godot 4.7 [logging documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/logging.html) and class reference | `Logger` (4.5+) runs on the failing thread and must not print; file logging on by default on desktop, five files kept |
| GDPR (Regulation 2016/679), Arts. 4, 5, 6, 7, 8, 11, 15, 17, 20, 25 and Recitals 26, 30, 32, 38, 47, 49, 64 | Personal data, lawful bases, consent and its withdrawal, minimisation, storage limitation, children, access and erasure |
| ePrivacy Directive 2002/58/EC Art. 5(3); EDPB Guidelines 2/2023 on the technical scope of Art. 5(3) (v2.0, 7 October 2024, para. 34); [EDPB Guidelines 05/2020 on consent](https://www.edpb.europa.eu/documents/guideline/guidelines-052020-on-consent-under-regulation-2016679_en) (paras. 39, 114) | An SDK that sends stored device information needs consent, personal or not; withdrawal in the same interface |
| CJEU, Breyer, [C-582/14](https://curia.europa.eu/jcms/upload/docs/application/pdf/2016-10/cp160112en.pdf) | A dynamic IP address is personal data |
| [COPPA, 16 CFR 312](https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-312) | Persistent identifiers are personal information; the internal-operations exception; a written retention policy |
| [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Google Play Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) | First-party crash data is not tracking but is declared; "Crash logs" and "Diagnostics" data types |

## Measurements

| What | Result |
|---|---|
| A C# exception in `_Process`, a signal handler, an `async void` method (4.7.2 mono, editor binary and release export) | The game kept running; a `Logger` received each as an error from `ExceptionUtils.LogException` with the full exception text; `AppDomain.UnhandledException` never fired |
| An exception on a thread the game created | The process aborted (exit 134); `AppDomain.UnhandledException` fired just before |
| A `Task` nobody awaited | Reported only to `TaskScheduler.UnobservedTaskException`, after a garbage collection |
| `OS.Crash` in a release mono export | Exit 132 and no crash banner in the output or the log; the debug export printed it |
| A release stack trace | The developer's absolute source paths; with `ContinuousIntegrationBuild` (or `PathMap`) they read `/_/` |
| A process that had registered a C# `Logger`, even one removed again, run under coverlet | Hung at exit after its tests passed (Breakout's GoDotTest run); fine without coverlet. Breakout installs its logger only when Main is the running game |
| Breakout's `TelemetryClient` | Nothing recorded before consent; withdrawal deletes the queue; 8 threads × 1000 events while sending: all 8000 delivered once |

## Not confirmed

- EUR-Lex, gdpr-info.eu and cnil.fr could not be reached; the GDPR was quoted from legislation.gov.uk's text as adopted.
- No law or regulator sets 90 days; CNIL's 13 and 25 months for audience measurement come from secondary sources.
- Whether crash reporting may rest on legitimate interest, and how to answer access and erasure requests with random
  ids, are questions for a lawyer.
- The sentry-godot binaries could not be downloaded here; its source was read, not run.
- The cause of the coverlet hang was not found (no engine symbols); see the roadmap.
