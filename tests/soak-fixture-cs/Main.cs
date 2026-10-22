using System.Runtime.InteropServices;
using Godot;

// The smallest server that stops the way a host expects: on SIGTERM it refuses new players, lets the match finish (here
// a short drain), and quits with 0. Godot has no handler of its own; without this, SIGTERM kills it at once (exit 143).
// The kit starts it with --soak-role=server|client and --soak-port, as it does tests/soak-fixture.
public partial class Main : Node
{
    PosixSignalRegistration? _term;
    volatile bool _stopRequested;
    bool _draining;
    string _role = "";

    public override void _Ready()
    {
        int port = 0;
        foreach (var arg in OS.GetCmdlineUserArgs())
        {
            var parts = arg.Split('=', 2);
            if (parts[0] == "--soak-role") _role = parts[1];
            if (parts[0] == "--soak-port") port = int.Parse(parts[1]);
        }
        var peer = new ENetMultiplayerPeer();
        if (_role == "server")
        {
            if (peer.CreateServer(port, 32) != Error.Ok) { GD.Print("[soak] fail server could not listen"); return; }
            Multiplayer.MultiplayerPeer = peer;
            // The handler runs on a thread-pool thread: only set a flag; the frame loop acts on it.
            _term = PosixSignalRegistration.Create(PosixSignal.SIGTERM, ctx => { ctx.Cancel = true; _stopRequested = true; });
            GD.Print("[soak] ready");
        }
        else
        {
            peer.CreateClient("127.0.0.1", port);
            Multiplayer.MultiplayerPeer = peer;
            Multiplayer.ConnectedToServer += () => GD.Print("[soak] ready");
        }
    }

    public override async void _Process(double delta)
    {
        if (!_stopRequested || _draining) return;
        _draining = true;
        GD.Print("[soak] stopping: refusing new players, draining");
        if (Multiplayer.MultiplayerPeer is ENetMultiplayerPeer enet) enet.RefuseNewConnections = true;
        await ToSignal(GetTree().CreateTimer(0.5), SceneTreeTimer.SignalName.Timeout);
        GetTree().Quit(0);
    }

    public override void _ExitTree() => _term?.Dispose();
}
