using Godot;
public partial class Menu : Label
{
    public override void _Ready() => Text = Tr(@"VERBATIM_KEY") + MyTr("NOT_A_TRANSLATION_CALL");
    static string MyTr(string s) => s;
}
