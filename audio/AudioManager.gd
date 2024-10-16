extends Node

#=======================================================================
#Señales para indicar cuando un audio ha terminado de reproducirse
#=======================================================================
signal audio_finished(audio_name)

#=======================================================================
#Constantes públicas
#=======================================================================
const channel_count:int						= 8 # set (could be user configurable, ex. low[8]/medium[16]/high[32])
const fade_in_out_min_volume_db:float		= -40.0
const default_volume_db:float				= 0.0

#=======================================================================
#Variables públicas
#=======================================================================
var sounds_enabled:bool						= true
var music_sound_enabled:bool				= true
var music_sound_level:float : set = _set_music_sound_level, get = _get_music_sound_level
var fx_sound_enabled:bool					= true
var fx_sound_level:float : set = _set_fx_sound_level, get = _get_fx_sound_level

#=======================================================================
#Variables privadas
#=======================================================================
var _audio_bus:Dictionary									= { "master" : 0, "music" : 1, "fx": 2 }
var _available_stream_players:Array[String]					= []
var _stream_players:Array[AudioStreamPlayer]				= []
var _stream_players_tweeners:Dictionary						= {}
var _playing_effects:Dictionary								= {}
var _playing_musics:Dictionary								= {}
var _effect_filenames:Array[String]							= []
var _music_filenames:Array[String]							= []
var _loaded_effect_streams:Dictionary						= {}
var _loaded_music_streams:Dictionary						= {}

#=======================================================================
#Ready
#=======================================================================
func _ready()->void:
	#Establecemos el bus layout
	AudioServer.set_bus_layout(load("res://audio/bus_layout.tres"))
	
	#Establecemos el volumen de los canales de audio
	AudioServer.set_bus_volume_db(_audio_bus["music"], self.music_sound_level)
	AudioServer.set_bus_volume_db(_audio_bus["fx"], self.fx_sound_level)
	
	#Creamos los canales de AudioStreamPlayer
	for l_i:int in channel_count:
		var l_stream_player = AudioStreamPlayer.new()
		
		#Indicamos que los reproductores de sonido nunca deben de parar cuando el juego se pause
		l_stream_player.process_mode = Node.PROCESS_MODE_ALWAYS
		
		#Establecemos un nombre al reproductor
		l_stream_player.name = str(l_i)
		
		#Insertamos el nodo en el árbol de escenas
		add_child(l_stream_player)
		
		#Guardamos el nombre del nodo en una lista que contendrá todos los audios que no se están reproduciendo
		_available_stream_players.append(l_stream_player.name)
		
		#Guardamos el nodo en una lista
		_stream_players.append(l_stream_player)
		
		#Conectamos las señales que emite el AudioStreamPlayer
		l_stream_player.finished.connect(_on_stream_finished.bind(l_stream_player))
	
	#Generamos la lista de nombres a partir de los nombres de los ficheros de música y efectos
	_effect_filenames = _get_filenames("res://audio//fx")
	_music_filenames = _get_filenames("res://audio//music")

#=======================================================================
#Obtiene el nombre completo del fichero de audio (a partir del nombre del audio del parámetro que no incluye la extensión)
#=======================================================================
func _get_filename(p_type:String, p_audio_name:String)->String:
	var l_result:String = ""
	var l_files:Array[String] = []
	
	#Comprobamos el tipo de recurso de audio
	match p_type:
		"music":
			#Obtenemos la lista con los nombres de los ficheros de música
			l_files = _music_filenames
		"fx":
			#Obtenemos la lista con los nombres de los ficheros de los efectos de sonido
			l_files = _effect_filenames
	
	#Recorremos la lista de ficheros
	for l_file:String in l_files:
		#Comprobamos si el nombre del fichero empieza por el nombre que estamos buscando
		if (l_file.begins_with(p_audio_name)):
			#Guardamos el nombre del fichero
			l_result = l_file
			
			#Salimos del bucle
			break
	
	return l_result

