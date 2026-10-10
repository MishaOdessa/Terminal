extends Control

@onready var user = $MarginContainer/VBoxContainer/HBoxContainer/User
@onready var cmd = $MarginContainer/VBoxContainer/HBoxContainer/cmd
@onready var history = $MarginContainer/VBoxContainer/History

var system_os: String
var username: String
var current_dir: String = "~"

var vfs_path: String = ""
var script_path: String = ""

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
	
	parse_cli_args()
	# Если путь к скрипту передали, запускаем его
	if not script_path.is_empty():
		run_startup_script(script_path)
	
func parse_cli_args() -> void:
	# OS.get_cmdline_user_args() берет только параметры, переданные ПОСЛЕ разделителя '--'
	var args := OS.get_cmdline_user_args()
	
	for i in range(args.size()):
		if args[i] == "--vfs" and i + 1 < args.size():
			vfs_path = args[i + 1]
		elif args[i] == "--script" and i + 1 < args.size():
			script_path = args[i + 1]
			
	# Отладочный вывод в стандартную консоль Linux
	print("=== DEBUG CLI ARGS ===")
	print("VFS Path: ", vfs_path)
	print("Script Path: ", script_path)
	print("======================")
	
	# Отладочный вывод прямо в окно нашего эмулятора
	history.append_text("[DEBUG] VFS: " + (vfs_path if not vfs_path.is_empty() else "НЕ ЗАДАН") + "\n")
	history.append_text("[DEBUG] Script: " + (script_path if not script_path.is_empty() else "НЕ ЗАДАН") + "\n\n")

func run_startup_script(path: String) -> void:
	#проверяем, существует ли файл
	if not FileAccess.file_exists(path):
		history.append_text("[ERROR] Script file not found: " + path + "\n")
		return
	
	#открываем файл для чтения
	var file := FileAccess.open(path, FileAccess.READ)
	
	#читаем файл пока не дойдем до конца
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		
		# Пропускаем пустые строки или комментарии (начинающиеся с #)
		if line.is_empty() or line.begins_with("#"):
			continue
		
		# Выполняем команду и получаем статус (успех/ошибка)
		var success: bool = _on_cmd_text_submitted(line)
		
		# Если произошла ошибка — останавливаем скрипт
		if not success:
			history.append_text("[SCRIPT ERROR] Stopped execution on command: " + line + "\n")
			break

func _on_cmd_text_submitted(new_text: String):
	var expanded_text := expand_env_vars(new_text.strip_edges())
	var parts := expanded_text.split(" ", false)
	#Записываем текущую строку ввода с промптом в историю вывода
	history.append_text(user.text + new_text + "\n")
	
	#очищаем поле ввода
	cmd.clear()
	var success: bool = true
	if not parts.is_empty():
		success = execute_command(parts)
	
	cmd.call_deferred("grab_focus")
	return success

func execute_command(parts: Array):
	if parts.is_empty():
		return true
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
			return false
	return true

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
