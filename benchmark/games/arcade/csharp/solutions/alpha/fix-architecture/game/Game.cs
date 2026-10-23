namespace OrbitPatrol;

using System.Collections.Generic;
using Godot;

/// <summary>
/// One run of the game: the ship, the waves, the shots and what they hit, the HUD and pause. Main starts it with Setup();
/// on its own (a flow, a test, the editor) it reads the command line and the data files itself. Everything happens in
/// _PhysicsProcess at a fixed 60 ticks, and every random choice comes from one seeded generator, so a seed replays a run.
/// </summary>
/// <remarks>
/// <c>level</c>, <c>state</c> and <c>start_level</c> keep the names the UI flows use: the flows are shared, word for word,
/// with the GDScript version of this game.
/// </remarks>
public partial class Game : Node2D
{
    public const float ShipY = 650f;
    public const float ShipSpeed = 420f;
    public static readonly Vector2 ShipSize = new(48, 32);
    public const float ShipMinX = 40f;
    public const float ShipMaxX = 1240f;
    public const float ShotSpeed = 720f;
    public const float EnemyShotSpeed = 260f;
    public const float FireCooldown = 0.18f;
    public const float WaveDelay = 1f;
    public const float ScreenBottom = 740f;
    public const float ColumnWidth = 80f;
    public const int Columns = 17;
    /// <summary>Enemies are filed under every column they reach plus this margin, so a shot on a column's edge still finds them.</summary>
    public const float ColumnMargin = 6f;

    private static readonly StringName MoveLeft = "move_left";
    private static readonly StringName MoveRight = "move_right";
    private static readonly StringName FireAction = "fire";

    [Signal]
    public delegate void FinishedEventHandler(bool victory, int points);

    [Signal]
    public delegate void QuitRequestedEventHandler();

    private readonly RandomNumberGenerator _rng = new();
    private int _ticks;
    private float _cooldown;
    private float _nextWaveIn = -1f;
    private int _spawned;
    /// <summary>The enemies in each column of the screen, refilled every tick; kept so the pass allocates nothing.</summary>
    private readonly List<Enemy>[] _columns = new List<Enemy>[Columns];

    private Texture2D _shotTexture = null!;
    private Texture2D _enemyShotTexture = null!;
    private Texture2D _enemyTexture = null!;
    private Texture2D _bossTexture = null!;
    private Label _scoreLabel = null!;
    private Label _livesLabel = null!;
    private Button _pauseButton = null!;
    private PauseMenu _pauseMenu = null!;
    private AudioStreamPlayer _sfxLaser = null!;

    public Score Score { get; } = new();
    public Rules Rules { get; } = new();
    public Waves? Waves { get; private set; }
    public LaunchOptions? Options { get; private set; }
    public Sprite2D Ship { get; private set; } = null!;
    public Node2D Enemies { get; private set; } = null!;
    public Node2D Shots { get; private set; } = null!;

    /// <summary>The level being played (flows read it).</summary>
    public int level { get; private set; } = 1;

    /// <summary>"playing", "won" or "lost" (flows read it).</summary>
    public string state { get; private set; } = "playing";

    public int WaveIndex { get; private set; }

    /// <summary>How many shot-against-enemy tests the collision pass has made, for the performance test.</summary>
    public int CollisionChecks { get; set; }

    public void Setup(Waves waves, LaunchOptions options, int best = 0)
    {
        Waves = waves;
        Options = options;
        Score.Best = best;
    }

    public override void _Ready()
    {
        _shotTexture = GD.Load<Texture2D>("res://art/shot.png");
        _enemyShotTexture = GD.Load<Texture2D>("res://art/enemy_shot.png");
        _enemyTexture = GD.Load<Texture2D>("res://art/enemy.png");
        _bossTexture = GD.Load<Texture2D>("res://art/boss.png");
        Ship = GetNode<Sprite2D>("Ship");
        Enemies = GetNode<Node2D>("Enemies");
        Shots = GetNode<Node2D>("Shots");
        _scoreLabel = GetNode<Label>("HUD/ScoreLabel");
        _livesLabel = GetNode<Label>("HUD/LivesLabel");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _sfxLaser = GetNode<AudioStreamPlayer>("SfxLaser");

        Options ??= LaunchOptions.Parse(OS.GetCmdlineUserArgs());
        Waves ??= Waves.FromFiles();
        _rng.Seed = Options.RunSeed;
        for (int i = 0; i < Columns; i++)
            _columns[i] = new List<Enemy>();
        Score.Changed += UpdateHud;
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => EmitSignal(SignalName.QuitRequested);
        Ship.Position = new Vector2(640, ShipY);
        RefreshText();
        start_level(Options.Level);
    }