#=======================================================================
#Obtiene una lista con todos los archivos de audio (.wav / .ogg) en el directorio
#=======================================================================
func _get_filenames(p_dir_path:String)->Array[String]:
	var l_result:Array[String] = []
	
	#Abrimos el directorio
	var l_dir_scan:DirAccess = DirAccess.open(p_dir_path)
	
	#Comprobamos si hemos abierto correctamente el directorio
	if (l_dir_scan != null):
		#Establecemos la configuración del escaner de ficheros
		l_dir_scan.include_hidden = false
		l_dir_scan.include_navigational = false
		
		#Recorremos todos los ficheros que hay en el directorio
		for l_file_name:String in l_dir_scan.get_files():
			#Comprobamos la extensión del fichero, para saber si es un fichero de audio soportado
			if ((l_file_name.ends_with(".wav")) or (l_file_name.ends_with(".ogg")) or (l_file_name.ends_with(".wav.import")) or (l_file_name.ends_with(".ogg.import"))):
				var l_base_file_name:String = l_file_name
				
				#Comprobamos si el fichero termina con la extensión de importación
				if (l_base_file_name.ends_with(".import")):
					#Obtenemos el nombre del fichero sin la extensión "*.import"
					l_base_file_name = l_base_file_name.get_basename()
				
				#Comprobamos que el fichero de audio no se hubiera añadido previamente
				if (l_result.has(l_base_file_name) == false):
					#Guardamos el nombre del fichero
					l_result.append(l_base_file_name)
	
	return l_result

#=======================================================================
#Obtiene el reproductor a partir de su nombre único
#=======================================================================
func _get_audio_stream_player_from_name(p_name:String)->AudioStreamPlayer:
	var l_result:AudioStreamPlayer = null
	
	#Recorremos la lista completa de reproductores de audio
	for l_stream_player:AudioStreamPlayer in _stream_players:
		#Comprobamos el nombre del reproductor
		if (l_stream_player.name == p_name):
			#Guardamos como resultado la instancia del reproductor
			l_result = l_stream_player
			
			#Salimos del bucle
			break
	
	return l_result

#=======================================================================
#Convierte los nombres de fichero a nombres de audios (Elimina la extensión desde el array con los nombres de ficheros)
#=======================================================================
func _remove_extensions(p_filenames:Array[String])->Array[String]:
	var l_basenames:Array[String] = []
	
	#Recorremos todos los ficheros
	for l_filename:String in p_filenames:
		#Insertamos la ruta del fichero sin incluir la extensión
		l_basenames.append(l_filename.get_basename())
	
	return l_basenames

#=======================================================================
#Obtiene un array con los recursos de los audios cargados
#El parámetro type es el mismo que el de la carpeta donde se encuentra
#=======================================================================
func _load_from_files(p_type:String, p_audio_names:Array[String])->Dictionary:
	var l_loaded:Dictionary = {}
	
	#Recorremos todos los nombres de los ficheros de audio
	for l_audio_name:String in p_audio_names:
		var l_stream:AudioStreamContainer = _load_from_file(p_type, l_audio_name)
		
		#Comprobamos si se ha cargado el audio
		if (l_stream != null):
			#Guardamos el stream de audio en el diccionario
			l_loaded[l_audio_name] = l_stream
	
	return l_loaded

#=======================================================================
#Intenta cargar un recurso de audio
#El parámetro type es el mismo que el de la carpeta donde se encuentra
#=======================================================================
func _load_from_file(p_type:String, p_audio_name:String)->AudioStreamContainer:
	var l_result:AudioStreamContainer = null
	var l_file = _get_filename(p_type, p_audio_name)
	
	#Comprobamos si se ha encontrado un fichero con el nombre especificado
	if (l_file != ""):
		#Creamos el contenedor del audio
		l_result = AudioStreamContainer.new()
		
		#Guardamos el stream del sonido
		l_result.audio_stream = load("res://audio//%s//%s" % [p_type, l_file])
	
	return l_result

#=======================================================================
#Para el tweener que haya asignado al stream player indicado
#=======================================================================
func _kill_stream_player_tweener(p_stream_player_name:StringName)->void:
	#Comprobamos si tenía un tween asignado
	if (_stream_players_tweeners.has(p_stream_player_name)):
		#Obtenemos el tween actual
		var l_current_tween:Tween = _stream_players_tweeners[p_stream_player_name]
		
		#Comprobamos si se está ejecutando (no debería de pasar, ya que si estaba libre es porque no esta reproduciendo ningún sonido)
		if (l_current_tween.is_running()):
			#Paramos el tween
			l_current_tween.kill()
		
		#Eliminamos la referencia al tween
		_stream_players_tweeners.erase(p_stream_player_name)

