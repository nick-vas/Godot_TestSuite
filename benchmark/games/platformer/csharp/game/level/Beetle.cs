namespace GlowmossRidge;

using Godot;

/// <summary>
/// A beetle walking back and forth on its platform. It moves itself, so pausing the tree stops it; the game decides
/// what touching it does. Its speed, points and colour come from data/beetles.json by kind.
/// </summary>
/// <remarks><c>kind</c> and <c>patrol</c> keep the names the level scenes use: the scenes are shared with the GDScript version.</remarks>
public partial class Beetle : Node3D
{
    public static readonly Vector3 Size = new(0.9f, 0.6f, 0.8f);

    [Export]
    public string kind { get; set; } = "crawler";

    /// <summary>How far either side of where it was placed it walks.</summary>
    [Export]
    public float patrol { get; set; } = 2f;

    private float _homeX;
    private float _direction = -1f;

    public float Speed { get; private set; } = 1.5f;

    public int Points { get; private set; } = 50;

    public override void _Ready()
    {
        _homeX = Position.X;
    }

    /// <summary>Takes its kind's row; an unknown kind keeps the defaults.</summary>
    public void Setup(BeetleRow? row)
    {
        Speed = row?.Speed ?? Speed;
        Points = row?.Points ?? Points;
        GetNode<MeshInstance3D>("Mesh").MaterialOverride = Level.FlatMaterial(new Color(row?.Color ?? "#a05030"));
    }

    public override void _PhysicsProcess(double delta)
    {
        float x = Position.X + _direction * Speed * (float)delta;
        if (x < _homeX - patrol)
        {
            x = _homeX - patrol;
            _direction = 1f;
        }
        else if (x > _homeX + patrol)
        {
            x = _homeX + patrol;
            _direction = -1f;
        }
        Position = new Vector3(x, Position.Y, Position.Z);
    }
}
