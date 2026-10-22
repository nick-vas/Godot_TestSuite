using System.Net;
using System.Net.Sockets;
using System.Text;
using Breakout.Core.Net;
using Xunit;
using static Breakout.Core.Net.ServerAction;

namespace Breakout.Core.Tests;

// A dedicated server's life under a fleet manager, after Agones (docs/googleforgames.md).
public sealed class ServerLifecycleTests
{
    static ServerLifecycle Allocated(LifecycleOptions? options = null)
    {
        var life = new ServerLifecycle(options ?? new LifecycleOptions());
        life.Listening();
        life.Allocated(0);
        return life;
    }

    [Fact]
    public void ReadyOnlyOnceThePortIsBound()
    {
        var life = new ServerLifecycle(new LifecycleOptions());
        Assert.Equal(ServerState.Starting, life.State);
        Assert.Empty(life.Allocated(0));   // a matchmaker cannot hand a match to a server that is not ready
        Assert.Equal(ServerState.Starting, life.State);
        Assert.Equal([MarkReady], life.Listening());
        Assert.Empty(life.Listening());   // once
        Assert.Equal(ServerState.Ready, life.State);
    }

    [Fact]
    public void AnAllocatedServerNobodyJoinsIsGivenBack()
    {
        var life = Allocated(new LifecycleOptions { FirstPlayerTimeoutSeconds = 900 });
        Assert.Empty(life.Tick(899));
        Assert.Equal([RefuseNewPlayers, MarkShutdown, Exit], life.Tick(900));
        Assert.Equal("nobody joined", life.EndReason);
        Assert.Empty(life.Tick(2000));   // once
    }

    [Fact]
    public void TheServerEndsWhenEverybodyHasLeftAndNobodyCameBack()
    {
        var life = Allocated(new LifecycleOptions { EmptyGraceSeconds = 20 });
        life.PlayerJoined("a", 1);
        life.PlayerJoined("b", 2);
        Assert.Empty(life.PlayerLeft("a", 50));
        Assert.Empty(life.PlayerLeft("b", 60));
        Assert.Empty(life.Tick(70));
        life.PlayerJoined("b", 75);   // reconnected within the grace
        Assert.Empty(life.Tick(200));
        Assert.Empty(life.PlayerLeft("b", 300));
        Assert.Equal([RefuseNewPlayers, MarkShutdown, Exit], life.Tick(320));
        Assert.Equal("everybody left", life.EndReason);
    }

    [Fact]
    public void ASelfHostedServerCountsTheFirstPlayerAsTheAllocation()
    {
        var life = new ServerLifecycle(new LifecycleOptions());
        life.Listening();
        life.PlayerJoined("a", 5);
        Assert.Equal(ServerState.Allocated, life.State);
        Assert.Equal(1, life.Players);
    }

    [Fact]
    public void AStopDuringAMatchDrainsThenEnds()
    {
        var life = Allocated(new LifecycleOptions { DrainSeconds = 20 });
        life.PlayerJoined("a", 1);
        Assert.Equal([RefuseNewPlayers], life.StopRequested(100));
        Assert.Equal(ServerState.Draining, life.State);
        Assert.Empty(life.PlayerJoined("late", 101) is var _ ? life.Tick(110) : []);
        Assert.Equal([MarkShutdown, Exit], life.Tick(120));   // new players were already refused at the stop
        Assert.Equal("drain time over", life.EndReason);
    }

    [Fact]
    public void AStopDuringAMatchEndsEarlyWhenThePlayersLeave()
    {
        var life = Allocated(new LifecycleOptions { DrainSeconds = 60, EmptyGraceSeconds = 0 });
        life.PlayerJoined("a", 1);
        life.StopRequested(10);
        Assert.Equal([MarkShutdown, Exit], life.PlayerLeft("a", 15));
    }

    [Fact]
    public void AStopWithNoMatchEndsAtOnce()
    {
        var ready = new ServerLifecycle(new LifecycleOptions());
        ready.Listening();
        Assert.Equal([RefuseNewPlayers, MarkShutdown, Exit], ready.StopRequested(1));
        var starting = new ServerLifecycle(new LifecycleOptions());
        Assert.Equal([MarkShutdown, Exit], starting.StopRequested(1));
        Assert.Equal([RefuseNewPlayers, MarkShutdown, Exit], Allocated().StopRequested(1));
    }