#=======================================================================
#Reproduce el audio
#=======================================================================
func _play(p_type:String, p_audio_name:String, p_fade_in:bool, p_fade_in_duration:float = 0.0, p_force_to_play:bool = false)->bool:
	var l_result:bool = false
	var l_stream_player_name = _available_stream_players.pop_front()
	
	#Comprobamos si no hay más canales disponibles, y se quiere forzar la reproducción del sonido
	if ((l_stream_player_name == null) and (p_force_to_play)):
		#Intentamos liberar un canal de audio del mismo tipo del que se quiere reproducir
		if (_release_audio_channel(p_type)):
			#Cogemos el canal que haya quedado libre
			l_stream_player_name = _available_stream_players.pop_front()
	
	#Comprobamos si se ha obtenido algun reproductor de audio
	if (l_stream_player_name != null):
		var l_stream_player:AudioStreamPlayer = _get_audio_stream_player_from_name(l_stream_player_name)
		var l_stream:AudioStream = null
		
		#Comprobamos el tipo de audio
		match p_type:
			"music":
				#Comprobamos si existe un recurso de audio con este nombre
				if (_loaded_music_streams.has(p_audio_name)):
					#Obtenemos el recurso de audio
					l_stream = _loaded_music_streams[p_audio_name].audio_stream
			"fx":
				#Comprobamos si existe un recurso de audio con este nombre
				if (_loaded_effect_streams.has(p_audio_name)):
					#Obtenemos el recurso de audio
					l_stream = _loaded_effect_streams[p_audio_name].audio_stream
		
		#Comprobamos si se ha obtenido el recurso de audio
		if (l_stream != null):
			#Comprobamos el tipo de audio
			match p_type:
				"music":
					#Establecemos el bus desde el que sonará
					l_stream_player.bus = "Music"
					
					#Guardamos el nombre del recurso de audio que va a reproducir
					_playing_musics[l_stream_player.name] = p_audio_name
				"fx":
					l_stream_player.bus = "Effects"
					
					#Guardamos el nombre del recurso de audio que va a reproducir
					_playing_effects[l_stream_player.name] = p_audio_name
			
			#Asignamos el recurso de audio
			l_stream_player.stream = l_stream
			
			#Paramos el tweener en caso de que tuviese uno asignado y aún no haya terminado
			_kill_stream_player_tweener(l_stream_player_name)
			
			#Comprobamos si hay que hacer un efecto fade in
			if (p_fade_in):
				#Nos aseguramos que la duración del tween sea superior o igual a 0.0
				p_fade_in_duration = maxf(p_fade_in_duration, 0.0)
				
				#Creamos una instancia del tween
				var l_new_tween:Tween = create_tween()
				
				#Conectamos las señales que emite el tween
				l_new_tween.finished.connect(_on_stream_player_tweener_finished.bind(l_stream_player_name))
				
				#Guardamos el tween
				_stream_players_tweeners[l_stream_player_name] = l_new_tween
				
				#Establecemos las propiedades del tween
				l_new_tween.set_ease(Tween.EASE_OUT)
				l_new_tween.set_trans(Tween.TRANS_LINEAR)
				
				#Bajamos el volumen al mínimo, para ir subiendolo gradualmente
				l_stream_player.volume_db = fade_in_out_min_volume_db
				
				#Comenzamos la reproducción del audio
				l_stream_player.play()
				
				#Comenzamos a aplicar el volumen gradualmente
				l_new_tween.tween_property(l_stream_player, "volume_db", default_volume_db, p_fade_in_duration)
			else:
				#Nos aseguramos que el volumen esta en su valor por defecto
				l_stream_player.volume_db = default_volume_db
				
				#Reproducimos el recurso de audio
				l_stream_player.play()
			
			#Establecemos el resultado de la operación
			l_result = true
		else:
			#Nos aseguramos que el nombre del reproductor de sonidos no este actualmente en la lista de disponibles
			if (_available_stream_players.has(l_stream_player_name) == false):
				#Ponemos el nombre del AudioStreamPlayer en la lista de disponibles
				_available_stream_players.append(l_stream_player_name)
	
	return l_result

