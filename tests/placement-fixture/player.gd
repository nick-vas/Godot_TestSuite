# The fixture's gameplay code. test/test_placement.gd reads the limits from here, as a game's placement test must.
extends CharacterBody3D

## How high above the ground the player can light a wall torch, in metres.
const REACH := 2.5
