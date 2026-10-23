using System.Net.Http.Json;
using System.Text.Json;

namespace Example.Core.Net;

/// <summary>
/// Agones' SDK over plain HTTP: the sidecar listens on localhost (<c>AGONES_SDK_HTTP_PORT</c>, 9358 by default), so a
/// Godot C# server needs only <see cref="HttpClient"/>, not the gRPC packages of the official C# SDK. The same calls work
/// against <c>sdk-server --local</c> on a developer's machine, with no cluster. A fleet manager of your own can serve the
/// same few endpoints and the server will not know the difference.
/// Calls are asynchronous on Agones' side: read the state back (<see cref="StateAsync"/>) rather than trusting a 200.
/// </summary>
public sealed class AgonesRest(HttpClient http)
{
    public static AgonesRest FromEnvironment(TimeSpan? timeout = null)
    {
        string port = Environment.GetEnvironmentVariable("AGONES_SDK_HTTP_PORT") is { Length: > 0 } p ? p : "9358";
        return new AgonesRest(new HttpClient { BaseAddress = new Uri($"http://localhost:{port}/"), Timeout = timeout ?? TimeSpan.FromSeconds(5) });
    }

    public Task ReadyAsync(CancellationToken ct = default) => PostAsync("ready", ct);
    public Task HealthAsync(CancellationToken ct = default) => PostAsync("health", ct);
    public Task AllocateAsync(CancellationToken ct = default) => PostAsync("allocate", ct);
    public Task ShutdownAsync(CancellationToken ct = default) => PostAsync("shutdown", ct);

    /// <summary>A label a matchmaker can select on (Agones stores it as <c>agones.dev/sdk-{key}</c>).</summary>
    public async Task SetLabelAsync(string key, string value, CancellationToken ct = default) =>
        (await http.PutAsJsonAsync("metadata/label", new { key, value }, ct)).EnsureSuccessStatusCode();

    /// <summary>The state Agones holds for this server: Scheduled, RequestReady, Ready, Allocated, Shutdown, Unhealthy...</summary>
    public async Task<string> StateAsync(CancellationToken ct = default)
    {
        using var doc = JsonDocument.Parse(await http.GetStringAsync("gameserver", ct));
        return doc.RootElement.GetProperty("status").GetProperty("state").GetString() ?? "";
    }

    /// <summary>
    /// The sidecar may start after the game: retry the first call (Agones' Unity SDK tries 30 times, a second apart)
    /// instead of failing the server on its first connection refused.
    /// </summary>
    public async Task<bool> WaitForSidecarAsync(int attempts = 30, TimeSpan? every = null, CancellationToken ct = default)
    {
        for (int i = 0; i < attempts; i++)
        {
            try { await StateAsync(ct); return true; }
            catch (HttpRequestException) { }
            catch (TaskCanceledException) when (!ct.IsCancellationRequested) { }   // the request timed out
            await Task.Delay(every ?? TimeSpan.FromSeconds(1), ct);
        }
        return false;
    }

    async Task PostAsync(string path, CancellationToken ct)
    {
        using var body = new StringContent("{}", System.Text.Encoding.UTF8, "application/json");
        (await http.PostAsync(path, body, ct)).EnsureSuccessStatusCode();
    }
}
