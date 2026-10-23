extends GutTest
## Hidden check for the release's fix-store: the library capsule is Steam's 600x900.


func _png_size(path: String) -> Vector2i:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 24 or bytes[1] != 0x50:
		return Vector2i.ZERO
	var w := (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19]
	var h := (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23]
	return Vector2i(w, h)


func test_hidden_library_capsule_is_600_by_900():
	assert_eq(_png_size("res://store/steam/library_capsule.png"), Vector2i(600, 900))
