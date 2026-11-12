extends Control

@onready var user = $MarginContainer/VBoxContainer/HBoxContainer/User
@onready var cmd = $MarginContainer/VBoxContainer/HBoxContainer/cmd
@onready var history = $MarginContainer/VBoxContainer/History

var system_os: String
var username: String
var groops: String
var current_dir: String = "~"

var known_users: Array = []
var known_groups: Array = []

var vfs_path: String = ""
var script_path: String = ""
var zip_reader: ZIPReader = ZIPReader.new()
var vfs_loaded: bool = false

var vfs_deleted: Dictionary = {}

const COMMAND_HELP: Dictionary = {
	"cd": "cd [dir]: change the current directory (.. goes up, no argument goes to ~)",
	"chown": "chown [user][:group] file...: change file owner and group",
	"clear": "clear: clear the terminal screen",
	"date": "date: print the current date and time",
	"exit": "exit: close the terminal",
	"help": "help: show this list of commands",
	"ls": "ls [-a] [-l] [-h]: list directory contents (-a hidden, -l long, -h human sizes)",
	"rmdir": "rmdir dir...: remove empty directories",
	"uname": "uname [-a]: print system information",
	"uptime": "uptime: show how long the terminal has been running",
}

func get_live_files() -> Array:
	var result: Array = []
	for f in zip_reader.get_files():
		if not is_path_deleted(f):
			result.append(f)
	return result

func is_path_deleted(path: String) -> bool:
	var p := path.trim_suffix("/")
	while not p.is_empty():
		if vfs_deleted.has(p):
			return true
		var idx := p.rfind("/")
		if idx == -1:
			break
		p = p.substr(0, idx)
	return false

func is_vfs_dir_empty(path: String) -> bool:
	var prefix := path + "/"
	for f in get_live_files():
		if f.begins_with(prefix) and f != prefix:
			return false
	return true

class VFSNodeMeta:
	var owner: String
	var group: String
	var mtime: int
	func _init(o: String, g: String, t: int) -> void:
		owner = o
		group = g
		mtime = t

var vfs_meta: Dictionary = {}

func get_default_mtime() -> int:
	if vfs_path.is_empty() or not FileAccess.file_exists(vfs_path):
		return int(Time.get_unix_time_from_system())
	return FileAccess.get_modified_time(vfs_path)

func get_node_meta(path: String) -> VFSNodeMeta:
	if vfs_meta.has(path):
		return vfs_meta[path]
	return VFSNodeMeta.new(username, groops, get_default_mtime())

# превращает аргумент пользователя в ключ архива относительно current_dir
func resolve_vfs_path(name: String) -> String:
	var base := "" if current_dir == "~" else current_dir.trim_prefix("~/")
	var full := name if base.is_empty() else base + "/" + name
	return full.trim_suffix("/")

func format_time(unix_time: int) -> String:
	# get_datetime_dict_from_unix_time даёт UTC, добавляем смещение пояса
	var bias_sec: int = Time.get_time_zone_from_system().bias * 60
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_sec)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]

func vfs_node_exists(path: String) -> bool:
	if is_path_deleted(path):
		return false
	return zip_reader.file_exists(path) or is_vfs_dir(path + "/")

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
	groops = username
	known_users = ["root", username]
	known_groups = ["root", groops]

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
		"date":
			execute_date()
		"uptime":
			execute_uptime()
		"uname":
			execute_uname(args)
		"chown":
			execute_chown(args)
		"rmdir":
			execute_rmdir(args)
		"help":
			return execute_help(args)
		_:
			history.append_text("bash: " + command + ": command not found\n")
			return false
	return true


func execute_help(args: Array) -> bool:
	var names: Array = COMMAND_HELP.keys()
	names.sort()
	var output := ""
	for name in names:
		output += COMMAND_HELP[name] + "\n"
	history.append_text(output)
	return true

func execute_date():
	var dt = Time.get_datetime_dict_from_system()
	# Можно собрать красивую строку вручную или выдать системную
	var date_str = Time.get_datetime_string_from_system(false, true)
	history.append_text(date_str + "\n")

