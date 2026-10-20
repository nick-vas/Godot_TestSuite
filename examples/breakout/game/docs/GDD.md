# Breakout: game design document

<!-- The kit's example. Feature headings and GDD:F<n> tags in the tests are what `godot-ci.ps1 status` reads. -->

## Pitch

Break every brick on each floor without losing your last ball, picking an upgrade after each floor.

## Pillars

1. Every hit is readable: the ball's angle depends only on where it meets the paddle.
2. Combos reward keeping the ball up, not grinding.
3. A run is short enough to start another one.

Mostly challenge, then sensation (hits that feel good), then discovery (upgrade combinations).

## Core loop

Aim the ball with the paddle, chain brick hits for a combo multiplier, clear the floor, pick an upgrade, go down a floor.

## Features

### F1 Paddle and ball
Priority: must
Fun: challenge, sensation
Done when:
- A hit at the paddle's edge sends the ball up and sideways; a centre hit sends it straight up.

### F2 Bricks, score and combo
Priority: must
Fun: challenge, sensation
Done when:
- The first floor has three rows of ten bricks.
- Breaking a brick scores, and every fifth brick in a row raises the multiplier; a paddle hit resets it.

### F3 Lives and game over
Priority: must
Fun: challenge
Done when:
- A run starts on floor one with three lives and ends when the last ball is lost.

### F4 Floors and upgrades
Priority: should
Fun: discovery, expression
Done when:
- Clearing a floor applies the chosen upgrade (extra life, wide paddle or fast ball).

### F5 Title screen
Priority: could
Done when:
- The game starts on a title screen with Play and Quit.

## Content

One floor layout, three upgrades.

## Screens

The arena, at 640x480, scaled to the window.

## Out of scope

Power-ups that drop from bricks, multiplayer, saving a run.
