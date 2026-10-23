class_name Level
extends Node3D
## A level scene: Start (a Marker3D where the climber's feet appear), Platforms, Moss, Beetles, Thorns, Checkpoints and
## the Beacon that ends it. Pieces are placed by their origin: a platform's centre, everything else's foot.

## Below the lowest platform by this much, the climber has fallen out.
const FALL_MARGIN := 4.0
## Sky kept above the highest platform, so the camera can show a jump from it.
const SKY_MARGIN := 6.0

@onready var platforms: Node3D = $Platforms
@onready var moss: Node3D = $Moss
@onready var beetles: Node3D = $Beetles
@onready var thorns: Node3D = $Thorns
@onready var checkpoints: Node3D = $Checkpoints
@onready var beacon: Node3D = $Beacon


func start_position() -> Vector3:
	return ($Start as Marker3D).position


## Each platform's box in the level, for the bot and the camera.
func platform_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for block: Platform in platforms.get_children():
		boxes.append(AABB(block.position - block.size / 2.0, block.size))
	return boxes


## What the camera may show: the platforms, with sky above them.
func bounds() -> AABB:
	var boxes := platform_boxes()
	var all := boxes[0]
	for box in boxes:
		all = all.merge(box)
	all.size.y += SKY_MARGIN
	return all


func fall_height() -> float:
	return bounds().position.y - FALL_MARGIN


## A flat colour that needs no light, the look of every piece of the game.
static func flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