#=======================================================================
#Para la reproducción del audio
#=======================================================================
func _stop(p_type:String, p_audio_name:String = "", p_fade_out:bool = false, p_fade_out_duration:float = 0.0, p_on_stop_callable_function = null)->void:
	var l_stream_player:AudioStreamPlayer = null
	var l_players:Dictionary = {}
	
	#Nos aseguramos que la duración del tween sea superior o igual a 0.0
	p_fade_out_duration = maxf(p_fade_out_duration, 0.0)
	
	#Comprobamos el tipo de audio
	match p_type:
		"music":
			#Obtenemos la lista con los reproductores de música activos
			l_players = _playing_musics
		"fx":
			#Obtenemos la lista con los reproductores de efectos de sonido activos
			l_players = _playing_effects
	
	#Recorremos todos los reproductores activos, para ver que audio están reproduciendo
	for l_stream_player_name:String in l_players.keys():
		#Comprobamos si el reproductor está reproduciendo el audio que estamos buscando, o no se ha especificado ningún audio porque se desean pararlos todos
		if ((l_players[l_stream_player_name] == p_audio_name) or (p_audio_name == "")):
			#Obtenemos el reproductor de audio
			l_stream_player = _get_audio_stream_player_from_name(l_stream_player_name)
			
			#Comprobamos si se ha obtenido el reproductor
			if (l_stream_player != null):
				#Paramos el tweener en caso de que tuviese uno asignado y aún no haya terminado
				_kill_stream_player_tweener(l_stream_player_name)
				
				#Comprobamos si debemos de realizar el efecto "fade out"
				if (p_fade_out):
					#Creamos una instancia del tween
					var l_new_tween:Tween = create_tween()
					
					#Conectamos las señales que emite el tween
					l_new_tween.finished.connect(_on_stream_player_tweener_finished.bind(l_stream_player_name))
					
					#Guardamos el tween
					_stream_players_tweeners[l_stream_player_name] = l_new_tween
					
					#Establecemos las propiedades del tween
					l_new_tween.set_ease(Tween.EASE_OUT)
					l_new_tween.set_trans(Tween.TRANS_LINEAR)
					
					#Comenzamos a aplicar la reducción de volumen gradualmente
					l_new_tween.tween_property(l_stream_player, "volume_db", fade_in_out_min_volume_db, p_fade_out_duration)
					
					#Paramos la reproducción
					l_new_tween.tween_callback(l_stream_player.stop)
					
					#Llamamos a la función que gestiona cuando el audio ha finalizado
					l_new_tween.tween_callback(_on_stream_stopped.bind(l_stream_player))
					
					#Comprobamos si hay que realizar alguna llamada a alguna función, justo después de parar el sonido
					if (p_on_stop_callable_function != null):
						#Llamamos a la función personalizada
						l_new_tween.tween_callback(p_on_stop_callable_function)
					
					#Paramos el tweener en caso de que tuviese uno asignado y aún no haya terminado
					l_new_tween.tween_callback(_kill_stream_player_tweener.bind(l_stream_player_name))
				else:
					#Paramos la reproducción
					l_stream_player.stop()
					
					#Llamamos a la función que gestiona cuando el audio ha finalizado
					_on_stream_stopped(l_stream_player)
					
					#Comprobamos si hay que realizar alguna llamada a alguna función, justo después de parar el sonido
					if (p_on_stop_callable_function != null):
						#Llamamos a la función personalizada
						(p_on_stop_callable_function as Callable).call()

