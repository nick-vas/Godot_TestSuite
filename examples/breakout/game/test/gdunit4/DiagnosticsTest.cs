namespace Breakout.Tests;

using System;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Breakout.Core.Telemetry;
using Breakout.Diagnostics;
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

    [AfterTest]
    public void ForgetEverything()
    {
        foreach (var file in new[] { "user://telemetry/state.json", "user://telemetry/session.running" })
            if (System.IO.File.Exists(ProjectSettings.GlobalizePath(file))) System.IO.File.Delete(ProjectSettings.GlobalizePath(file));
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
}
