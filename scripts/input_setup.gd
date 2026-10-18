extends RefCounted
## Registers every control for keyboard/mouse AND controller (Xbox / PlayStation layout).

static func setup() -> void:
	# menus: A picks, B backs out, D-pad and left stick move between buttons (Godot's ui_* defaults leave
	# some of these out)
	_ui_joy("ui_accept", JOY_BUTTON_A)
	_ui_joy("ui_cancel", JOY_BUTTON_B)
	_ui_joy("ui_up", JOY_BUTTON_DPAD_UP)
	_ui_joy("ui_down", JOY_BUTTON_DPAD_DOWN)
	_ui_joy("ui_left", JOY_BUTTON_DPAD_LEFT)
	_ui_joy("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_ui_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_ui_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_ui_axis("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_ui_axis("ui_right", JOY_AXIS_LEFT_X, 1.0)
	if InputMap.has_action("laser"):
		return
	_key("move_forward", KEY_W); _axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_key("move_back", KEY_S); _axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_key("move_left", KEY_A); _axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_key("move_right", KEY_D); _axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	# arrow keys look around (for laptop touchpads that shut off while keys are held)
	_key("look_left", KEY_LEFT); _axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_key("look_right", KEY_RIGHT); _axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_key("look_up", KEY_UP); _axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_key("look_down", KEY_DOWN); _axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_key("jump", KEY_SPACE); _joy("jump", JOY_BUTTON_A)
	_key("crouch", KEY_C); _key("crouch", KEY_CTRL); _joy("crouch", JOY_BUTTON_B)
	_key("sprint", KEY_SHIFT); _joy("sprint", JOY_BUTTON_LEFT_STICK)
	_key("reload", KEY_R); _joy("reload", JOY_BUTTON_X)
	_mouse("fire", MOUSE_BUTTON_LEFT); _key("fire", KEY_E); _axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_mouse("aim", MOUSE_BUTTON_RIGHT); _key("aim", KEY_Q); _axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_key("pause", KEY_ESCAPE); _joy("pause", JOY_BUTTON_START)
	_key("laser", KEY_T); _joy("laser", JOY_BUTTON_DPAD_LEFT)


static func _ui_joy(action: String, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	_ensure(action)
	if not InputMap.action_has_event(action, e):
		InputMap.action_add_event(action, e)


static func _ui_axis(action: String, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	_ensure(action)
	if not InputMap.action_has_event(action, e):
		InputMap.action_add_event(action, e)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


static func _key(action: String, key: Key) -> void:
	_ensure(action)
	var e := InputEventKey.new()
	e.physical_keycode = key
	InputMap.action_add_event(action, e)


static func _mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


static func _joy(action: String, button: JoyButton) -> void:
	_ensure(action)
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


static func _axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)
