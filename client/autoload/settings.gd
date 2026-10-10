class_name Settings
## Player preferences, saved to user://settings.cfg. A static class rather than an autoload
## node: anything can read Settings.invert_y directly, and nothing has to be registered in
## project.godot. Change a value, then call Settings.save().

const PATH := "user://settings.cfg"

static var invert_y := false  # mouse up looks down (flight-stick style)


static func _static_init() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	invert_y = cfg.get_value("controls", "invert_y", invert_y)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # keep any keys this version doesn't know about
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.save(PATH)
