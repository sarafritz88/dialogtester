extends Control

# References to key nodes
@onready var npc_sprite: TextureRect = $NPCArea/NPCSprite
@onready var npc_name_label: Label = $NPCArea/NPCNameLabel
@onready var npc_text: Label = $DialogBox/MarginContainer/VBoxContainer/NPCText
@onready var choices_container: VBoxContainer = $DialogBox/MarginContainer/VBoxContainer/ChoicesMargin/ChoicesContainer

# Old-style font applied to all dialog text
var alien_font: FontFile = preload("res://fonts/Orbitron.ttf")

# --- Data Structures ---
# A DialogNode represents one step in a conversation.
# Replace or extend this with your own dialog generation tool's output.
class DialogNode:
	var npc_name: String
	var npc_line: String
	var choices: Array  # Array of Dicts: { "text": String, "next_id": int }

	func _init(name: String, line: String, opts: Array) -> void:
		npc_name = name
		npc_line = line
		choices = opts

# --- Dialog State ---
# Key: node ID (int), Value: DialogNode
var dialog_tree: Dictionary = {}
var current_node_id: int = 0

# Variables available for substitution in dialog text.
# Keys defined here can be overridden by the "variables" block in the JSON.
# Use {key} syntax in any npc_line or choice text — e.g. {player_name}.
var dialog_vars: Dictionary = {
	"player_name": "Traveler",
	"player_title": "Carbon Unit",
}

# Path to the dialog JSON file — swap this out to load a different conversation
const DIALOG_FILE := "res://dialog_data.json"

func _ready() -> void:
	# Apply font to the static NPC speech label in the dialog box
	npc_text.add_theme_font_override("font", alien_font)
	npc_text.add_theme_color_override("font_color", Color(0.5, 1.0, 0.85, 1.0))
	_update_font_sizes()
	get_viewport().size_changed.connect(_update_font_sizes)
	load_dialog_from_file(DIALOG_FILE)
	_register_js_bridge()

# Recalculates all font sizes relative to viewport height so text
# stays readable on any screen size — desktop, tablet, or mobile.
func _update_font_sizes() -> void:
	var vh: float = get_viewport().get_visible_rect().size.y
	var npc_text_size: int = int(vh * 0.035)   # ~25px on 720p, ~38px on 1080p
	var choice_size: int   = int(vh * 0.030)   # ~22px on 720p, ~32px on 1080p
	var name_size: int     = int(vh * 0.040)   # ~29px on 720p, ~43px on 1080p

	npc_text.add_theme_font_size_override("font_size", npc_text_size)
	npc_name_label.add_theme_font_size_override("font_size", name_size)

	# Re-apply to any existing choice buttons
	for btn in choices_container.get_children():
		btn.add_theme_font_size_override("font_size", choice_size)

# Registers a global JS function `godot_load_dialog_json(jsonString)` that the
# surrounding web page can call to push new dialog data into the running game.
# We keep a reference to the callback object so it isn't garbage collected.
var _js_callback: JavaScriptObject = null
func _register_js_bridge() -> void:
	if not OS.has_feature("web"):
		return
	_js_callback = JavaScriptBridge.create_callback(_on_js_load_dialog)
	JavaScriptBridge.get_interface("window").godot_load_dialog_json = _js_callback
	JavaScriptBridge.eval("console.log('Dialog bridge ready.');")

# Called by JS with a raw JSON string. Parses and loads it.
func _on_js_load_dialog(args: Array) -> void:
	var raw: String = str(args[0])
	load_dialog_from_string(raw)

# Parses a raw JSON string and loads the dialog — same as load_dialog_from_file
# but accepts a string directly, used by the web bridge and useful for testing.
func load_dialog_from_string(raw: String) -> void:
	var json := JSON.new()
	var err := json.parse(raw)
	if err != OK:
		push_error("Failed to parse dialog JSON string: %s" % json.get_error_message())
		return
	var data: Dictionary = json.get_data()
	# Reset vars to script defaults before applying JSON variables,
	# so swapping files doesn't bleed values from the previous conversation.
	dialog_vars = { "player_name": "Traveler", "player_title": "Carbon Unit" }
	if data.has("variables"):
		for key in data["variables"]:
			dialog_vars[key] = data["variables"][key]
	load_dialog(data.get("nodes", []), int(data.get("start_id", 0)))

