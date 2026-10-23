using Example.Core.Level;
using Xunit;

namespace Example.Core.Tests;

public sealed class SoftLockTests
{
    // Hall has one key and two locked doors: the closet (nothing inside) and the exit. A key rack that hands out
    // another key whenever the player has none is the fix.
    static SoftLockLevel Vault(bool keyRack)
    {
        var level = new SoftLockLevel();
        int hall = level.Area("Hall"), closet = level.Area("Closet"), exit = level.Area("Exit");
        int key = level.Item("key");
        level.Pickup(hall, key)
            .Passage(hall, closet, "closet door", uses: key)
            .Passage(hall, exit, "exit door", uses: key)
            .Goal(exit);
        if (keyRack) level.Supply(hall, key, name: "key rack");
        return level;
    }

    [Fact]
    public void ALevelWithEnoughOfEverythingIsSafe()
    {
        var level = new SoftLockLevel();
        int hall = level.Area("Hall"), armory = level.Area("Armory"), cave = level.Area("Cave"), exit = level.Area("Exit");
        int key = level.Item("key"), ammo = level.Item("ammo", max: 6);
        level.Pickup(hall, key)
            .Pickup(armory, ammo, 3)
            .Passage(hall, armory)
            .Passage(hall, cave, "iron gate", uses: key)
            .Passage(cave, exit, "cracked wall", uses: ammo, useCount: 3)
            .Goal(exit);

        var result = SoftLockCheck.Run(level);
        Assert.True(result.Safe, result.ToString());
        Assert.Empty(result.Steps);
        Assert.Equal(0, result.DeadEndStates);
        Assert.Equal(15, result.States);   // 4 before the key, 4 holding it, 6 with the gate open, the exit
        Assert.Equal(result.States, SoftLockCheck.Run(level).States);   // deterministic
    }

    [Fact]
    public void AKeySpentOnTheWrongDoorIsFoundWithTheStepsThatLeadThere()
    {
        var result = SoftLockCheck.Run(Vault(keyRack: false));
        Assert.False(result.Safe);
        Assert.Equal(["pick up key in Hall", "use key on closet door, go Hall -> Closet"], result.Steps);
        Assert.Equal("Closet, holding nothing", result.StuckAt);
        Assert.Equal(2, result.DeadEndStates);   // in the closet, and back in the hall with the closet open
        Assert.Equal(5, result.States);
    }

    [Fact]
    public void ADeliveryTubeFixesABoxThatCanBeDestroyed()
    {
        // Portal: the exit door opens while a box sits on its button, and the box can fall into the goo.
        static SoftLockLevel Chamber(bool tube)
        {
            var level = new SoftLockLevel();
            int chamber = level.Area("Chamber"), exit = level.Area("Exit");
            int box = level.Item("box", canBeLost: true, start: 1);
            level.Passage(chamber, exit, "door", oneWay: true, needs: box).Goal(exit);
            if (tube) level.Supply(chamber, box, name: "delivery tube");
            return level;
        }

        var locked = SoftLockCheck.Run(Chamber(tube: false));
        Assert.Equal(["lose box"], locked.Steps);
        Assert.Equal("Chamber, holding nothing", locked.StuckAt);
        Assert.True(SoftLockCheck.Run(Chamber(tube: true)).Safe);

        // The same fix for the key: a rack that gives another key when the player has none.
        Assert.True(SoftLockCheck.Run(Vault(keyRack: true)).Safe);
    }

    [Fact]
    public void AOneWayDropBeforeTheKeyAndAnUnreachableGoalAreReported()
    {
        var level = new SoftLockLevel();
        int ledge = level.Area("Ledge"), pit = level.Area("Pit"), exit = level.Area("Exit");
        int key = level.Item("key");
        level.Pickup(ledge, key)
            .Passage(ledge, pit, oneWay: true)
            .Passage(pit, exit, "gate", uses: key)
            .Goal(exit);
        Assert.Equal(["go Ledge -> Pit"], SoftLockCheck.Run(level).Steps);

        var walled = new SoftLockLevel();
        walled.Area("Cell");
        walled.Goal(walled.Area("Outside"));
        var result = SoftLockCheck.Run(walled);
        Assert.False(result.Safe);
        Assert.Empty(result.Steps);
        Assert.Equal("Cell, holding nothing", result.StuckAt);
    }

    [Fact]
    public void LosingAnyItemIsTheStressTest()
    {
        // Safe as designed, but if the key could be destroyed (dropped in lava), the level locks.
        var level = new SoftLockLevel();
        int hall = level.Area("Hall"), exit = level.Area("Exit");
        int key = level.Item("key");
        level.Pickup(hall, key).Passage(hall, exit, "exit door", uses: key).Goal(exit);
        Assert.True(SoftLockCheck.Run(level).Safe);
        var stressed = SoftLockCheck.Run(level, everyItemCanBeLost: true);
        Assert.Equal(["pick up key in Hall", "lose key"], stressed.Steps);

        // The key rack survives any loss: a lost key is replaced in the hall.
        Assert.True(SoftLockCheck.Run(Vault(keyRack: true), everyItemCanBeLost: true).Safe);
    }

    [Fact]
    public void TooManyStatesStopsWithAClearError()
    {
        var level = new SoftLockLevel();
        int room = level.Area("Room");
        level.Goal(level.Area("Exit"));
        for (int i = 0; i < 8; i++)
        {
            int item = level.Item($"gem{i}", max: 7, canBeLost: true);
            level.Supply(room, item, upTo: 7);
        }
        var e = Assert.Throws<InvalidOperationException>(() => SoftLockCheck.Run(level, maxStates: 1000));
        Assert.Contains("stopped at 1000 states", e.Message);
        Assert.Contains("checkpoint", e.Message);
    }

    [Fact]
    public void AGameTestChecksItsLevelInTwoLines()
    {
        var level = Vault(keyRack: true);   // the game's own level, built from its data
        SoftLockCheck.AssertNoSoftLock(level);

        var e = Assert.Throws<SoftLockException>(() => SoftLockCheck.AssertNoSoftLock(Vault(keyRack: false)));
        Assert.Equal("Soft-lock after 2 step(s): pick up key in Hall; use key on closet door, go Hall -> Closet. " +
            "Stuck in Closet, holding nothing: 2 of 5 reachable states cannot reach the goal.", e.Message);
        Assert.False(e.Result.Safe);
    }
}
