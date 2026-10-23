namespace GlowmossRidge.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: on a 16:9 screen the camera keeps the climber in view at the foot and the top
/// of The Climb, and never shows past the level's edges. What the view shows is worked out here from Camera3D's own
/// rule (an orthographic size is the height of the view), not from the game's code.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenCameraTest
{
    private Vector2I _windowSize;

    private static SceneTree Tree => (SceneTree)Engine.GetMainLoop();

    private static async Task PhysicsFrames(int count)
    {
        for (int i = 0; i < count; i++)
            await Tree.ToSignal(Tree, SceneTree.SignalName.PhysicsFrame);
    }

    [BeforeTest]
    public void SixteenByNine()
    {
        _windowSize = Tree.Root.Size;
        Tree.Root.Size = new Vector2I(1280, 720);
    }

    [AfterTest]
    public void RestoreWindow()
    {
        Tree.Root.Size = _windowSize;
    }

    private static Vector2 HalfView(Game game)
    {
        Vector2 view = game.GetViewport().GetVisibleRect().Size;
        float halfHeight = game.Camera.Size / 2f;
        return new Vector2(halfHeight * view.X / view.Y, halfHeight);
    }

    private static void AssertClimberInView(Game game, string where)
    {
        Vector2 half = HalfView(game);
        Vector3 camera = game.Camera.Position;
        Vector3 feet = game.Player.Position;
        AssertThat(Mathf.Abs(feet.X - camera.X) <= half.X - 0.4f).OverrideFailureMessage($"{where}: across, climber {feet.X:0.00}, view {camera.X:0.00} +- {half.X:0.00}").IsTrue();
        AssertThat(feet.Y >= camera.Y - half.Y).OverrideFailureMessage($"{where}: feet {feet.Y:0.00} above the bottom of the view {camera.Y - half.Y:0.00}").IsTrue();
        AssertThat(feet.Y + 1f <= camera.Y + half.Y).OverrideFailureMessage($"{where}: head {feet.Y + 1f:0.00} below the top of the view {camera.Y + half.Y:0.00}").IsTrue();
    }

    [TestCase]
    public async Task Hidden_the_climber_is_in_view_at_the_foot_of_the_climb()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(2);
        game.start_level(3);
        await PhysicsFrames(60);
        AssertClimberInView(game, "the foot of the climb");
    }

    [TestCase]
    public async Task Hidden_the_climber_is_in_view_at_the_top_of_the_climb()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(2);
        game.start_level(3);
        var top = new Aabb();
        foreach (Aabb box in game.Current.PlatformBoxes())
        {
            if (box.End.Y > top.End.Y)
                top = box;
        }
        game.Player.Place(new Vector3(top.GetCenter().X, top.End.Y, 0));
        await PhysicsFrames(120);
        AssertClimberInView(game, "the top of the climb");
    }

    [TestCase]
    public async Task Hidden_the_view_stays_inside_the_level()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(32);
        Vector2 half = HalfView(game);
        Aabb bounds = game.Current.Bounds();
        AssertThat(game.Camera.Position.X - half.X >= bounds.Position.X - 0.01f).OverrideFailureMessage("the view starts inside the level").IsTrue();
        AssertThat(game.Camera.Position.Y - half.Y >= bounds.Position.Y - 0.01f).OverrideFailureMessage("the view's bottom is inside the level").IsTrue();
        AssertClimberInView(game, "the start of level 1");
    }
}
