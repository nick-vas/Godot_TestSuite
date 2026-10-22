# Hiding lag in each mechanic: Halo: Reach (godot-multiplayer reference)

Halo: Reach's rules for each mechanic (`docs/gdc/halo-reach-networking.md`):

- **Predict the look, let the host decide the outcome.** A grenade throw animates on the button press; the grenade
  exists only when the host creates it, a round trip after the release frame. Behind the moving arm, players did not
  notice 100 to 150 ms of that delay (casual players 200 ms).
- **Ask where the lag is hidden.** Draw the mechanic as a sequence diagram of client and host with sloped arrows. If
  the host decides something and no step waits for a round trip, the lag has not gone: it returns as a warp, an unfair
  result or reconciling code.
- **Change the mechanic when that hides the lag.** Reach's armour lock turns on 3 frames after the press; the host
  shortens that delay by the user's measured round trip, so the shield lands when the user sees it and only others
  see it early. Halo 3's "healthier player wins the melee trade" felt random at a few hundred ms and was simplified.
- **Warp the logic, blend the look.** On a correction, move logical and physics state at once (no pushing through thin
  walls) and blend only the mesh and the hit shapes back with a short exponential blend. In Godot, set the body's
  transform and give its visual child (and hitbox `Area3D`s) an offset that decays to zero. With this, Reach sent
  vehicles as few as 5 updates a second instead of 15 to 20.

