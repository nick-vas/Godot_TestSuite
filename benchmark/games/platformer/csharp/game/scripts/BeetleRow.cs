namespace GlowmossRidge;

/// <summary>A row of data/beetles.json: walking speed (metres a second), the points a stomp scores, the colour "#rrggbb".</summary>
public sealed record BeetleRow(string Id, float Speed, int Points, string Color);
