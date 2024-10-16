extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Load audio samples
	var effects:Array[String] = [
		"blip",
		"confirmation",
		"laser"
	]
	AudioManager.load_effects(effects, false)
	AudioManager.load_music("bgm")
	# OR
#	AudioManager.load_all_effects()
#	AudioManager.load_all_music()
	# OR
#	AudioManager.load_all()


func _on_Blip_pressed() -> void:
	AudioManager.play_effect("blip")


func _on_Laser_pressed() -> void:
	AudioManager.play_effect("laser")


func _on_Confirmation_pressed() -> void:
	AudioManager.play_effect("confirmation")


func _on_BGM_pressed() -> void:
	AudioManager.play_music("bgm", false)


func _on_swap_bgm_pressed() -> void:
	AudioManager.swap_current_music("bgm", true, true, 1.0, 1.0)
