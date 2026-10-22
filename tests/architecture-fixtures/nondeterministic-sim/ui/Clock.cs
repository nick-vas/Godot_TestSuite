using System;

namespace Fixture.Ui;

// Outside the simulation folder: reading the clock for a HUD is fine.
public static class Clock
{
    public static string Now() => DateTime.Now.ToShortTimeString() + Math.Sin(1);
}