#=======================================================================
#Libera un canal de audio que esté a punto de terminar de reproducirse del tipo indicado
#=======================================================================
func _release_audio_channel(p_type:String)->bool:
	var l_result:bool = false
	var l_stream_player:AudioStreamPlayer = null
	var l_stream_player_name:Variant = null
	var l_stream_player_remaining_duration:float = 0.0
	var l_players:Dictionary = {}
	
	#Comprobamos el tipo de audio
	match p_type:
		"music":
			#Obtenemos la lista con los reproductores de música activos
			l_players = _playing_musics
		"fx":
			#Obtenemos la lista con los reproductores de efectos de sonido activos
			l_players = _playing_effects
	
	#Recorremos todos los reproductores activos, para ver que audio están reproduciendo
	for l_audio_stream_player_name:String in l_players.keys():
		#Obtenemos el reproductor de audio
		l_stream_player = _get_audio_stream_player_from_name(l_audio_stream_player_name)
		
		#Comprobamos si se ha obtenido el reproductor
		if (l_stream_player != null):
			#Obtenemos el tiempo restante para finalizar el audio
			var l_remaining_duration:float = (l_stream_player.stream.get_length() - l_stream_player.get_playback_position())
			
			#Comprobamos si no es el primer stream player que evaluamos
			if (l_stream_player_name != null):
				#Comprobamos si este stream player está más próximo a terminar de reproducirse
				if (l_remaining_duration < l_stream_player_remaining_duration):
					#Guardamos el nombre del stream player
					l_stream_player_name = l_audio_stream_player_name
					l_stream_player_remaining_duration = l_remaining_duration
			else:
				#Guardamos el nombre del stream player
				l_stream_player_name = l_audio_stream_player_name
				l_stream_player_remaining_duration = l_remaining_duration
		
	#Comprobamos si se ha obtenido el nombre del reproductor
	if (l_stream_player_name != null):
		#Obtenemos el reproductor de audio
		l_stream_player = _get_audio_stream_player_from_name(l_stream_player_name)
		
		#Paramos el tweener en caso de que tuviese uno asignado y aún no haya terminado
		_kill_stream_player_tweener(l_stream_player_name)
		
		#Paramos la reproducción
		l_stream_player.stop()
		
		#Llamamos a la función que gestiona cuando el audio ha finalizado
		_on_stream_stopped(l_stream_player)
		
		#Establecemos el resultado de la operación para indicar que se ha liberado un stream player
		l_result = true
	
	return l_result

#=======================================================================
#Comprueba si el audio se está reproduciendo actualmente
#=======================================================================
func _is_playing(p_type:String, p_audio_name:String)->bool:
	var l_result:bool = false
	var l_players:Dictionary = {}
	
	#Comprobamos el tipo de audio
	match p_type:
		"music":
			#Obtenemos la lista con los reproductores de música activos
			l_players = _playing_musics
		"fx":
			#Obtenemos la lista con los reproductores de efectos de sonido activos
			l_players = _playing_effects
	
	#Recorremos todos los reproductores activos, para ver que audio están reproduciendo
	for audio_stream_player_name:String in l_players.keys():
		#Comprobamos si el reproductor está reproduciendo el audio que estamos buscando, o no se ha especificado ningún audio porque se desean pararlos todos
		if (l_players[audio_stream_player_name] == p_audio_name):
			#Obtenemos el reproductor
			l_result = true
			
			#Salimos del bucle
			break
	
	return l_result

#=======================================================================
#Obtiene una lista con todos los audios que se están reproduciendo actualmente
#=======================================================================
func get_playing_audio_names(p_type:String)->PackedStringArray:
	var l_result:PackedStringArray = []
	var l_players:Dictionary = {}
	
	#Comprobamos el tipo de audio
	match p_type:
		"music":
			#Obtenemos la lista con los reproductores de música activos
			l_players = _playing_musics
		"fx":
			#Obtenemos la lista con los reproductores de efectos de sonido activos
			l_players = _playing_effects
	
	#Recorremos todos los reproductores activos, para ver que audio están reproduciendo
	for audio_stream_player_name:String in l_players.keys():
		#Guardamos en la lista el nombre del audio que se esta reproduciendo
		l_result.append(l_players[audio_stream_player_name])
	
	return l_result

#=======================================================================
#Establece el volumen de la musica
#=======================================================================
func _get_music_sound_level()->float:
	return AudioServer.get_bus_volume_db(_audio_bus["music"])
func _set_music_sound_level(p_level:float)->void:
	#Establecemos el volumen de la música
	AudioServer.set_bus_volume_db(_audio_bus["music"], p_level)

#=======================================================================
#Establece el volumen de los efectos especiales
#=======================================================================
func _get_fx_sound_level()->float:
	return AudioServer.get_bus_volume_db(_audio_bus["fx"])
func _set_fx_sound_level(p_level:float)->void:
	#Establecemos el volumen del efecto de click
	AudioServer.set_bus_volume_db(_audio_bus["fx"], p_level)

