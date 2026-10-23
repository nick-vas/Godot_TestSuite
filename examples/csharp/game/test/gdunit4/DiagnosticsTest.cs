namespace Example.Tests;

using System;
using System.Text.Json.Nodes;
using System.Linq;
using System.Threading.Tasks;
using Example.Core.Telemetry;
using Example.Diagnostics;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

// Crash reports reach telemetry only with consent. The errors are handed to the logger the way Godot hands it a C#
// exception (function ExceptionUtils.LogException, the exception text as the code), so the test log stays clean.
[TestSuite]
[RequireGodotRuntime]
public class DiagnosticsTest
{
    static void Report(ErrorCapture capture, string exceptionText) =>
        capture._LogError("ExceptionUtils.LogException", "", 0, exceptionText, "", false, (int)Logger.ErrorType.Error, new Godot.Collections.Array<ScriptBacktrace>());

    static string Thrown(string message)
    {
        try { throw new InvalidOperationException(message); }
        catch (Exception e) { return e.ToString(); }
    }

    // The game's own telemetry files: user:// is the same folder when a developer plays the game, so the player's consent
    // and session marker are set aside before each test and put back after it, not deleted.
    static readonly string[] TelemetryFiles = { "user://telemetry/state.json", "user://telemetry/session.running" };
    const string SetAside = ".before-test";

    [BeforeTest]
    public void SetTheGamesStateAside()
    {
        foreach (var file in TelemetryFiles)
        {
            var path = ProjectSettings.GlobalizePath(file);
            // A copy already set aside is the game's, left by a run that stopped early; what is in its place is a test's.
            if (System.IO.File.Exists(path + SetAside)) System.IO.File.Delete(path);
            else if (System.IO.File.Exists(path)) System.IO.File.Move(path, path + SetAside);
        }
    }

    [AfterTest]
    public void ForgetEverything()
    {
        foreach (var file in TelemetryFiles)
        {
            var path = ProjectSettings.GlobalizePath(file);
            if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
            if (System.IO.File.Exists(path + SetAside)) System.IO.File.Move(path + SetAside, path);
        }
    }

    [TestCase]
    public async Task Nothing_is_recorded_without_consent()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://Main.tscn");
        var diagnostics = ((Main)runner.Scene()).Diagnostics;
        await runner.SimulateFrames(1);
        Report(diagnostics.Capture, Thrown("boom"));
        AssertThat(diagnostics.Client.Queued).IsEqual(0);
        AssertThat(System.IO.File.Exists(ProjectSettings.GlobalizePath("user://telemetry/session.running"))).IsFalse();
    }

    [TestCase]
    public async Task An_exception_becomes_one_fingerprinted_crash_event()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://Main.tscn");
        var diagnostics = ((Main)runner.Scene()).Diagnostics;
        await runner.SimulateFrames(1);
        diagnostics.SetDiagnosticsConsent(true);
        Report(diagnostics.Capture, Thrown("player Ana's save"));
        Report(diagnostics.Capture, Thrown("player Bo's save"));   // the same crash again: not reported twice
        AssertThat(diagnostics.Client.Queued).IsEqual(1);

        var queued = JsonNode.Parse(diagnostics.Client.Export())!["queued"]![0]!;
        AssertThat(queued["fields"]!["kind"]!.GetValue<string>()).IsEqual("exception");
        AssertThat(queued.ToJsonString()).NotContains("Ana").NotContains("InvalidOperation");

        diagnostics.SetDiagnosticsConsent(false);   // withdrawn: what was held is gone
        AssertThat(diagnostics.Client.Queued).IsEqual(0);
    }

    [TestCase]
    public async Task A_session_that_never_quit_cleanly_is_reported_at_the_next_start()
    {
        using (ISceneRunner first = ISceneRunner.Load("res://Main.tscn"))
        {
            await first.SimulateFrames(1);
            var diagnostics = ((Main)first.Scene()).Diagnostics;
            diagnostics.SetDiagnosticsConsent(true);
            diagnostics.Client.Persist();
            // A crash: the process dies here, so no clean quit runs. The marker file stays behind.
            System.IO.File.Copy(ProjectSettings.GlobalizePath("user://telemetry/session.running"),
                ProjectSettings.GlobalizePath("user://telemetry/crashed.copy"), overwrite: true);
        }
        System.IO.File.Move(ProjectSettings.GlobalizePath("user://telemetry/crashed.copy"),
            ProjectSettings.GlobalizePath("user://telemetry/session.running"), overwrite: true);

        using ISceneRunner second = ISceneRunner.Load("res://Main.tscn");
        await second.SimulateFrames(1);
        var queued = JsonNode.Parse(((Main)second.Scene()).Diagnostics.Client.Export())!["queued"]!.AsArray();
        AssertThat(queued.Count).IsEqual(1);
        AssertThat(queued[0]!["fields"]!["kind"]!.GetValue<string>()).IsEqual("unclean_exit");
    }

    // The playtest events from a real floor: the paddle held away loses balls (death, with the floor as checkpoint), and
    // a playtest build's file gets them only once analytics consent is given; quitting ends the floor as quit.
    [TestCase]
    public async Task Playtest_events_from_a_floor_reach_the_session_file_only_with_consent()
    {
        var folder = ProjectSettings.GlobalizePath("user://playtests-test");
        string file;
        using (ISceneRunner runner = ISceneRunner.Load("res://Main.tscn"))
        {
            var main = (Main)runner.Scene();
            var diagnostics = main.Diagnostics;
            diagnostics.PlaytestSink = new PlaytestFileSink(folder, diagnostics.Client.SessionId);
            file = diagnostics.PlaytestSink.File;
            await runner.SimulateFrames(1);
            AssertThat(main.Playtest.Level).IsEqual("floor_1");

            Input.ActionPress("move_left");
            try
            {
                for (int i = 0; i < 1200 && main.Run.Lives == 3; i++) await runner.SimulateFrames(1);
                AssertThat(main.Run.Lives).IsEqual(2);
                AssertThat(await diagnostics.FlushPlaytestAsync()).IsEqual(0);   // no consent: nothing recorded
                AssertThat(System.IO.File.Exists(file)).IsFalse();

                diagnostics.Client.SetConsent(Purpose.Analytics, Consent.Granted);
                for (int i = 0; i < 1200 && main.Run.Lives == 2; i++) await runner.SimulateFrames(1);
                AssertThat(main.Run.Lives).IsEqual(1);
            }
            finally { Input.ActionRelease("move_left"); }
            AssertThat(await diagnostics.FlushPlaytestAsync()).IsEqual(1);
        }
        try
        {
            var events = System.IO.File.ReadAllLines(file)
                .SelectMany(line => JsonNode.Parse(line)!["events"]!.AsArray())
                .Select(e => (Name: e!["event"]!.GetValue<string>(), Fields: e["fields"]!)).ToList();
            AssertThat(events.Select(e => e.Name).ToArray()).ContainsExactly("death", "level_time");
            AssertThat(events[0].Fields["level"]!.GetValue<string>()).IsEqual("floor_1");
            AssertThat(events[0].Fields["checkpoint"]!.GetValue<int>()).IsEqual(1);
            AssertThat(events[0].Fields["y"]!.GetValue<double>()).IsEqual(448.0);   // the paddle's top
            AssertThat(events[1].Fields["result"]!.GetValue<string>()).IsEqual("quit");   // the scene left the tree: written then
        }
        finally { System.IO.Directory.Delete(folder, recursive: true); }
    }
}