func execute_uptime():
	var uptime_sec = int(Time.get_ticks_msec() / 1000)
	var hours = int(uptime_sec / 3600)
	var minutes = int((uptime_sec % 3600) / 60)
	var seconds = uptime_sec % 60 
	var uptime_output = "up %02d:%02d:%02d,  1 user,  load average: 0.00, 0.00, 0.00\n" % [hours, minutes, seconds]
	history.append_text(uptime_output)

func execute_uname(args):
	var os: String = OS.get_name()
	if args.has("-a") or args.has("--all"):
		var hostname = OS.get_environment("HOSTNAME")
		if hostname.is_empty():
			hostname = OS.get_environment("COMPUTERNAME")
		if hostname.is_empty():
			hostname = "localhost"
		var version = OS.get_version()
		var distro = OS.get_distribution_name()
		var kernel_info = ""
		kernel_info = "%s %s %s.%s" % [os, hostname, version, OS.get_processor_name()]
		history.append_text(kernel_info + "\n")
	else:
		history.append_text(os + "\n")


func execute_rmdir(args: Array) -> bool:
	if args.is_empty():
		history.append_text("rmdir: missing operand\n")
		return false

	var ok := true
	for target in args:
		var path := resolve_vfs_path(target)
		if not vfs_node_exists(path):
			history.append_text("rmdir: failed to remove '%s': No such file or directory\n" % target)
			ok = false
			continue
		if not is_vfs_dir(path + "/"):
			history.append_text("rmdir: failed to remove '%s': Not a directory\n" % target)
			ok = false
			continue
		if not is_vfs_dir_empty(path):
			history.append_text("rmdir: failed to remove '%s': Directory not empty\n" % target)
			ok = false
			continue
		vfs_deleted[path] = true
		vfs_meta.erase(path)
	return ok

func execute_chown(args: Array):
	if args.size() < 2:
		history.append_text("chown: missing operand\n")
		return false
	var spec: String = args[0]
	
	var new_user: String = ""
	var new_group: String = ""
	if ":" in spec:
		var parts = spec.split(":", true)
		if parts[0] != "":
			new_user = parts[0]
		if parts.size() > 1 and parts[1] != "":
			new_group = parts[1]
	else:
		new_user = spec
		
	if not new_user.is_empty() and not known_users.has(new_user):
		history.append_text("chown: invalid user: '%s'\n" % spec)
		return false
	if not new_group.is_empty() and not known_groups.has(new_group):
		history.append_text("chown: invalid group: '%s'\n" % spec)
		return false
	
	var ok := true
	for target in args.slice(1):
		var path := resolve_vfs_path(target)
		if not vfs_node_exists(path):
			history.append_text("chown: cannot access '%s': No such file or directory\n" % target)
			ok = false
			continue

		# берём текущие метаданные (или дефолтные) и меняем только заданное
		var meta := get_node_meta(path)
		if not new_user.is_empty():
			meta.owner = new_user
		if not new_group.is_empty():
			meta.group = new_group
		meta.mtime = int(Time.get_unix_time_from_system()) 
		vfs_meta[path] = meta
	return ok

func execute_cd(args: Array) -> bool:
	if args.is_empty():
		current_dir = "~"
		update_prompt()
		return true
		
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
	
	var files: Array = get_live_files()
	
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
			
		var is_dir = is_vfs_dir(full_item_path + "/")
		# Если это директория, в архиве может быть запись с слэшем на конце
		if zip_reader.file_exists(full_item_path + "/"):
			is_dir = true
		
		if long_format:
			var meta := get_node_meta(full_item_path)
			var type_char = "d" if is_dir else "-"
			var permissions = type_char + "rwxr-xr-x" if is_dir else type_char + "rw-r--r--"
			var size_str = "0"
			
			var date_str = format_time(meta.mtime)
			
			if is_dir:
				var folder_size = 0
				var prefix_to_match = full_item_path + "/"
				for f in get_live_files():
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
					
			output_string += "%s %s %s %s %s %s\n" % [permissions, meta.owner, meta.group, size_str.lpad(6), date_str, item]
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
	

func is_vfs_dir(target_zip_prefix: String) -> bool:
	for file_puth in get_live_files():
		if file_puth.begins_with(target_zip_prefix):
			return true
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