#=======================================================================
#Función para capturar la señal de cuando un audio ha finalizado
#=======================================================================
func _on_stream_finished(p_stream_player:AudioStreamPlayer)->void:
	var l_audio_name:String = ""
	var l_stream_player_name:StringName = p_stream_player.name
	
	#Comprobamos que bus estaba utilizando el reproductor
	match (p_stream_player.bus):
		"Effects":
			#Obtenemos el nombre del audio que se ha reproducido
			l_audio_name = _playing_effects.get(l_stream_player_name, "")
			
			#Eliminamos el reproductor de la lista de los reproductores que están en uso
			_playing_effects.erase(l_stream_player_name)
		"Music":
			#Obtenemos el nombre del audio que se ha reproducido
			l_audio_name = _playing_musics.get(l_stream_player_name, "")
			
			#Eliminamos el reproductor de la lista de los reproductores que están en uso
			_playing_musics.erase(l_stream_player_name)
	
	#Paramos el tweener en caso de que tuviese uno asignado y aún no haya terminado (podría pasar que el tween dure más que el audio)
	_kill_stream_player_tweener(l_stream_player_name)
	
	#Nos aseguramos que el nombre del reproductor de sonidos no este actualmente en la lista de disponibles
	if (_available_stream_players.has(l_stream_player_name) == false):
		#Ponemos el nodo AudioStreamPlayer en la lista de nodos disponibles
		_available_stream_players.append(l_stream_player_name)
	
	#Emitimos una señal para indicar el nombre del audio que ha finalizado
	audio_finished.emit(l_audio_name)

#=======================================================================
#Función para procesar cuando un audio se ha parado antes de terminar de reproducirse
#=======================================================================
func _on_stream_stopped(p_stream_player:AudioStreamPlayer)->void:
	var l_audio_name:String = ""
	var l_stream_player_name:StringName = p_stream_player.name
	
	#Comprobamos que bus estaba utilizando el reproductor
	match (p_stream_player.bus):
		"Effects":
			#Obtenemos el nombre del audio que se ha reproducido
			l_audio_name = _playing_effects.get(l_stream_player_name, "")
			
			#Eliminamos el reproductor de la lista de los reproductores que están en uso
			_playing_effects.erase(l_stream_player_name)
		"Music":
			#Obtenemos el nombre del audio que se ha reproducido
			l_audio_name = _playing_musics.get(l_stream_player_name, "")
			
			#Eliminamos el reproductor de la lista de los reproductores que están en uso
			_playing_musics.erase(l_stream_player_name)
	
	#Nos aseguramos que el nombre del reproductor de sonidos no este actualmente en la lista de disponibles
	if (_available_stream_players.has(l_stream_player_name) == false):
		#Ponemos el nodo AudioStreamPlayer en la lista de nodos disponibles
		_available_stream_players.append(l_stream_player_name)
	
	#Emitimos una señal para indicar el nombre del audio que ha finalizado
	audio_finished.emit(l_audio_name)

#=======================================================================
#Función para procesar cuando un tween ha terminado de ejecutarse
#=======================================================================
func _on_stream_player_tweener_finished(p_stream_player_name:StringName)->void:
	#Comprobamos si tenía un tween asignado
	if (_stream_players_tweeners.has(p_stream_player_name)):
		#Eliminamos la referencia al tween
		_stream_players_tweeners.erase(p_stream_player_name)

#=======================================================================
#Obtiene una lista con los nombres de todos los efectos de sonidos cargados en memoria
#=======================================================================
func loaded_effects()->Array[String]:
	return _loaded_effect_streams.keys()

#=======================================================================
#Carga un array con los recursos de efectos de audio desde un array con los nombres de los audios (sin las extensiones de los archivos)
#=======================================================================
func load_effects(p_audio_names:Array[String], p_append:bool)->void:
	#Comprobamos si debemos de añadir los sonidos a los existentes
	if (p_append):
		#Recorremos todos los nombres de audio que se desean añadir
		for l_audio_name:String in p_audio_names:
			#Añadimos el audio
			load_effect(l_audio_name)
	else:
		_loaded_effect_streams = _load_from_files("fx", p_audio_names)