    [Fact]
    public void UnderAgonesTheProcessWaitsForItsSigterm()
    {
        var life = Allocated(new LifecycleOptions { ExitAfterShutdown = false });
        Assert.Equal([RefuseNewPlayers, MarkShutdown], life.MatchEnded(10));
        Assert.Empty(life.StopRequested(11));   // the SIGTERM after the shutdown: nothing more to do but quit
        Assert.Equal(ServerState.Shutdown, life.State);
    }

    [Fact]
    public void TheWatchdogPingsThroughALoadButNotThroughAHang()
    {
        var dog = new HealthWatchdog(hungAfterSeconds: 10);
        Assert.False(dog.ShouldPing(0));   // no frame yet: the game has not started
        dog.Frame(1);
        Assert.True(dog.ShouldPing(4));    // a 3-second load: still pinging
        Assert.True(dog.ShouldPing(10.9));
        Assert.False(dog.ShouldPing(11));  // hung: let the fleet manager replace it
        dog.Frame(12);
        Assert.True(dog.ShouldPing(12));
    }

    // A stand-in for Agones' sidecar on a free port, recording what the client sends; the same calls were checked
    // against the real sdk-server 1.61.0 in --local mode (docs/googleforgames.md).
    sealed class FakeSidecar : IDisposable
    {
        readonly HttpListener _listener = new();
        public readonly List<string> Requests = new();
        public string State = "Ready";
        public int Port { get; }

        public FakeSidecar()
        {
            var probe = new TcpListener(IPAddress.Loopback, 0);
            probe.Start();
            Port = ((IPEndPoint)probe.LocalEndpoint).Port;
            probe.Stop();
            _listener.Prefixes.Add($"http://localhost:{Port}/");
            _listener.Start();
            _ = Task.Run(Serve);
        }

        async Task Serve()
        {
            while (_listener.IsListening)
            {
                HttpListenerContext ctx;
                try { ctx = await _listener.GetContextAsync(); } catch { return; }
                string body = await new StreamReader(ctx.Request.InputStream).ReadToEndAsync();
                lock (Requests) Requests.Add($"{ctx.Request.HttpMethod} {ctx.Request.Url!.AbsolutePath} {body}");
                string reply = ctx.Request.Url.AbsolutePath == "/gameserver" ? $"{{\"status\":{{\"state\":\"{State}\"}}}}" : "{}";
                var bytes = Encoding.UTF8.GetBytes(reply);
                ctx.Response.ContentType = "application/json";
                await ctx.Response.OutputStream.WriteAsync(bytes);
                ctx.Response.Close();
            }
        }

        public void Dispose() => _listener.Close();
    }

    [Fact]
    public async Task TheRestClientSpeaksAgonesHttpApi()
    {
        using var sidecar = new FakeSidecar { State = "Allocated" };
        var sdk = new AgonesRest(new HttpClient { BaseAddress = new Uri($"http://localhost:{sidecar.Port}/") });
        Assert.True(await sdk.WaitForSidecarAsync(attempts: 3, every: TimeSpan.FromMilliseconds(50)));
        await sdk.ReadyAsync();
        await sdk.HealthAsync();
        await sdk.SetLabelAsync("map", "garden");
        Assert.Equal("Allocated", await sdk.StateAsync());
        await sdk.ShutdownAsync();
        Assert.Equal(["GET /gameserver ", "POST /ready {}", "POST /health {}", "PUT /metadata/label {\"key\":\"map\",\"value\":\"garden\"}",
                      "GET /gameserver ", "POST /shutdown {}"], sidecar.Requests);
    }

    [Fact]
    public async Task WaitingForAMissingSidecarGivesUpInsteadOfThrowing()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        int port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();   // nothing listens there now
        var sdk = new AgonesRest(new HttpClient { BaseAddress = new Uri($"http://localhost:{port}/"), Timeout = TimeSpan.FromSeconds(1) });
        Assert.False(await sdk.WaitForSidecarAsync(attempts: 2, every: TimeSpan.FromMilliseconds(20)));
    }
}
