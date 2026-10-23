class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --level=N.

var autoplay := false
var run_seed := 0
var no_save := false
var level := 1


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--autoplay":
			options.autoplay = true
		elif arg == "--no-save":
			options.no_save = true
		elif arg.begins_with("--seed="):
			options.run_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--level="):
			options.level = maxi(1, int(arg.get_slice("=", 1)))
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
