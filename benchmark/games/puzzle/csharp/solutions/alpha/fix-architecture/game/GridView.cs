namespace Frostmote;

using System.Collections.Generic;
using Godot;

/// <summary>
/// Draws a board: walls, ice, snow, the exit (dim while closed, bright once open) and the sparks still out. The mote is
/// the child sprite Mote, which the game moves along a slide.
/// </summary>
public partial class GridView : Node2D
{
    public const float TileSize = 60f;
    private static readonly Color WallColor = new(0.16f, 0.22f, 0.34f);
    private static readonly Color IceColor = new(0.62f, 0.8f, 0.92f);
    private static readonly Color SnowColor = new(0.94f, 0.96f, 1f);
    private static readonly Color ExitClosed = new(0.35f, 0.42f, 0.5f);
    private static readonly Color ExitOpen = new(0.3f, 0.85f, 0.55f);

    /// <summary>The sparks drawn: those the board has left, plus, during a slide, those the mote has not reached yet.</summary>
    private readonly List<Vector2I> _sparks = new();
    private Texture2D _sparkTexture = null!;
    private Board? _board;

    public Sprite2D Mote { get; private set; } = null!;

    public override void _Ready()
    {
        _sparkTexture = GD.Load<Texture2D>("res://art/spark.png");
        Mote = GetNode<Sprite2D>("Mote");
    }

    /// <summary>Shows a board centred on a point of the screen, the mote on its tile.</summary>
    public void ShowBoard(Board shown, Vector2 center)
    {
        _board = shown;
        Position = (center - new Vector2(shown.Width, shown.Height) * TileSize / 2f).Round();
        ShowSparks(shown.Sparks);
        PlaceMote(shown.Position, shown.Position, 1f);
    }

    public void ShowSparks(IEnumerable<Vector2I> cells)
    {
        _sparks.Clear();
        _sparks.AddRange(cells);
        QueueRedraw();
    }

    /// <summary>The mote a share t of the way along a slide.</summary>
    public void PlaceMote(Vector2I from, Vector2I to, float t)
    {
        Mote.Position = CellCenter(from).Lerp(CellCenter(to), Mathf.Clamp(t, 0f, 1f));
    }

    public static Vector2 CellCenter(Vector2I cell) => (new Vector2(cell.X, cell.Y) + new Vector2(0.5f, 0.5f)) * TileSize;

    public override void _Draw()
    {
        if (_board == null)
            return;
        for (int y = 0; y < _board.Height; y++)
        {
            for (int x = 0; x < _board.Width; x++)
            {
                var rect = new Rect2(new Vector2(x, y) * TileSize, new Vector2(TileSize, TileSize));
                switch (_board.Tile(new Vector2I(x, y)))
                {
                    case Board.Wall:
                        DrawRect(rect, WallColor);
                        break;
                    case Board.Snow:
                        DrawRect(rect, SnowColor);
                        break;
                    default:
                        DrawRect(rect, IceColor);
                        DrawRect(rect, IceColor.Darkened(0.12f), false, 1f);
                        break;
                }
            }
        }
        Rect2 exitRect = new Rect2(new Vector2(_board.Exit.X, _board.Exit.Y) * TileSize, new Vector2(TileSize, TileSize)).Grow(-8f);
        DrawRect(exitRect, _sparks.Count == 0 ? ExitOpen : ExitClosed);
        foreach (Vector2I cell in _sparks)
            DrawTexture(_sparkTexture, CellCenter(cell) - _sparkTexture.GetSize() / 2f);
    }
}
