extends Node
# Steam calls with deliberate mistakes for tests/Test-Steam.ps1, against steam/rich_presence.vdf and
# steam/achievements.json: a misspelt achievement and stat, a token missing from the file, and a value that is not a
# token. GodotSteam's GDScript API.

const FLOOR_TOKEN := "#Status_Floor"


func on_floor_cleared(floor_number: int) -> void:
	Steam.setAchievement("ACH_FIRST_FLOOR")
	Steam.setAchievement("ACH_FRIST_FLOOR")
	Steam.setStatInt("bricks_broken", floor_number)
	Steam.setStatInt("brick_broken", floor_number)
	Steam.setRichPresence("floor", str(floor_number))
	Steam.setRichPresence("steam_display", "#Status_Floor")
	Steam.storeStats()


func on_lobby() -> void:
	Steam.setRichPresence("steam_display", "#Status_Lobby")


func on_quit() -> void:
	Steam.setRichPresence("steam_display", "Quitting")
	Steam.setRichPresence("steam_display", "")
