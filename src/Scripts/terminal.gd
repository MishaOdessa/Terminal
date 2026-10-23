extends Control

@onready var user = $MarginContainer/VBoxContainer/HBoxContainer/User
@onready var cmd = $MarginContainer/VBoxContainer/HBoxContainer/cmd
@onready var history = $MarginContainer/VBoxContainer/History

var system_os: String
var username: String
var current_dir: String = "~"

var vfs_path: String = ""
var script_path: String = ""
var zip_reader: ZIPReader = ZIPReader.new()
var vfs_loaded: bool = false

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
	
	#VFS запуск
	if not vfs_path.is_empty():
		load_vfs(vfs_path)
	
	# Если путь к скрипту передали, запускаем его
	if not script_path.is_empty():
		run_startup_script(script_path)

func load_vfs(path: String) -> void:
	var err := zip_reader.open(path)
	if DirAccess.dir_exists_absolute(path):
		history.append_text("[VFS] file opened: " + path + "\n")                    
		return
	elif not DirAccess.dir_exists_absolute(path) and err != OK: 
		history.append_text("[VFS ERROR] Archive file not found: " + path + "\n")                     
		return
	if err == OK:
		vfs_loaded = true
		history.append_text("[VFS] Archive successfully opened: " + path + "\n")
	else:
		history.append_text("[VFS ERROR] Error opening ZIP (code " + str(err) + "): " + path + "\n")

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
			#history.append_text("cd " + str(args) + "\n")
			execute_cd(args)
		"ls":
			execute_ls(args)
			#history.append_text("ls " + str(args) + "\n")
		_:
			history.append_text("bash: " + command + ": command not found\n")
			return false
	return true

func execute_cd(args: Array) -> bool:
	var folder_name: String = args[0]
	
	# 1. Сначала обрабатываем выход на уровень вверх (cd ..)
	if folder_name == "..":
		if current_dir == "~":
			# Выше корня (~/ архива) идти некуда
			return false
		
		var split_dir = Array(current_dir.split("/", false))
		if split_dir.size() > 0:
			split_dir.remove_at(split_dir.size() - 1)
			current_dir = "/".join(split_dir)
			
		# Если после удаления ничего не осталось, возвращаем ~
		if current_dir == "":
			current_dir = "~"
			
		update_prompt()
		return true

	# 2. Обработка обычного перехода в папку
	var target_zip_prefix: String = ""
	if current_dir == "~":
		target_zip_prefix = folder_name + "/"
	else:
		var clean_dir = current_dir.trim_prefix("~/")
		target_zip_prefix = clean_dir + "/" + folder_name + "/"
	
	# Проверяем, существует ли такая папка в архиве
	if is_vfs_dir(target_zip_prefix):
		if current_dir == "~":
			current_dir = "~/" + folder_name
		else:
			current_dir = current_dir + "/" + folder_name
			
		update_prompt()
		return true
	else:
		history.append_text("cd: no such file or directory: " + folder_name + "\n")
		return false
func execute_ls(args: Array) -> void:
	# Разобьем аргументы на флаги (все, что начинается с '-') и возможные пути
	var show_all: bool = false       # -a
	var long_format: bool = false    # -l
	var human_readable: bool = false # -h
	
	for arg in args:
		if arg.begins_with("-"):
			if "a" in arg: show_all = true
			if "l" in arg: long_format = true
			if "h" in arg: human_readable = true
	
	var files: PackedStringArray = zip_reader.get_files()
	
	var current_parts: Array = []
	if current_dir != "~":
		current_parts = Array(current_dir.trim_prefix("~/").split("/", false))
	
	var current_depth: int = current_parts.size()
	var results: Array = []
	
	# Собираем элементы текущего уровня
	for file_path in files:
		var file_parts: Array = Array(file_path.split("/", false))
		
		if file_parts.size() == current_depth + 1:
			var match_prefix: bool = true
			for i in range(current_depth):
				if file_parts[i] != current_parts[i]:
					match_prefix = false
					break
			
			if match_prefix:
				var item_name = file_parts[file_parts.size() - 1]
				
				# Если нет флага -a, пропускаем файлы/папки, начинающиеся с точки
				if not show_all and item_name.begins_with("."):
					continue
					
				if not item_name in results:
					results.append(item_name)
	
	if results.is_empty():
		return
		
	results.sort()
	
	# Вывод результата
	var output_string: String = ""
	
	for item in results:
		var full_item_path = ""
		if current_dir == "~":
			full_item_path = item
		else:
			full_item_path = current_dir.trim_prefix("~/") + "/" + item
			
		var is_dir = false
		# Если это директория, в архиве может быть запись с слэшем на конце
		if zip_reader.file_exists(full_item_path + "/"):
			is_dir = true
		
		if long_format:
			var type_char = "d" if is_dir else "-"
			var permissions = type_char + "rwxr-xr-x" if is_dir else type_char + "rw-r--r--"
			var size_str = "0"
			
			var date_str = get_file_real_time(full_item_path)
			
			if is_dir:
				var folder_size = 0
				var prefix_to_match = full_item_path + "/"
				for f in zip_reader.get_files():
					if f.begins_with(prefix_to_match):
						var content = zip_reader.read_file(f)
						if content.size() > 0:
							folder_size += content.size()
				
				if folder_size > 0:
					if human_readable:
						size_str = format_human_size(folder_size)
					else:
						size_str = str(folder_size)
			else:
				# Безопасно получаем размер файла через read_file().size()
				var content = zip_reader.read_file(full_item_path)
				var real_size = content.size()
				
				if human_readable:
					size_str = format_human_size(real_size)
				else:
					size_str = str(real_size)
					
			output_string += "%s  1 %s %s  %s %s %s\n" % [permissions, username, username, size_str.lpad(6), date_str, item]
		else:
			output_string += item + "  "

	# Если это обычный ls (без -l), добавляем перевод строки в самом конце
	if not long_format:
		output_string += "\n"

	history.append_text(output_string)

# Вспомогательная функция для -h (перевод байтов в читаемый вид)
func format_human_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + "B"
	elif bytes < 1024 * 1024:
		return "%.1fK" % (bytes / 1024.0)
	else:
		return "%.1fM" % (bytes / (1024.0 * 1024.0))
	
# Функция для получения форматированной даты файла
func get_file_real_time(full_item_path: String) -> String:
	# Путь к файлу на диске (если ты распаковываешь архив в user://vfs/)
	var disk_path = "user://vfs/" + full_item_path
	
	if FileAccess.file_exists(disk_path) or DirAccess.dir_exists_absolute(disk_path):
		var mod_time = FileAccess.get_modified_time(disk_path)
		var dt = Time.get_datetime_dict_from_unix_time(mod_time)
		
		var months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
		var month_str = months[dt["month"]]
		var day_str = str(dt["day"]).lpad(2, " ")
		var hour_str = str(dt["hour"]).lpad(2, "0")
		var minute_str = str(dt["minute"]).lpad(2, "0")
		
		return "%s %s %s:%s" % [month_str, day_str, hour_str, minute_str]
	
	# Запасной вариант, если файла нет на диске
	return "Jan 1  00:00"
	

func is_vfs_dir(target_zip_prefix: String) -> bool:
	var files: PackedStringArray = zip_reader.get_files()
	for file_puth in files:
		if file_puth.begins_with(target_zip_prefix):
			return true
			break
	return false

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
