namespace GlowmossRidge;

using Godot;

/// <summary>The end of a lost run: its score and the best.</summary>
public partial class GameOver : ResultScreen
{
    protected override void RefreshText()
    {
        GetNode<Label>("Box/Title").Text = Tr("GAMEOVER_TITLE");
        GetNode<Label>("Box/ScoreLabel").Text = TextFormat.Fill(Tr("GAMEOVER_SCORE"), Points);
        GetNode<Label>("Box/BestLabel").Text = TextFormat.Fill(Tr("GAMEOVER_BEST"), Best);
        GetNode<Button>("Box/MenuButton").Text = Tr("GAMEOVER_MENU");
    }
}
