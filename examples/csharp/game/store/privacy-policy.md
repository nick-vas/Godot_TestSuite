# Breakout privacy policy

Version 1. Breakout is the kit's example game; this is the shape of a real policy, written from what its code records
(`Diagnostics/Diagnostics.cs`, `Example.Core/Telemetry`). A real game names its studio, a contact address and where the
data is sent.

## What the game records, and only after you agree

The game asks in its settings menu before it records anything, separately for each purpose, and records nothing for a
purpose you refuse.

- **Diagnostics**: crash reports. Each one holds the kind of crash (an exception, an engine error or a session that
  did not quit cleanly) and a fingerprint, a hash that groups reports of the same error. No stack text, file paths or
  names.
- **Analytics**: the floor you reached and your score, and at the end of each run the floor, whether you won, died or
  gave up, the difficulty, and the floor where you first took each upgrade. We use it to balance the game.

Every report carries a random session id and the game's version. Nothing identifies you, your device or your account.

## Your choices

- Change either answer at any time in the settings menu. Refusing or withdrawing deletes what the game still holds on
  your device.
- Export: the game can show you everything it holds about you on this device, and the session ids it has sent.
- Erasure: the game deletes what it holds here and gives you the session ids, so that we can delete what was sent.

When this policy changes, its version goes up and the game asks you again.
