using Example.Core.Determinism;

namespace Example.Core.Ai;

/// <summary>
/// One player's "emotional intensity", as Left 4 Dead's AI Director estimates it (Michael Booth, "The AI Systems of
/// Left 4 Dead", AIIDE 2009): a single number that rises when the player is hurt, knocked down, dragged off a ledge or
/// sees an enemy die close by, and decays toward zero, but not while enemies are still on them. Booth: "Survivor
/// Intensity estimation is crude, yet the resulting pacing works". The weights are not in the talk; the defaults here
/// put a heavy hit near the peak threshold of <see cref="PacingOptions"/>.
/// </summary>
public sealed class Intensity
{
    readonly PacingOptions _options;

    public Intensity(PacingOptions? options = null) => _options = options ?? new PacingOptions();

    /// <summary>0 is calm; it is capped at 1.</summary>
    public float Value { get; private set; }

    /// <summary>Hurt by an enemy: in proportion to the damage, as a share of full health.</summary>
    public void Damaged(float damage, float maxHealth) => Add(_options.DamageWeight * Math.Max(0, damage) / Math.Max(1, maxHealth));

    /// <summary>Knocked down and waiting for a teammate.</summary>
    public void Incapacitated() => Add(_options.IncapacitatedBoost);

    /// <summary>Pulled or pushed off a ledge by an enemy.</summary>
    public void OffLedge() => Add(_options.LedgeBoost);

    /// <summary>An enemy died near the player: the closer, the more it counts (inversely proportional to distance).</summary>
    public void EnemyDiedNearby(float distance) => Add(_options.NearbyKillWeight / Math.Max(_options.NearbyKillMinDistance, distance));

    /// <summary>Decays toward zero, unless an enemy is actively engaging the player.</summary>
    public void Tick(float seconds, bool engaged)
    {
        if (!engaged) Value = Math.Max(0, Value - _options.DecayPerSecond * seconds);
    }

    void Add(float amount) => Value = Math.Clamp(Value + amount, 0, 1);
}

/// <summary>The Director's four phases, in order; Relax leads back to Build Up.</summary>
public enum PacingPhase
{
    /// <summary>Full threat population until the team's intensity crosses the peak threshold.</summary>
    BuildUp,
    /// <summary>Full population for a few more seconds after the peak, so the build-up has a minimum length.</summary>
    SustainPeak,
    /// <summary>Minimal population while intensity decays out of the peak range; Relax waits for a break in the fight.</summary>
    PeakFade,
    /// <summary>Minimal population for 30-45 s, or until the team has travelled far enough.</summary>
    Relax,
}

public sealed record PacingOptions
{
    /// <summary>Team intensity at which Build Up ends. Not given in the talk.</summary>
    public float PeakThreshold { get; init; } = 0.8f;
    /// <summary>Peak Fade ends when the team's intensity is below this ("decays out of peak range"). Not given in the talk.</summary>
    public float FadeBelow { get; init; } = 0.5f;
    /// <summary>In Relax, wanderers come back only once the team is this calm ("No Wanderers until team is calm").</summary>
    public float CalmBelow { get; init; } = 0.2f;
    /// <summary>Booth: "Continue full threat population for 3-5 seconds after Survivor Intensity has peaked".</summary>
    public float SustainMinSeconds { get; init; } = 3f;
    public float SustainMaxSeconds { get; init; } = 5f;
    /// <summary>Booth: "Maintain minimal threat population for 30-45 seconds".</summary>
    public float RelaxMinSeconds { get; init; } = 30f;
    public float RelaxMaxSeconds { get; init; } = 45f;
    /// <summary>"or until Survivors have traveled far enough toward the next safe room". In world units.</summary>
    public float RelaxDistance { get; init; } = 60f;