#=======================================================================
#Carga un efecto de sonido en memoria
#=======================================================================
func load_effect(p_audio_name:String)->void:
	#Comprobamos si no existe el audio que se desea cargar
	if (_loaded_effect_streams.has(p_audio_name) == false):
		var l_loaded_audio_stream:AudioStreamContainer = _load_from_file("fx", p_audio_name)
		
		#Comprobamos si se ha cargado el recurso de audio
		if (l_loaded_audio_stream != null):
			#Guardamos el recurso de audio
			_loaded_effect_streams[p_audio_name] = l_loaded_audio_stream

#=======================================================================
#Obtiene una lista con los nombres de todos los ficheros de música cargados en memoria
#=======================================================================
func loaded_musics()->Array[String]:
	return _loaded_music_streams.keys()

#=======================================================================
#Carga un array con los recursos de música desde un array con los nombres de los audios (sin las extensiones de los archivos)
#=======================================================================
func load_musics(p_audio_names:Array[String])->void:
	_loaded_music_streams = _load_from_files("music", p_audio_names)

#=======================================================================
#Carga un archivo de música en memoria
#=======================================================================
func load_music(p_audio_name:String)->void:
	#Comprobamos si no existe la música que se desea cargar
	if (_loaded_music_streams.has(p_audio_name) == false):
		var l_loaded_audio_stream:AudioStreamContainer = _load_from_file("music", p_audio_name)
		
		#Comprobamos si se ha cargado el recurso de audio
		if (l_loaded_audio_stream != null):
			#Guardamos el recurso de audio
			_loaded_music_streams[p_audio_name] = l_loaded_audio_stream

#=======================================================================
#Carga cualquier música y efecto de sonido.
#Nota: Es lo mismo que llamar a "load_all_effects" y "load_all_music"
#=======================================================================
func load_all()->void:
	#Cargamos todos los efectos de sonido
	load_all_effects()
	
	#Cargamos todos los ficheros de música
	load_all_music()

#=======================================================================
#Carga cualquier fichero de efecto de sonido
#=======================================================================
func load_all_effects()->void:
	#Carga la lista de efectos de sonido
	load_effects(_remove_extensions(_effect_filenames), false)

#=======================================================================
#Carga cualquier fichero de música
#=======================================================================
func load_all_music()->void:
	#Carga la lista de ficheros de música
	load_musics(_remove_extensions(_music_filenames))

#=======================================================================
#Libera de la memoria todos los sonidos
#=======================================================================
func deload_all()->void:
	#Liberamos de la memoria todos los efectos de sonido
	deload_all_effects()
	
	#Liberamos de la memoria todos los ficheros de música
	deload_all_music()

#=======================================================================
#Libera de la memoria todos los efectos de sonido
#=======================================================================
func deload_all_effects()->void:
	#Variamos el diccionario
	_loaded_effect_streams.clear()

#=======================================================================
#Libera de la memoria todos los efectos de sonido incluidos en el parámetro
#=======================================================================
func deload_effects(p_audio_names:Array[String])->void:
	#Recorremos todos los nombres de audio que se desean eliminar
	for l_audio_name:String in p_audio_names:
		#Eliminamos el audio
		deload_effect(l_audio_name)

#=======================================================================
#Libera de la memoria todos los ficheros de música
#=======================================================================
func deload_all_music()->void:
	#Vaciamos el diccionario
	_loaded_music_streams.clear()

#=======================================================================
#Libera de la memoria el efecto de sonido especificado en el parámetro
#=======================================================================
func deload_effect(p_audio_name:String)->bool:
	#Intenta eliminar el efecto de sonido y retorna el resultado de la operación
	return _loaded_effect_streams.erase(p_audio_name)

#=======================================================================
#Libera de la memoria el fichero de música especificado en el parámetro
#=======================================================================
func deload_music(p_audio_name:String)->void:
	#Intenta eliminar el fichero de música y retorna el resultado de la operación
	return _loaded_music_streams.erase(p_audio_name)

#=======================================================================
#Reproduce el fichero de efecto de sonido (sin incluir la extensión)
#=======================================================================
func play_effect(p_audio_name:String, p_allow_duplicate:bool = true, p_force_to_play:bool = false)->bool:
	var l_result:bool = false
	
	#Comprobamos si los efectos de sonido están habilitados
	if (self.fx_sound_enabled):
		#Comprobamos si el sonido no puede estar duplicado
		if (p_allow_duplicate == false):
			#Paramos la reproducción del efecto de sonido
			_stop("fx", p_audio_name)
		
		#Reproducimos el efecto de sonido
		l_result = _play("fx", p_audio_name, false, 0.0, p_force_to_play)
	
	return l_result