    public override void _ExitTree()
    {
        Score.Changed -= UpdateHud;
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _pauseButton.Text = Tr("HUD_PAUSE");
        UpdateHud();
    }

    private void UpdateHud()
    {
        _scoreLabel.Text = TextFormat.Fill(Tr("HUD_SCORE"), Score.Points);
        _livesLabel.Text = TextFormat.Fill(Tr("HUD_LIVES"), Rules.Lives);
    }

    /// <summary>Starts a level from its first wave (flows call it to jump to a level).</summary>
    public void start_level(int number)
    {
        level = number;
        WaveIndex = 0;
        _spawned = 0;
        _nextWaveIn = -1f;
        Clear(Enemies);
        Clear(Shots);
        SpawnWave();
    }

    /// <summary>Game time in milliseconds: physics ticks, never the wall clock.</summary>
    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    public override void _PhysicsProcess(double delta)
    {
        if (state != "playing")
            return;
        float step = (float)delta;
        _ticks += 1;
        Rules.Tick(delta);
        MoveShip(step);
        EnemiesFire(step);
        ResolveShotHits();
        ResolveShipHits();
        RemoveSpentShots();
        AdvanceWaves(step);
    }

    private void MoveShip(float delta)
    {
        float direction = Input.GetAxis(MoveLeft, MoveRight);
        bool firing = Input.IsActionPressed(FireAction);
        Ship.Position = new Vector2(Mathf.Clamp(Ship.Position.X + direction * ShipSpeed * delta, ShipMinX, ShipMaxX), Ship.Position.Y);
        Ship.Visible = !Rules.IsInvulnerable || (_ticks / 6) % 2 == 0;
        _cooldown -= delta;
        if (firing && _cooldown <= 0f && state == "playing")
        {
            _cooldown = FireCooldown;
            SpawnShot(Ship.Position + new Vector2(0, -24), new Vector2(0, -ShotSpeed), false);
            _sfxLaser.Play();
        }
    }

    private void EnemiesFire(float delta)
    {
        foreach (Node node in Enemies.GetChildren())
        {
            var enemy = (Enemy)node;
            if (enemy.Fire <= 0f)
                continue;
            enemy.FireTimer -= delta;
            if (enemy.FireTimer > 0f)
                continue;
            enemy.FireTimer = enemy.Fire * _rng.RandfRange(0.7f, 1.3f);
            SpawnShot(enemy.Position + new Vector2(0, enemy.Size.Y / 2f), new Vector2(0, EnemyShotSpeed), true);
        }
    }

    /// <summary>
    /// Tests the ship's shots against the enemies in their own column of the screen only: with a full wave and a stream of
    /// shots, testing every shot against every enemy is most of a frame.
    /// </summary>
    public void ResolveShotHits()
    {
        foreach (List<Enemy> column in _columns)
            column.Clear();
        foreach (Node node in Enemies.GetChildren())
        {
            var enemy = (Enemy)node;
            float half = enemy.Size.X / 2f + ColumnMargin;
            for (int c = ColumnOf(enemy.Position.X - half); c <= ColumnOf(enemy.Position.X + half); c++)
                _columns[c].Add(enemy);
        }
        foreach (Node node in Shots.GetChildren())
        {
            var shot = (Shot)node;
            if (shot.Hostile || shot.Spent)
                continue;
            foreach (Enemy enemy in _columns[ColumnOf(shot.Position.X)])
            {
                CollisionChecks += 1;
                if (enemy.Hp > 0 && Overlaps(shot.Position, shot.Size, enemy.Position, enemy.Size))
                {
                    ShotHitEnemy(shot, enemy);
                    break;
                }
            }
        }
    }

    private static int ColumnOf(float x) => Mathf.Clamp((int)(x / ColumnWidth), 0, Columns - 1);

    private static bool Overlaps(Vector2 a, Vector2 aSize, Vector2 b, Vector2 bSize) =>
        Mathf.Abs(a.X - b.X) * 2f < aSize.X + bSize.X && Mathf.Abs(a.Y - b.Y) * 2f < aSize.Y + bSize.Y;

    private void ShotHitEnemy(Shot shot, Enemy enemy)
    {
        shot.Spent = true;
        int gained = Rules.HitEnemy(enemy);
        if (enemy.Hp <= 0)
        {
            Score.Hit(gained);
            EnemyDestroyed(enemy);
        }
    }

    private void EnemyDestroyed(Enemy enemy)
    {
        Enemies.RemoveChild(enemy);
        enemy.QueueFree();
    }

