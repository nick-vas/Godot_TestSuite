extends SceneTree
# Writes the engine's own licence data as JSON (what a credits/licences screen can show at run time).
func _init():
	var out := {
		"version": Engine.get_version_info()["string"],
		"licenseText": Engine.get_license_text(),
		"copyright": Engine.get_copyright_info(),
		"licenses": Engine.get_license_info(),
	}
	var path: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://engine-notices.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote ", path)
	quit()
