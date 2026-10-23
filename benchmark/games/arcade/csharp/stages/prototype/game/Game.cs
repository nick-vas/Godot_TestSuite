namespace OrbitPatrol;

using Godot;

/// <summary>
/// The prototype: the ship, its shots and one wave of six grunts. Everything happens in _PhysicsProcess at a fixed
/// 60 ticks; the score and the lives live in Score and Rules, which the tests cover.
/// </summary>
public partial class Game : Node2D
{
    public const float ShipY = 650f;
    public const float ShipSpeed = 420f;
    public static readonly Vector2 ShipSize = new(48, 32);
    public const float ShipMinX = 40f;
    public const float ShipMaxX = 1240f;
    public const float ShotSpeed = 720f;
    public const float FireCooldown = 0.18f;
    public const float ScreenBottom = 740f;
    /// <summary>The one wave of the prototype.</summary>
    public static readonly EnemyRow Grunt = new("grunt", 1, 100, 0, 0, "#e05050", false);
    public const int WaveSize = 6;
    public const float WaveSpeed = 40f;

    private static readonly StringName MoveLeft = "move_left";
    private static readonly StringName MoveRight = "move_right";
    private static readonly StringName FireAction = "fire";

    [Signal]
    public delegate void FinishedEventHandler(bool victory, int points);

    private int _ticks;
    private float _cooldown;
    private int _spawned;
    private Texture2D _shotTexture = null!;
    private Texture2D _enemyTexture = null!;
    private Label _scoreLabel = null!;
    private Label _livesLabel = null!;

    public Score Score { get; } = new();
    public Rules Rules { get; } = new();
    public Sprite2D Ship { get; private set; } = null!;
    public Node2D Enemies { get; private set; } = null!;
    public Node2D Shots { get; private set; } = null!;

    /// <summary>"playing", "won" or "lost" (flows read it).</summary>
    public string state { get; private set; } = "playing";

    public override void _Ready()
    {
        _shotTexture = GD.Load<Texture2D>("res://art/shot.png");
        _enemyTexture = GD.Load<Texture2D>("res://art/enemy.png");
        Ship = GetNode<Sprite2D>("Ship");
        Enemies = GetNode<Node2D>("Enemies");
        Shots = GetNode<Node2D>("Shots");
        _scoreLabel = GetNode<Label>("HUD/ScoreLabel");
        _livesLabel = GetNode<Label>("HUD/LivesLabel");
        Score.Changed += UpdateHud;
        Ship.Position = new Vector2(640, ShipY);
        UpdateHud();
        for (int i = 0; i < WaveSize; i++)
        {
            const float spacing = 110f;
            SpawnEnemy(Grunt, WaveSpeed, new Vector2(640f + (i - (WaveSize - 1) / 2f) * spacing, 100f));
        }
    }

    public override void _ExitTree()
    {
        Score.Changed -= UpdateHud;
    }

    private void UpdateHud()
    {
        _scoreLabel.Text = $"Score: {Score.Points}";
        _livesLabel.Text = $"Lives: {Rules.Lives}";
    }

    public override void _PhysicsProcess(double delta)
    {
        if (state != "playing")
            return;
        _ticks += 1;
        Rules.Tick(delta);
        MoveShip((float)delta);
        ResolveShotHits();
        ResolveShipHits();
        RemoveSpentShots();
        if (Enemies.GetChildCount() == 0)
        {
            GD.Print("[Run] level 1 done");
            Finish(true);
        }
    }

    private void MoveShip(float delta)
    {
        float direction = Input.GetAxis(MoveLeft, MoveRight);
        Ship.Position = new Vector2(Mathf.Clamp(Ship.Position.X + direction * ShipSpeed * delta, ShipMinX, ShipMaxX), Ship.Position.Y);
        Ship.Visible = !Rules.IsInvulnerable || (_ticks / 6) % 2 == 0;
        _cooldown -= delta;
        if (Input.IsActionPressed(FireAction) && _cooldown <= 0f)
        {
            _cooldown = FireCooldown;
            SpawnShot(Ship.Position + new Vector2(0, -24), new Vector2(0, -ShotSpeed));
        }
    }

    private void ResolveShotHits()
    {
        foreach (Node shotNode in Shots.GetChildren())
        {
            var shot = (Shot)shotNode;
            if (shot.Spent)
                continue;
            foreach (Node enemyNode in Enemies.GetChildren())
            {
                var enemy = (Enemy)enemyNode;
                if (enemy.Hp > 0 && Overlaps(shot.Position, shot.Size, enemy.Position, enemy.Size))
                {
                    shot.Spent = true;
                    int gained = Rules.HitEnemy(enemy);
                    if (enemy.Hp <= 0)
                    {
                        Score.Hit(gained);
                        Enemies.RemoveChild(enemy);
                        enemy.QueueFree();
                    }
                    break;
                }
            }
        }
    }

    private void ResolveShipHits()
    {
        foreach (Node node in Enemies.GetChildren())
        {
            var enemy = (Enemy)node;
            if (Overlaps(enemy.Position, enemy.Size, Ship.Position, ShipSize) && Rules.ShipHit())
            {
                Score.Miss();
                UpdateHud();
                Enemies.RemoveChild(enemy);
                enemy.QueueFree();
                if (Rules.IsGameOver)
                {
                    GD.Print("[Run] game over");
                    Finish(false);
                }
            }
        }
    }

    private void RemoveSpentShots()
    {
        foreach (Node node in Shots.GetChildren())
        {
            var shot = (Shot)node;
            bool gone = shot.Position.Y < -20f || shot.Position.Y > ScreenBottom;
            if (gone && !shot.Spent)
                Score.Miss();
            if (gone || shot.Spent)
            {
                Shots.RemoveChild(shot);
                shot.QueueFree();
            }
        }
    }

    private static bool Overlaps(Vector2 a, Vector2 aSize, Vector2 b, Vector2 bSize) =>
        Mathf.Abs(a.X - b.X) * 2f < aSize.X + bSize.X && Mathf.Abs(a.Y - b.Y) * 2f < aSize.Y + bSize.Y;

    public Enemy SpawnEnemy(EnemyRow row, float speed, Vector2 at)
    {
        var enemy = new Enemy();
        _spawned += 1;
        enemy.Name = $"Enemy{_spawned}";
        enemy.Texture = _enemyTexture;
        enemy.Setup(row, speed, at);
        Enemies.AddChild(enemy);
        return enemy;
    }

    public Shot SpawnShot(Vector2 at, Vector2 velocity)
    {
        var shot = new Shot { Texture = _shotTexture, Position = at, Velocity = velocity };
        Shots.AddChild(shot);
        return shot;
    }

    private void Finish(bool victory)
    {
        state = victory ? "won" : "lost";
        EmitSignal(SignalName.Finished, victory, Score.Points);
    }
}
