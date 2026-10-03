extends Control

@onready var user = $MarginContainer/VBoxContainer/HBoxContainer/User
@onready var cmd = $MarginContainer/VBoxContainer/HBoxContainer/cmd
@onready var history = $MarginContainer/VBoxContainer/History

var system_os: String
var username: String
var current_dir: String = "~"

func get_system_os():
	system_os = OS.get_name().to_lower()
	if system_os == "linux":
		system_os = get_linux_destro()

func get_linux_destro() -> String:
	var path := "/etc/os-release"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		while not file.eof_reached():# читаем до конца
			var line := file.get_line().strip_edges()
			if line.begins_with("ID="):
				var distro := line.trim_prefix("ID=").replace('"','').strip_edges()
				return distro.to_lower()
	return "linux"
	
func get_system_user():
	username = OS.get_environment("USER")
	if username.is_empty():
		username = OS.get_environment("USERNAME")
	if username.is_empty():
		username = "user"

func update_prompt() -> void:
	user.text = username + "@" + system_os + ":" + current_dir + "$ "

func _ready() -> void:
	get_system_os()
	get_system_user()
	update_prompt()
	cmd.grab_focus()
	# Подключаем сигнал нажатия Enter к нашей функции
	cmd.text_submitted.connect(_on_cmd_text_submitted)
	

func _on_cmd_text_submitted(new_text: String) -> void:
	var expanded_text := expand_env_vars(new_text.strip_edges())
	var parts := expanded_text.split(" ", false)
	#Записываем текущую строку ввода с промптом в историю вывода
	history.append_text(user.text + new_text + "\n")
	
	#очищаем поле ввода
	cmd.clear()
	
	if not parts.is_empty():
		execute_command(parts)
	
	cmd.call_deferred("grab_focus")

func execute_command(parts: Array) -> void:
	if parts.is_empty():
		return
	var command: String = parts[0]
	var args := parts.slice(1) # Берет всё, начиная с 1-го элемента до конца
	
	match command:
		"clear":
			history.clear()
		"exit":
			get_tree().quit()
		"cd":
			history.append_text("cd " + str(args) + "\n")
		"ls":
			history.append_text("ls " + str(args) + "\n")
		_:
			history.append_text("bash: " + command + ": command not found\n")

func expand_env_vars(input_text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\$([A-Za-z0-9_]+)")
	
	var result := input_text
	for m in regex.search_all(input_text): # проходит по каждому найденному совпадению в строке
		var full_match := m.get_string(0) # забирает целиком "$USER"
		var var_name := m.get_string(1)   # забирает без первого знака $ -> "USER"
		
		var env_value := OS.get_environment(var_name)
		result = result.replace(full_match, env_value)
		
	return result

func _process(delta: float) -> void:
	pass
