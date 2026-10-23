namespace GlowmossRidge;

using Godot;

/// <summary>A patch of thorns on the ground: touching it hurts. Its width comes from size; the spikes are drawn from it.</summary>
/// <remarks><c>size</c> keeps the name the level scenes use: the scenes are shared with the GDScript version.</remarks>
public partial class Thorns : Node3D
{
    public const float SpikeWidth = 0.5f;

    [Export]
    public Vector3 size { get; set; } = new(1.5f, 0.5f, 1f);

    public override void _Ready()
    {
        int count = Mathf.Max(1, Mathf.RoundToInt(size.X / SpikeWidth));
        var spike = new PrismMesh { Size = new Vector3(size.X / count, size.Y, size.Z) };
        StandardMaterial3D material = Level.FlatMaterial(new Color("#c23b4b"));
        for (int i = 0; i < count; i++)
        {
            AddChild(new MeshInstance3D
            {
                Mesh = spike,
                MaterialOverride = material,
                Position = new Vector3(-size.X / 2f + (i + 0.5f) * size.X / count, size.Y / 2f, 0),
            });
        }
    }
}
