namespace Example.Core.Telemetry;

/// <summary>
/// The sink of a playtest build: each batch becomes one line of <c>&lt;directory&gt;/&lt;session&gt;.jsonl</c>, the format
/// <c>hyperdot.ps1 playtest -Sessions</c> reads (a line a crash cut short is skipped there, with the rest of the file
/// kept). Collect the testers' folders into one per build and run the report on it. Nothing goes over the network, and
/// the <see cref="TelemetryClient"/> still hands it only what the player agreed to.
/// </summary>
public sealed class PlaytestFileSink : ITelemetrySink
{
    readonly SemaphoreSlim _gate = new(1, 1);

    public PlaytestFileSink(string directory, string sessionId)
    {
        if (sessionId.Length == 0 || sessionId.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-'))
            throw new ArgumentException($"'{sessionId}' is not a session id (letters, digits and '-')", nameof(sessionId));
        Directory = directory;
        File = Path.Combine(directory, sessionId + ".jsonl");
    }

    public string Directory { get; }
    public string File { get; }

    public async Task SendAsync(string batchJson, CancellationToken cancel)
    {
        if (batchJson.Contains('\n')) throw new ArgumentException("a batch is one line of JSON", nameof(batchJson));
        await _gate.WaitAsync(cancel).ConfigureAwait(false);
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            await System.IO.File.AppendAllTextAsync(File, batchJson + "\n", cancel).ConfigureAwait(false);
        }
        finally { _gate.Release(); }
    }
}
