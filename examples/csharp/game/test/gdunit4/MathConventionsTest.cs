namespace Example.Tests;

using Godot;
using static GdUnit4.Assertions;
using GdUnit4;
using Numerics = System.Numerics;

// The conventions godot-math's table states, on Godot's own types (the "maths book" is Burzynski's Mathematics for Game
// Developers): a positive yaw turns a -Z-facing object to its left, Right x Up is +Z, and a cross product's length is
// the parallelogram's area (the book's <1, -2, -4> and <4, 3, -5>: 26.94, half for the triangle). Example.Core computes
// with System.Numerics, which agrees on handedness and yaw but has no Forward and composes matrices the other way round:
// those differences are pinned here too, so code moved between the two is checked.
[TestSuite]
[RequireGodotRuntime]
public class MathConventionsTest
{
    const float HalfPi = Mathf.Pi / 2;

    static void AssertNear(Vector3 actual, Vector3 expected) =>
        AssertThat(actual.IsEqualApprox(expected)).OverrideFailureMessage($"{actual}, expected {expected}").IsTrue();

    [TestCase]
    public void APositiveYawTurnsForwardToTheLeft()
    {
        AssertThat(Vector3.Forward).IsEqual(new Vector3(0, 0, -1));
        AssertNear(Vector3.Forward.Rotated(Vector3.Up, HalfPi), new Vector3(-1, 0, 0));
        AssertNear(Vector3.Forward.Rotated(Vector3.Up, -HalfPi), Vector3.Right);   // turning right is a negative angle

        var node = new Node3D();
        node.RotateY(HalfPi);
        AssertNear(-node.Basis.Z, new Vector3(-1, 0, 0));                         // the node's forward after the turn
        node.Free();

        // 2D is the other way on screen: y is down, so a positive angle turns clockwise.
        AssertThat(Vector2.Right.Rotated(HalfPi).IsEqualApprox(Vector2.Down)).IsTrue();
    }

    [TestCase]
    public void TheCrossProductIsRightHandedAndItsLengthIsTheArea()
    {
        AssertThat(Vector3.Right.Cross(Vector3.Up)).IsEqual(new Vector3(0, 0, 1));
        var a = new Vector3(1, -2, -4);
        var b = new Vector3(4, 3, -5);
        AssertThat(a.Cross(b)).IsEqual(new Vector3(22, -11, 11));
        AssertThat(a.Cross(b).Length()).IsEqualApprox(26.94f, 0.005f);            // the parallelogram
        AssertThat(a.Cross(b).Length() / 2).IsEqualApprox(13.47f, 0.005f);        // the triangle
        AssertThat(b.Cross(a)).IsEqual(-a.Cross(b));                               // order flips the normal, not the area
        // 2D: a number, positive when b is clockwise from a on screen.
        AssertThat(Vector2.Right.Cross(Vector2.Down)).IsEqual(1f);
    }

    [TestCase]
    public void SystemNumericsAgreesOnYawAndCrossButComposesTheOtherWay()
    {
        var turned = Numerics.Vector3.Transform(-Numerics.Vector3.UnitZ, Numerics.Quaternion.CreateFromAxisAngle(Numerics.Vector3.UnitY, HalfPi));
        AssertNear(new Vector3(turned.X, turned.Y, turned.Z), new Vector3(-1, 0, 0));
        AssertThat(Numerics.Vector3.Cross(Numerics.Vector3.UnitX, Numerics.Vector3.UnitY)).IsEqual(Numerics.Vector3.UnitZ);

        // Yaw then pitch, written both ways. Godot's a * b applies b first; System.Numerics' row vectors apply the left
        // matrix first. The same written order gives different results.
        var yaw = new Basis(Vector3.Up, HalfPi);
        var pitch = new Basis(Vector3.Right, HalfPi);
        AssertNear(yaw * pitch * Vector3.Forward, Vector3.Up);                     // pitch first: up
        AssertNear(pitch * yaw * Vector3.Forward, new Vector3(-1, 0, 0));                           // yaw first: left
        var numerics = Numerics.Vector3.Transform(-Numerics.Vector3.UnitZ,
            Numerics.Matrix4x4.CreateRotationY(HalfPi) * Numerics.Matrix4x4.CreateRotationX(HalfPi));
        AssertNear(new Vector3(numerics.X, numerics.Y, numerics.Z), new Vector3(-1, 0, 0));         // yaw first, as written
    }
}
