using System.Numerics;
using Example.Core.Determinism;

namespace Example.Core.Procgen;

/// <summary>What a room is to a player passing through, from its exit count (up and down count too: a shaft is a hallway).</summary>
public enum RoomRole { DeadEnd, Hallway, Junction }

public enum Spawn { Loot, Trap, Enemy }

/// <summary>
/// Placement by topology, as Eldritch ended up doing it: loot only in dead ends (a detour always pays, and a dead end is
/// never on the way to anywhere), traps in hallways where there is no choice to make and in dead ends to guard the loot,
/// enemies at junctions where the player can route around them. Then a population cap with a safe zone round the start.
/// </summary>
public static class Placement
{
    public static RoomRole Role(Exits e) => BitOperations.PopCount((uint)e) switch
    {
        <= 1 => RoomRole.DeadEnd,
        2 => RoomRole.Hallway,
        _ => RoomRole.Junction,
    };

    public static bool Allows(Spawn spawn, RoomRole role) => spawn switch
    {
        Spawn.Loot => role == RoomRole.DeadEnd,
        Spawn.Trap => role is RoomRole.Hallway or RoomRole.DeadEnd,
        _ => role == RoomRole.Junction,
    };

    /// <summary>Rooms (set pieces excluded) where this kind of spawn belongs.</summary>
    public static IReadOnlyList<Cell> Rooms(Maze maze, Spawn spawn) =>
        maze.Cells.Where(c => maze.SetPieceAt(c) == null && Allows(spawn, Role(maze[c]))).ToList();

    /// <summary>
    /// Eldritch's "resolve groups": from every candidate spawner, drop those fewer than <paramref name="minRooms"/> rooms'
    /// walk from <paramref name="start"/>, then keep a random <paramref name="keep"/> of the rest. The cap sets the population
    /// (a dozen enemies early in the game, two dozen late) whatever the modules offer.
    /// </summary>
    public static IReadOnlyList<Cell> ResolveGroup(Maze maze, IReadOnlyList<Cell> spawners, int keep, Cell start, int minRooms, ulong seed)
    {
        var rng = new DeterministicRandom(Maze.Mix(seed));
        int[] dist = maze.Distances(start);
        var pool = spawners.Where(c => dist[maze.Index(c)] >= minRooms).ToList();
        for (int i = pool.Count - 1; i > 0; i--)
        {
            int j = rng.Next(i + 1);
            (pool[i], pool[j]) = (pool[j], pool[i]);
        }
        return pool.Take(keep).ToList();
    }
}