    public float DamageWeight { get; init; } = 1.5f;
    public float IncapacitatedBoost { get; init; } = 0.6f;
    public float LedgeBoost { get; init; } = 0.5f;
    public float NearbyKillWeight { get; init; } = 0.1f;
    public float NearbyKillMinDistance { get; init; } = 1f;
    public float DecayPerSecond { get; init; } = 0.05f;
}

/// <summary>
/// Left 4 Dead's adaptive dramatic pacing: the team's intensity (the highest of its players) drives four phases, and the
/// phase decides what may spawn. It changes when threats come, never how strong they are: "Amplitude (difficulty) is
/// not changed, frequency (pacing) is". Boss encounters are outside it ("Overall pacing affected too much if they are
/// missing"): spawn them on their own schedule and do not ask the director. Its generator is a <see cref="DeterministicRandom"/>
/// the game seeds from the run seed, so a run replays exactly and <see cref="RandomState"/> can go in a save.
/// </summary>
public sealed class PacingDirector
{
    readonly PacingOptions _options;
    DeterministicRandom _random;
    float _phaseTime;
    float _phaseLength;
    float _travelled;

    public PacingDirector(DeterministicRandom random, PacingOptions? options = null)
    {
        _options = options ?? new PacingOptions();
        _random = random;
    }

    /// <summary>The generator's state now: save it with the phase, and restore it with <c>new DeterministicRandom(state)</c>.</summary>
    public ulong RandomState => _random.State;

    public PacingPhase Phase { get; private set; } = PacingPhase.BuildUp;

    /// <summary>Wanderers, mobs and special enemies: Build Up and Sustain Peak only.</summary>
    public bool FullPopulation => Phase is PacingPhase.BuildUp or PacingPhase.SustainPeak;

    /// <summary>Mobs and special enemies may spawn. Specials already alive may still attack in any phase.</summary>
    public bool MaySpawnMobs => FullPopulation;

    /// <summary>Wandering enemies: with the full population, or in Relax once the team is calm.</summary>
    public bool MaySpawnWanderers { get; private set; } = true;

    /// <param name="seconds">Time since the last tick.</param>
    /// <param name="teamIntensity">The highest <see cref="Intensity.Value"/> among the players.</param>
    /// <param name="engaged">An enemy is fighting any player now; Peak Fade waits for a natural break.</param>
    /// <param name="travelled">Distance the team moved toward the goal since the last tick.</param>
    public void Tick(float seconds, float teamIntensity, bool engaged, float travelled)
    {
        _phaseTime += seconds;
        switch (Phase)
        {
            case PacingPhase.BuildUp:
                if (teamIntensity >= _options.PeakThreshold) Enter(PacingPhase.SustainPeak, Between(_options.SustainMinSeconds, _options.SustainMaxSeconds));
                break;
            case PacingPhase.SustainPeak:
                if (_phaseTime >= _phaseLength) Enter(PacingPhase.PeakFade, 0);
                break;
            case PacingPhase.PeakFade:
                if (teamIntensity < _options.FadeBelow && !engaged) Enter(PacingPhase.Relax, Between(_options.RelaxMinSeconds, _options.RelaxMaxSeconds));
                break;
            case PacingPhase.Relax:
                _travelled += Math.Max(0, travelled);
                if (_phaseTime >= _phaseLength || _travelled >= _options.RelaxDistance) Enter(PacingPhase.BuildUp, 0);
                break;
        }
        MaySpawnWanderers = FullPopulation || (Phase == PacingPhase.Relax && teamIntensity < _options.CalmBelow);
    }

    /// <summary>The team's intensity: the most stressed player sets the pace.</summary>
    public static float TeamIntensity(IEnumerable<Intensity> players)
    {
        var highest = 0f;
        foreach (var p in players) highest = Math.Max(highest, p.Value);
        return highest;
    }

    void Enter(PacingPhase phase, float length)
    {
        Phase = phase;
        _phaseTime = 0;
        _phaseLength = length;
        _travelled = 0;
    }

    float Between(float min, float max) => min + (float)_random.NextDouble() * (max - min);
}
