namespace OrbitPatrol;

using Godot;

/// <summary>The end of a won run.</summary>
public partial class Victory : ResultScreen
{
    protected override void RefreshText()
    {
        GetNode<Label>("Box/Title").Text = Tr("VICTORY_TITLE");
        GetNode<Label>("Box/Message").Text = TextFormat.Fill(Tr("VICTORY_MESSAGE"), Points);
        GetNode<Button>("Box/MenuButton").Text = Tr("VICTORY_MENU");
    }
}
