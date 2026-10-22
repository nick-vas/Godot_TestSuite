namespace Breakout.Diagnostics;

using System.Collections.Generic;
using Breakout.Core.Telemetry;
using Godot;

/// <summary>
/// The game's telemetry: crash reports and play events, each only with the player's consent (ask in the settings menu,
/// before recording anything). Sending is the game's own job: post <see cref="TelemetryClient.FlushAsync"/> batches from a
/// background task to your endpoint, or use Sentry's Godot addon for crashes (it brings its own consent switch: leave
/// auto_init off and start it after the player agrees).
/// </summary>
public partial class Diagnostics : Node
{
    public static readonly TelemetrySchema Schema = new(
        new EventDefinition("crash", 1, Purpose.Diagnostics, new Dictionary<string, FieldKind>
        {
            ["kind"] = new FieldKind.Label("exception", "engine", "unclean_exit"),
            ["fingerprint"] = new FieldKind.Fingerprint(),
        }),
        new EventDefinition("floor_reached", 1, Purpose.Analytics, new Dictionary<string, FieldKind>
        {
            ["floor"] = new FieldKind.Integer(1, 999),
            ["score"] = new FieldKind.Integer(0, int.MaxValue),
        }),
        // One per run, on victory or death: the floor reached and when each upgrade was first taken (BalanceReport).
        RunSummary.Event);

    /// <summary>The fingerprint of a session that did not quit cleanly: nothing to group by but the fact itself.</summary>
    public const string UncleanExitFingerprint = "0000000000000000";

    SessionMarker? _marker;
    ErrorCapture? _capture;

    public TelemetryClient Client { get; private set; } = null!;
    /// <summary>
    /// Install the logger for the whole process. Only the game's own entry point should: a scene a test instantiates is
    /// not the game, and on Godot 4.7.2 mono a process that ever registered a C# Logger hung at exit under coverlet.
    /// </summary>
    public bool CaptureEngineErrors { get; init; }
    public ErrorCapture Capture => _capture ?? throw new System.InvalidOperationException("not in the scene tree");

    public override void _Ready()
    {
        string version = ProjectSettings.GetSetting("application/config/version", "dev").AsString();
        Client = new TelemetryClient(Schema, string.IsNullOrEmpty(version) ? "dev" : version,
            stateFile: ProjectSettings.GlobalizePath("user://telemetry/state.json"));
        _marker = new SessionMarker(ProjectSettings.GlobalizePath("user://telemetry/session.running"));
        _capture = new ErrorCapture(Client);
        if (CaptureEngineErrors) OS.AddLogger(_capture);
        if (Client.ConsentFor(Purpose.Diagnostics) == Consent.Granted) BeginSession();
    }

    /// <summary>From the settings menu. Refusing (or withdrawing) also deletes what was held, and stops the marker.</summary>
    public void SetDiagnosticsConsent(bool granted)
    {
        Client.SetConsent(Purpose.Diagnostics, granted ? Consent.Granted : Consent.Refused);
        if (granted) BeginSession(); else _marker?.End();
    }

    void BeginSession()
    {
        if (_marker!.Begin())
            Client.Track("crash", new Dictionary<string, object> { ["kind"] = "unclean_exit", ["fingerprint"] = UncleanExitFingerprint });
    }

    public override void _Notification(int what)
    {
        // A clean quit: the next start will not report this session as a crash.
        if (what == NotificationWMCloseRequest || what == NotificationPredelete)
        {
            _marker?.End();
            Client?.Persist();
        }
        // A node deleted while the game quits (queued for deletion, then flushed at shutdown) never gets _ExitTree. A
        // logger still registered then is called for the engine's own shutdown messages after .NET has begun to unload,
        // and the process hangs; so unregister on deletion too.
        if (what == NotificationPredelete) RemoveCapture();
    }

    public override void _ExitTree() => RemoveCapture();

    void RemoveCapture()
    {
        if (_capture == null) return;
        if (CaptureEngineErrors) OS.RemoveLogger(_capture);
        _capture = null;
    }
}

/// <summary>
/// Receives every error Godot reports, including C# exceptions thrown in callbacks (which Godot logs and survives;
/// AppDomain.UnhandledException never sees them). Runs on the thread that failed: no engine calls, no printing, no
/// throwing, only a schema-checked event with a fingerprint, once per distinct crash per session.
/// </summary>
public partial class ErrorCapture(TelemetryClient client) : Logger
{
    readonly HashSet<string> _seen = new();

    public override void _LogError(string function, string file, int line, string code, string rationale,
        bool editorNotify, int errorType, Godot.Collections.Array<ScriptBacktrace> scriptBacktraces)
    {
        if (errorType == (int)ErrorType.Warning) return;
        try
        {
            bool exception = function == "ExceptionUtils.LogException";
            string fingerprint = CrashFingerprint.From(exception ? code : $"{function}Error\n   at {function}(");
            lock (_seen) if (!_seen.Add(fingerprint)) return;
            client.Track("crash", new Dictionary<string, object> { ["kind"] = exception ? "exception" : "engine", ["fingerprint"] = fingerprint });
        }
        catch (System.Exception) { /* a report about a report would loop: drop it */ }
    }
}
