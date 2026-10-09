# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node2D

## Luto ladra cuando Lino llega a esta distancia del punto donde empieza la
## conversación con Lázaro, antes de que empiece.
const DISTANCIA_LADRIDO_DE_LUTO: float = 520.0

# Marcadores de la escena
@export var punto_parada_lino: Marker2D
@export var posicion_junto_a_lazaro: Marker2D

var secuencia_activada: bool = false
var luto_ya_ladro: bool = false

@onready var jugador: CharacterBody2D = $OnTheGround/Player
@onready var sprite_jugador: AnimatedSprite2D = jugador.get_node("%PlayerSprite")
@onready var luto: CharacterBody2D = $OnTheGround/Luto
@onready var luto_sprite: AnimatedSprite2D = $OnTheGround/Luto/AnimatedSprite2D
@onready var cinematic: Cinematic = $Cinematic
@onready var detector_dialogo: Area2D = $OnTheGround/DetectorDialogo


func _ready() -> void:
	# La cinemática la lanza este script, no la escena.
	cinematic.autostart = false

	luto.add_child(EfectoFantasma.new())
	ColisionSimple.poner(get_node_or_null("OnTheGround/Lazaro"))

	hacer_que_luto_corra()


func _process(_delta: float) -> void:
	if luto_ya_ladro or secuencia_activada:
		return
	# La zona real del detector es su forma de colisión, no el nodo en sí.
	var punto := detector_dialogo.global_position
	for hijo in detector_dialogo.get_children():
		if hijo is CollisionShape2D:
			punto = hijo.global_position
			break
	var distancia := jugador.global_position.distance_to(punto)
	if distancia < DISTANCIA_LADRIDO_DE_LUTO:
		luto_ya_ladro = true
		_luto_ladra()


func _luto_ladra() -> void:
	Ladrido.sonar(self, luto.global_position, 2)
	if not luto_sprite.sprite_frames.has_animation(&"bark") or luto_sprite.animation == &"walk":
		return
	luto_sprite.play(&"bark")
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(luto_sprite) and luto_sprite.animation == &"bark":
		luto_sprite.play(&"idle")


func hacer_que_luto_corra() -> void:
	luto_sprite.play("walk")

	var tween = create_tween()
	tween.tween_property(luto, "global_position", posicion_junto_a_lazaro.global_position, 2.0)
	await tween.finished

	luto_sprite.play("idle")


## La llama la señal del detector cuando Lino lo pisa.
func _on_detector_dialogo_body_entered(body: Node2D) -> void:
	if body.name == "Player" and not secuencia_activada:
		secuencia_activada = true
		comenzar_secuencia_cinematica()


func comenzar_secuencia_cinematica() -> void:
	if jugador.has_method("take_control"):
		jugador.take_control(self)

	jugador.velocity = Vector2.ZERO
	await get_tree().physics_frame

	while jugador.global_position.distance_to(punto_parada_lino.global_position) > 5.0:
		var direccion = (punto_parada_lino.global_position - jugador.global_position).normalized()

		jugador.velocity = direccion * 80.0
		jugador.move_and_slide()

		if sprite_jugador.animation != "walk":
			sprite_jugador.play("walk")

		await get_tree().physics_frame

	jugador.velocity = Vector2.ZERO

	# Mira a la derecha, hacia Luto: el sprite solo cambia de lado al moverse.
	sprite_jugador.play("idle")
	sprite_jugador.flip_h = false

	var bloqueo := BloqueoSaltoDialogo.new()
	add_child(bloqueo)
	cinematic.start()
	await cinematic.cinematic_finished
	bloqueo.queue_free()

	var puerta_secreta = get_tree().get_first_node_in_group("puerta_cinematica")

	if puerta_secreta != null:
		if puerta_secreta.has_method("abrir_puerta_secreta"):
			puerta_secreta.abrir_puerta_secreta()
		else:
			push_error("El nodo encontrado no tiene la función abrir_puerta_secreta")
	else:
		push_error("No se encontró la puerta.")

	if jugador.has_method("return_control"):
		jugador.return_control(self)
