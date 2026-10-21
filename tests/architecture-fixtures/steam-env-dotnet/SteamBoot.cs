using Godot;

public partial class SteamBoot : Node
{
    public override void _EnterTree() => System.Environment.SetEnvironmentVariable("SteamAppId", "480");
}
