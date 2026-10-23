# Solving an Invisible Problem: Designing for Color-Blindness in Games

- Speaker: Douglas Pennant (spelling as transcribed; the surname may be "Pennant" or similar), associate development manager
  at Creative Assembly, himself a deuteranope. Earlier QA work on Alien: Isolation and Kinect Star Wars; Halo Wars 2.
- Year: not stated. Most likely GDC 2019, inferred from "Fortnite, as of November, 125 million players", a talk at the Game
  Accessibility Conference that week about the Xbox Adaptive Controller, and Halo Wars 2 as his team's last release.
- Video: https://www.youtube.com/watch?v=KbFs9ghIIEI

## What the talk teaches

1. **The problem is invisible to whoever has it.** A colour-blind tester cannot report a cue he never sees (the Working Joes'
   eyes in Alien: Isolation changed colour when hostile; he learned it a month or two before ship), and people with normal
   colour vision do not know it is broken. Someone has to start the conversation and test on purpose.
2. **Cover the three dichromacies** (protanopia, deuteranopia, tritanopia): they are the extreme ends of the milder anomalous
   kinds, so supporting them covers those too. About 1 in 12 men and 1 in 200 women are colour blind; deuteranopia is about
   three quarters of colour-blind men, protanopia about a quarter, tritanopia about 1 in 10,000 and equal across sexes.
3. **Where games go wrong:** team colours, units that blend into the ground, colour-matching puzzles, health shown as
   green-yellow-red, crowded minimaps, racing lines that turn red to brake, glowing eyes as the only sign of aggression.
4. **Never colour alone** (WCAG 1.4.1): Hue adds symbols, FTL crosshatches rooms without oxygen, Mass Effect keeps its two
   dialogue choices in fixed places.
5. **Blue and orange for pairs that must never be confused.** In his words: "If you have two things and you can't have them
   get mixed up, blue and orange, every time." Not for total colour blindness, unless the brightness differs too.
6. **Semantic colour presets.** Pick colours for friendly, enemy and faction A once, from a colour-safe palette; artists and
   designers tag by meaning; a preset that fails a test is fixed in one place. Test the presets in context, with simulators
   (Color Oracle, Sim Daltonism, Coblis, Unity and Unreal packages) and with colour-blind people.
7. **Let players pick the colours** (AudioSurf, Overwatch's enemy and friendly colours, Battlefield 1's hue picker). Asked
   whether he prefers a whole-screen correction filter: no, change the UI; "I don't need the entire screen to change color."
8. **Make the options findable** (Fortnite's Accessibility tab). Its tritanopia mode is used by many players who are not
   tritanopes, because it reads more clearly.

## What the kit took

- `shot -ColorVision protan,deutan,tritan` (`ci/godot/tools/shot.gd`, `ci/godot/lib/Measure.ps1`, `ci/godot/hyperdot.ps1`):
  every screenshot is also saved as `<name>.protan.png`, `.deutan.png`, `.tritan.png`, listed in `shots[].colorVision`
  (`docs/json.md`). The model is Machado, Oliveira and Fernandes (2009), severity 1.0, applied in linear RGB: sRGB decode,
  matrix, clamp, encode. The matrices are the authors' published table; their page (inf.ufrgs.br/~oliveira) could not be
  reached from here, so they were checked against three implementations that agree to six decimals: colorspacious
  (`cvd.py`, which says it downloaded them from that page), colour-science (`blindness/datasets/machado2010.py`) and
  DaltonLens-Python (`simulate.py`).
- `tests/Test-ColorVision.ps1` with `tests/colorvision-fixture` (in the `measure` job of `self-test.yml`).
- `godot-ui-accessibility`: colours defined once by meaning, blue and orange for must-not-confuse pairs, player-chosen marker
  colours, recolour markers and UI rather than filter the screen, and the `-ColorVision` check. `look`: critique the
  simulated pictures.

## Measured

- Fixture swatches, CIE76 ΔE between brick red #C84610 and leaf green #328200: 94.4 seen normally, 12.0 as a protanope,
  11.4 as a deuteranope. Blue #377EB8 and orange #FF7F00: 121 normally, 99, 115 and 98 in the three simulations. Every
  simulated swatch is within 1/255 of the matrix computed in PowerShell; grey stays grey.
- The red and green the triage first proposed (ColorBrewer #E41A1C and #4DAF4A) stay 32 (protan) and 21 (deutan) apart, because
  they differ in lightness: brightness alone still separates them, which is why the fixture uses a pair of similar lightness.
- Applying the matrix to sRGB values directly (the common mistake) is off by up to 26/255 and understates the collapse: red and
  green come out 20 apart for a protanope instead of 12. The self-test fails on that version (13 checks).
- Speed at 1920x1080 under Xvfb with software OpenGL (llvmpipe), Godot 4.7.2: a per-pixel GDScript loop takes 1.3 s per kind;
  the shader, one `SubViewport` per kind, takes about 250 ms for all three including the read-back, and saving the three PNGs
  about 300 ms. A GPU makes the shader part faster still.

## What it did not take, and why

- Achromatopsia (about 1 in 30,000) and the milder anomalous kinds: the talk covers the dichromacies on purpose, and
  severity 1.0 is the worst case of each.
- DaltonLens notes that Machado's model is less accurate for tritanopia than Brettel (1997); the tritan picture is a guide,
  not a diagnosis. A colour-blind tester remains the real check, as the talk insists.
- A colour-blind mode or colour picker in the C# example: the rule is in the skill; the kit's part is letting an agent see the screens.
