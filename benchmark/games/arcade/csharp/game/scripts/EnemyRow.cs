namespace OrbitPatrol;

/// <summary>A row of data/enemies.json: hit points, points, sideways drift (pixels), seconds between shots (0: never fires).</summary>
public sealed record EnemyRow(string Id, int Hp, int Points, float Drift, float Fire, string Color, bool Boss);
