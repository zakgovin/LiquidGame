class_name SoundFeedback
extends Node

signal played(event: StringName)

const STREAMS := {
	&"click": preload("res://assets/audio/click.wav"),
	&"start": preload("res://assets/audio/start.wav"),
	&"complete": preload("res://assets/audio/complete.wav"),
	&"failure": preload("res://assets/audio/failure.wav")}
var enabled: bool = true
var players: Dictionary = {}


func _ready() -> void:
	for event: StringName in STREAMS:
		var player := AudioStreamPlayer.new()
		player.stream = STREAMS[event]
		player.max_polyphony = 3
		player.volume_db = -9.0 if event == &"click" else -3.0
		add_child(player)
		players[event] = player


func play_event(event: StringName) -> void:
	if enabled and players.has(event):
		players[event].play()
		played.emit(event)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for player: AudioStreamPlayer in players.values(): player.stop()
