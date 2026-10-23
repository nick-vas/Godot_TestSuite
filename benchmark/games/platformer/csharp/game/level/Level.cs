namespace GlowmossRidge;

using System.Collections.Generic;
using Godot;

/// <summary>
/// A level scene: Start (a Marker3D where the climber's feet appear), Platforms, Moss, Beetles, Thorns, Checkpoints and
/// the Beacon that ends it. Pieces are placed by their origin: a platform's centre, everything else's foot.
/// </summary>
public partial class Level : Node3D
{
    /// <summary>Below the lowest platform by this much, the climber has fallen out.</summary>
    public const float FallMargin = 4f;
    /// <summary>Sky kept above the highest platform, so the camera can show a jump from it.</summary>
    public const float SkyMargin = 6f;

    private Node3D? _platforms;
    private Node3D? _moss;
    private Node3D? _beetles;
    private Node3D? _thorns;
    private Node3D? _checkpoints;
    private Node3D? _beacon;

    // Found once, on first use, so a level a test makes without adding it to the tree can be read too.
    public Node3D Platforms => _platforms ??= GetNode<Node3D>("Platforms");
    public Node3D Moss => _moss ??= GetNode<Node3D>("Moss");
    public Node3D Beetles => _beetles ??= GetNode<Node3D>("Beetles");
    public Node3D Thorns => _thorns ??= GetNode<Node3D>("Thorns");
    public Node3D Checkpoints => _checkpoints ??= GetNode<Node3D>("Checkpoints");
    public Node3D Beacon => _beacon ??= GetNode<Node3D>("Beacon");

    public Vector3 StartPosition() => GetNode<Marker3D>("Start").Position;

    /// <summary>Each platform's box in the level, for the bot and the camera.</summary>
    public List<Aabb> PlatformBoxes()
    {
        var boxes = new List<Aabb>();
        foreach (Node node in Platforms.GetChildren())
        {
            var block = (Platform)node;
            boxes.Add(new Aabb(block.Position - block.size / 2f, block.size));
        }
        return boxes;
    }

    /// <summary>What the camera may show: the platforms, with sky above them.</summary>
    public Aabb Bounds()
    {
        List<Aabb> boxes = PlatformBoxes();
        Aabb all = boxes[0];
        foreach (Aabb box in boxes)
            all = all.Merge(box);
        all.Size += new Vector3(0, SkyMargin, 0);
        return all;
    }

    public float FallHeight() => Bounds().Position.Y - FallMargin;

    /// <summary>A flat colour that needs no light, the look of every piece of the game.</summary>
    public static StandardMaterial3D FlatMaterial(Color color) => new()
    {
        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
        AlbedoColor = color,
    };
}
