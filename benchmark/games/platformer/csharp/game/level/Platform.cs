namespace GlowmossRidge;

using Godot;

/// <summary>A block of the level. Its collision box and its look come from size, so a level is a list of positions and sizes.</summary>
/// <remarks><c>size</c> and <c>color</c> keep the names the level scenes use: the scenes are shared with the GDScript version.</remarks>
public partial class Platform : StaticBody3D
{
    [Export]
    public Vector3 size { get; set; } = new(4, 1, 2);

    [Export]
    public Color color { get; set; } = new("#4d6b3c");

    public override void _Ready()
    {
        GetNode<CollisionShape3D>("Shape").Shape = new BoxShape3D { Size = size };
        var mesh = GetNode<MeshInstance3D>("Mesh");
        mesh.Mesh = new BoxMesh { Size = size };
        mesh.MaterialOverride = Level.FlatMaterial(color);
        // A strip of moss along the top, so the surface to land on reads at a glance.
        var top = GetNode<MeshInstance3D>("Top");
        top.Mesh = new BoxMesh { Size = new Vector3(size.X, 0.18f, size.Z + 0.02f) };
        top.Position = new Vector3(top.Position.X, size.Y / 2f - 0.09f, top.Position.Z);
        top.MaterialOverride = Level.FlatMaterial(new Color("#8fd16a"));
    }
}