    private void ResolveShipHits()
    {
        foreach (Node node in Shots.GetChildren())
        {
            var shot = (Shot)node;
            if (shot.Hostile && !shot.Spent && Overlaps(shot.Position, shot.Size, Ship.Position, ShipSize))
            {
                shot.Spent = true;
                ShipHit();
            }
        }
        foreach (Node node in Enemies.GetChildren())
        {
            var enemy = (Enemy)node;
            if (Overlaps(enemy.Position, enemy.Size, Ship.Position, ShipSize) && ShipHit() && !enemy.Boss)
            {
                Enemies.RemoveChild(enemy);
                enemy.QueueFree();
            }
        }
    }

    /// <summary>True when the hit cost a life (not while invulnerable).</summary>
    private bool ShipHit()
    {
        if (state != "playing" || !Rules.ShipHit())
            return false;
        Score.Miss();
        UpdateHud();
        if (Rules.IsGameOver)
            Finish(false);
        return true;
    }

    private void RemoveSpentShots()
    {
        foreach (Node node in Shots.GetChildren())
        {
            var shot = (Shot)node;
            bool gone = shot.Position.Y < -20f || shot.Position.Y > ScreenBottom;
            if (gone && !shot.Hostile && !shot.Spent)
                Score.Miss();
            if (gone || shot.Spent)
            {
                Shots.RemoveChild(shot);
                shot.QueueFree();
            }
        }
    }

    private void AdvanceWaves(float delta)
    {
        if (state != "playing" || Enemies.GetChildCount() > 0)
            return;
        if (_nextWaveIn < 0f)
        {
            _nextWaveIn = WaveDelay;
            return;
        }
        _nextWaveIn -= delta;
        if (_nextWaveIn > 0f)
            return;
        _nextWaveIn = -1f;
        WaveIndex += 1;
        SpawnWave();
    }

    private void SpawnWave()
    {
        IReadOnlyList<WaveRow> rows = Waves!.WavesOf(level);
        if (WaveIndex >= rows.Count)
        {
            LevelDone();
            return;
        }
        WaveRow row = rows[WaveIndex];
        EnemyRow? enemyRow = Waves.Enemy(row.Enemy);
        if (enemyRow == null)
        {
            GD.PushError($"Level {level} names an unknown enemy '{row.Enemy}'");
            return;
        }
        foreach (Vector2 at in Formation(row.Formation, row.Count))
            SpawnEnemy(enemyRow, row.Speed, at);
    }

    private void LevelDone()
    {
        GD.Print($"[Run] level {level} done");
        if (level >= Waves!.LevelCount)
        {
            GD.Print("[Run] victory");
            Finish(true);
        }
        else
        {
            start_level(level + 1);
        }
    }

    private static List<Vector2> Formation(string kind, int count)
    {
        var points = new List<Vector2>(count);
        int columns = kind == "grid" ? Mathf.Min(count, 6) : count;
        float spacing = Mathf.Min(110f, 1100f / Mathf.Max(columns, 1));
        for (int i = 0; i < count; i++)
        {
            int column = i % columns;
            float x = 640f + (column - (columns - 1) / 2f) * spacing;
            float y = 100f;
            if (kind == "v")
                y += Mathf.Abs(i - (count - 1) / 2f) * 30f;
            else if (kind == "grid")
                y += (i / columns) * 60f;
            points.Add(new Vector2(x, y));
        }
        return points;
    }

    public Enemy SpawnEnemy(EnemyRow row, float speed, Vector2 at)
    {
        var enemy = new Enemy();
        _spawned += 1;
        enemy.Name = $"Enemy{_spawned}";
        enemy.Texture = row.Boss ? _bossTexture : _enemyTexture;
        enemy.Setup(row, speed, at);
        enemy.FireTimer = enemy.Fire * _rng.RandfRange(0.5f, 1.5f);
        Enemies.AddChild(enemy);
        return enemy;
    }

    public Shot SpawnShot(Vector2 at, Vector2 velocity, bool hostile)
    {
        var shot = new Shot
        {
            Texture = hostile ? _enemyShotTexture : _shotTexture,
            Hostile = hostile,
            Size = hostile ? new Vector2(8, 14) : new Vector2(6, 16),
            Position = at,
            Velocity = velocity,
        };
        Shots.AddChild(shot);
        return shot;
    }

    private void Finish(bool victory)
    {
        state = victory ? "won" : "lost";
        if (!victory)
            GD.Print("[Run] game over");
        EmitSignal(SignalName.Finished, victory, Score.Points);
        // On its own (the prototype, or a flow) nobody listens; a bot run then ends here.
        if (Options!.Autoplay && GetSignalConnectionList(SignalName.Finished).Count == 0)
            GetTree().Quit();
    }

    private static void Clear(Node parent)
    {
        foreach (Node child in parent.GetChildren())
        {
            parent.RemoveChild(child);
            child.QueueFree();
        }
    }
}