#=======================================================================
#Obtiene si el efecto de sonido está reproduciendose o no
#=======================================================================
func playing_effect(p_audio_name:String)->bool:
	return _is_playing("fx", p_audio_name)

#=======================================================================
#Para la reproducción del efecto de sonido
#=======================================================================
func stop_effect(p_audio_name:String)->void:
	#Paramos la reproducción del efecto de sonido
	_stop("fx", p_audio_name)

#=======================================================================
#Para la reproducción de todos los efecto de sonido
#=======================================================================
func stop_effects()->void:
	#Paramos la reproducción de todos los efectos de sonido
	_stop("fx")

#=======================================================================
#Reproduce el fichero de música (sin incluir la extensión)
#=======================================================================
func play_music(p_audio_name:String, p_fade_in:bool, p_fade_in_duration:float = 0.0, p_force_to_play:bool = false)->bool:
	var l_result:bool = false
	
	#Comprobamos si la música está habilitada
	if (self.music_sound_enabled):
		#Comprobamos si la música se estaba reproduciendo
		if (_is_playing("music", p_audio_name)):
			#Paramos la reproducción de la música
			_stop("music", p_audio_name)
		
		#Reproducimos la música
		l_result = _play("music", p_audio_name, p_fade_in, p_fade_in_duration, p_force_to_play)
	
	return l_result

#=======================================================================
#Intercambia una música por otra
#=======================================================================
func swap_music(p_stop_audio_name:String, p_play_audio_name:String, p_fade_out:bool, p_fade_in:bool, p_fade_out_duration:float = 0.0, p_fade_in_duration:float = 0.0, p_force_to_play:bool = false)->bool:
	var l_result:bool = false
	
	#Comprobamos si la música que se desea parar se está reproduciendo o no se ha especificado musica alguna
	if (_is_playing("music", p_stop_audio_name)):
		var l_next_play:Callable = play_music.bind(p_play_audio_name, p_fade_in, p_fade_in_duration, p_force_to_play)
		
		#Paramos la reproducción de la música
		_stop("music", p_stop_audio_name, p_fade_out, p_fade_out_duration, l_next_play)
	else: #La música que se desea parar no se está reproduciendo
		#Reproducimos la nueva música
		l_result = play_music(p_play_audio_name, p_fade_in, p_fade_in_duration, p_force_to_play)
	
	return l_result

#=======================================================================
#Intercambia la música que se este reproduciendo actualmente por otra
#=======================================================================
func swap_current_music(p_play_audio_name:String, p_fade_out:bool, p_fade_in:bool, p_fade_out_duration:float = 0.0, p_fade_in_duration:float = 0.0, p_force_to_play:bool = false)->bool:
	var l_result:bool = false
	var l_current_musics:PackedStringArray = get_playing_audio_names("music")
	
	#Comprobamos si hay música reproduciendose
	if (l_current_musics.size() > 0):
		var l_next_play:Callable = play_music.bind(p_play_audio_name, p_fade_in, p_fade_in_duration, p_force_to_play)
		
		#Paramos la reproducción de la música
		_stop("music", l_current_musics[0], p_fade_out, p_fade_out_duration, l_next_play)
	else: #La música que se desea parar no se está reproduciendo
		#Reproducimos la nueva música
		l_result = play_music(p_play_audio_name, p_fade_in, p_fade_in_duration, p_force_to_play)
	
	return l_result

#=======================================================================
#Obtiene si el fichero de música está reproduciendose o no
#=======================================================================
func playing_music(p_audio_name:String)->bool:
	return _is_playing("music", p_audio_name)

#=======================================================================
#Para la reproducción de la música
#=======================================================================
func stop_music(p_audio_name:String, p_fade_out:bool, p_fade_out_duration:float = 0.0)->void:
	#Paramos la reproducción de la música
	_stop("music", p_audio_name, p_fade_out, p_fade_out_duration)

#=======================================================================
#Para la reproducción de todas las pistas de música
#=======================================================================
func stop_musics()->void:
	#Paramos la reproducción de todas las pistas de música
	_stop("music")