# Replaces all {key} tokens in a string with values from dialog_vars.
func _substitute(text: String) -> String:
	for key in dialog_vars:
		text = text.replace("{%s}" % key, str(dialog_vars[key]))
	return text

# Set or update a variable at runtime — call this from anywhere in your game.
# e.g. set_dialog_var("player_name", "Sara")
func set_dialog_var(key: String, value) -> void:
	dialog_vars[key] = value

# Loads a dialog tree from a JSON file on disk.
# The file must have the structure:
#   { "start_id": int, "nodes": [ { "id", "npc_name", "npc_line", "choices" }, ... ] }
func load_dialog_from_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("Dialog file not found: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("Failed to parse dialog JSON: %s" % json.get_error_message())
		return
	var data: Dictionary = json.get_data()
	# Merge any variables defined in the JSON into dialog_vars.
	# JSON values override the script defaults, but won't remove existing keys.
	if data.has("variables"):
		for key in data["variables"]:
			dialog_vars[key] = data["variables"][key]
	load_dialog(data.get("nodes", []), int(data.get("start_id", 0)))

# --- Display Logic ---
func show_node(node_id: int) -> void:
	if node_id == -1:
		_end_dialog()
		return

	if not dialog_tree.has(node_id):
		push_error("Dialog node %d not found." % node_id)
		return

	current_node_id = node_id
	var node: DialogNode = dialog_tree[node_id]

	npc_name_label.text = _substitute(node.npc_name)
	npc_text.text = _substitute(node.npc_line)

	_clear_choices()
	for choice in node.choices:
		_add_choice_button(_substitute(choice["text"]), int(choice["next_id"]))

func _add_choice_button(label_text: String, next_id: int) -> void:
	var btn := Button.new()
	btn.text = "▶  " + label_text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_override("font", alien_font)
	var choice_size: int = int(get_viewport().get_visible_rect().size.y * 0.030)
	btn.add_theme_font_size_override("font_size", choice_size)
	# Player choices: cool silver-blue, distinct from warm NPC parchment
	btn.add_theme_color_override("font_color", Color(0.72, 0.85, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.5, 0.7, 1.0, 1.0))
	btn.pressed.connect(func(): show_node(next_id))
	choices_container.add_child(btn)

func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()

func _end_dialog() -> void:
	npc_text.text = "..."
	_clear_choices()
	npc_name_label.text = "—"
	# Reset so you can restart the conversation for testing
	var restart_btn := Button.new()
	restart_btn.text = "▶  [Restart Dialog]"
	restart_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	restart_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart_btn.add_theme_font_override("font", alien_font)
	var choice_size: int = int(get_viewport().get_visible_rect().size.y * 0.030)
	restart_btn.add_theme_font_size_override("font_size", choice_size)
	restart_btn.add_theme_color_override("font_color", Color(0.72, 0.85, 1.0, 1.0))
	restart_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	restart_btn.add_theme_color_override("font_pressed_color", Color(0.5, 0.7, 1.0, 1.0))
	restart_btn.pressed.connect(func(): show_node(0))
	choices_container.add_child(restart_btn)


# --- Public API for your dialog generation tool ---
# Call this to load an external dialog tree at runtime.
# Expected format:
#   nodes: Array of Dicts, each with keys:
#     "id": int
#     "npc_name": String
#     "npc_line": String
#     "choices": Array of { "text": String, "next_id": int }
#   start_id: int (which node to start on)
func load_dialog(nodes: Array, start_id: int = 0) -> void:
	dialog_tree.clear()
	for n in nodes:
		dialog_tree[int(n["id"])] = DialogNode.new(
			n["npc_name"],
			n["npc_line"],
			n["choices"]
		)
	show_node(start_id)
