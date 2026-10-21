using Godot;

public partial class SaveLoader : Node
{
    public Resource LoadSlot(int slot) => ResourceLoader.Load<Resource>($"user://saves/slot{slot}.tres");
}
