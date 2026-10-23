namespace OrbitPatrol.Tests;

using System;
using System.IO;

/// <summary>The game's own files on disk, found from the test assembly (built under .godot/ inside the project).</summary>
public static class ProjectFiles
{
    public static string Root
    {
        get
        {
            for (DirectoryInfo? dir = new(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "project.godot")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException($"No project.godot above {AppContext.BaseDirectory}");
        }
    }

    public static string Read(string relative) => File.ReadAllText(Path.Combine(Root, relative));

    /// <summary>The real tables, read without the engine.</summary>
    public static Waves LoadWaves() => Waves.Parse(Read("data/enemies.json"), Read("data/levels.json"));
}
