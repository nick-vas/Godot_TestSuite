using Example.Core.Determinism;
using Example.Core.Ai;
using Xunit;

namespace Example.Core.Tests;

public sealed class PacingDirectorTests
{
    [Fact]
    public void IntensityRisesWithHarmAndDecaysOnlyWhenNothingIsEngaging()
    {
        var i = new Intensity();
        i.Damaged(20, 100);
        Assert.Equal(0.3f, i.Value, 3);
        i.Tick(2, engaged: true);
        Assert.Equal(0.3f, i.Value, 3);   // still being attacked: no decay
        i.Tick(2, engaged: false);
        Assert.Equal(0.2f, i.Value, 3);
        i.Incapacitated();
        i.OffLedge();
        Assert.Equal(1f, i.Value);        // capped
        i.Tick(100, engaged: false);
        Assert.Equal(0f, i.Value);
    }

    [Fact]
    public void ANearbyKillCountsMoreTheCloserItIs()
    {
        var near = new Intensity();
        var far = new Intensity();
        near.EnemyDiedNearby(2);
        far.EnemyDiedNearby(8);
        Assert.Equal(4 * far.Value, near.Value, 4);
    }

    [Fact]
    public void TheMostStressedPlayerSetsTheTeamsIntensity()
    {
        var calm = new Intensity();
        var hurt = new Intensity();
        hurt.Damaged(40, 100);
        Assert.Equal(hurt.Value, PacingDirector.TeamIntensity([calm, hurt, new Intensity()]));
    }

    [Fact]
    public void ThePhasesFollowTheTalksTimings()
    {
        var d = new PacingDirector(new DeterministicRandom(1));
        Assert.Equal(PacingPhase.BuildUp, d.Phase);
        d.Tick(1, 0.5f, engaged: true, travelled: 0);
        Assert.True(d.MaySpawnMobs);

        d.Tick(1, 0.85f, engaged: true, travelled: 0);
        Assert.Equal(PacingPhase.SustainPeak, d.Phase);
        var sustained = 0f;
        while (d.Phase == PacingPhase.SustainPeak) { d.Tick(0.1f, 0.9f, true, 0); sustained += 0.1f; }
        Assert.InRange(sustained, 3f, 5.1f);   // "Continue full threat population for 3-5 seconds"

        Assert.Equal(PacingPhase.PeakFade, d.Phase);
        Assert.False(d.MaySpawnMobs);
        d.Tick(5, 0.3f, engaged: true, travelled: 0);
        Assert.Equal(PacingPhase.PeakFade, d.Phase);   // calm enough, but the fight is still going
        d.Tick(1, 0.3f, engaged: false, travelled: 0);
        Assert.Equal(PacingPhase.Relax, d.Phase);
        Assert.False(d.MaySpawnWanderers);              // not calm yet

        var relaxed = 0f;
        while (d.Phase == PacingPhase.Relax)
        {
            d.Tick(0.5f, 0.1f, false, 0);
            relaxed += 0.5f;
            if (d.Phase == PacingPhase.Relax) { Assert.True(d.MaySpawnWanderers); Assert.False(d.MaySpawnMobs); }
        }
        Assert.InRange(relaxed, 30f, 45.5f);            // "Maintain minimal threat population for 30-45 seconds"
        Assert.Equal(PacingPhase.BuildUp, d.Phase);
    }

    [Fact]
    public void RelaxEndsEarlyWhenTheTeamMovesOnFarEnough()
    {
        var d = new PacingDirector(new DeterministicRandom(2), new PacingOptions { RelaxDistance = 50 });
        d.Tick(1, 0.9f, true, 0);
        while (d.Phase == PacingPhase.SustainPeak) d.Tick(1, 0.9f, true, 0);
        d.Tick(1, 0.1f, false, 0);
        Assert.Equal(PacingPhase.Relax, d.Phase);
        for (var t = 0; t < 4; t++) d.Tick(1, 0.1f, false, 12);
        Assert.Equal(PacingPhase.Relax, d.Phase);       // 48 travelled
        d.Tick(1, 0.1f, false, 12);
        Assert.Equal(PacingPhase.BuildUp, d.Phase);
    }

    [Fact]
    public void TheSameSeedPacesTheSame()
    {
        static List<PacingPhase> Run(int seed)
        {
            var d = new PacingDirector(new DeterministicRandom((ulong)seed));
            var phases = new List<PacingPhase>();
            for (var t = 0; t < 600; t++) { d.Tick(1, t % 90 < 20 ? 0.9f : 0.1f, false, 0); phases.Add(d.Phase); }
            return phases;
        }
        Assert.Equal(Run(7), Run(7));
        Assert.NotEqual(Run(7), Run(8));   // the seed decides how long each Sustain Peak and Relax lasts
    }

    [Fact]
    public void AGameDrivenByTheDirectorGetsPeaksAndBreathers()
    {
        // A crude simulation: while mobs may spawn, the team keeps getting hurt; otherwise nothing happens. Over ten
        // minutes the director must produce repeated peaks, each followed by a quiet stretch of at least 30 s.
        var team = new[] { new Intensity(), new Intensity(), new Intensity(), new Intensity() };
        var d = new PacingDirector(new DeterministicRandom(3));
        var rng = new Random(3);
        int peaks = 0, quiet = 0, longestQuiet = 0, quietRun = 0;
        var last = d.Phase;
        for (var tick = 0; tick < 600 * 10; tick++)
        {
            var dt = 0.1f;
            var engaged = d.MaySpawnMobs;
            if (engaged && rng.NextDouble() < 0.08) team[rng.Next(team.Length)].Damaged(8, 100);
            foreach (var p in team) p.Tick(dt, engaged);
            d.Tick(dt, PacingDirector.TeamIntensity(team), engaged, 0);
            if (d.Phase == PacingPhase.SustainPeak && last != PacingPhase.SustainPeak) peaks++;
            if (!d.MaySpawnMobs) { quiet++; quietRun++; longestQuiet = Math.Max(longestQuiet, quietRun); } else quietRun = 0;
            last = d.Phase;
        }
        Assert.InRange(peaks, 4, 12);
        Assert.True(longestQuiet >= 300, $"longest quiet stretch {longestQuiet / 10f} s");
        Assert.InRange(quiet / 6000f, 0.3f, 0.8f);
    }
}
