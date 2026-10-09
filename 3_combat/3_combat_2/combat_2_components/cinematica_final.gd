# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node
## La cinemática final del 3.2, al recoger el último hilo.
##
## Elián se desvanece. En un recuerdo (entre fundidos a blanco), Luto corre
## hasta Lázaro, Lázaro habla y los dos se van en paz. Después, ya con todo el
## color, Lino escapa del vacío por la puerta y pasa al outro.

## "6. Embers of Hope (Loop).ogg" de renya_beyond_sorrow.
const MUSICA_DE_LAZARO: AudioStream = preload("uid://y0pa0a2b8n6n")
## elian_dissapear.wav
const SONIDO_ELIAN_DESAPARECE: AudioStream = preload("uid://bfjawnnd00a8k")

const DURACION_DESVANECER_ELIAN: float = 2.7
const ZOOM_SOBRE_LAZARO := Vector2(1.5, 1.5)
## Cuánto sube y baja Lázaro mientras flota, y en cuánto tiempo.
const FLOTE_ALTURA: float = 5.0
const FLOTE_DURACION: float = 1.0
## Dónde se detiene Luto junto a Lázaro (a su lado y a sus pies), y a qué velocidad corre.
const DISTANCIA_LUTO_A_LAZARO: float = 46.0
const ALTURA_LUTO_JUNTO_A_LAZARO: float = 36.0
const VELOCIDAD_LUTO: float = 260.0
const DURACION_LADRIDO: float = 1.5
const DURACION_DESPEDIDA: float = 3.0
## Lino corre desde el puente hasta la puerta y entra apenas antes que el vacío.
const DISTANCIA_ESCAPE: float = 240.0
const TIEMPO_ESCAPE_LINO: float = 2.6
const VENTAJA_SOBRE_EL_VACIO: float = 0.25

var jugador: Player
var elian: Node2D
var lazaro: AnimatedSprite2D
var luto: Node2D
var puerta_salida: Node2D
var particulas_perdon: GPUParticles2D
var efectos: Node
var saturacion_manager: Node
var dialogo_lazaro: DialogueResource
var titulo_dialogo_lazaro: String
var escena_outro: PackedScene
## Lo que se oculta al empezar: ya no queda nada por hacer.
var interfaz: Array[CanvasLayer] = []
## Para los sonidos de Elián (se apagan poco a poco, sin cortarse).
var reir: Callable

var _capa_fundido := CanvasLayer.new()
var _fundido := ColorRect.new()
var _sprite_luto: AnimatedSprite2D
var _altura_lazaro: float = 0.0
var _flote_lazaro: Tween
var _flote_luto: Tween


func reproducir() -> void:
	if is_instance_valid(elian):
		await _desvanecer_a_elian()

	for capa in interfaz:
		capa.visible = false
	efectos.mostrar_puerta()
	efectos.iniciar_ondas_de_color()
	efectos.temblar(efectos.TEMBLOR_LEVE)

	_preparar_fundido()
	await _fundir(Color.WHITE, 3.0).finished

	var camara_de_lino := get_viewport().get_camera_2d()
	var camara := Camera2D.new()
	camara.global_position = lazaro.global_position
	camara.zoom = ZOOM_SOBRE_LAZARO
	add_child(camara)
	camara.make_current()
	efectos.restaurar_musica()
	MusicPlayer.play_stream(MUSICA_DE_LAZARO)
	_hacer_flotar_a_lazaro()
	_sprite_luto = luto.get_node("AnimatedSprite2D")
	EfectoFantasma.quitar_de(luto)

	await _aclarar(2.5).finished
	await _luto_corre_hacia_lazaro()
	await _hablar_con_lazaro()
	await _despedir_a_lazaro_y_luto()

	await _fundir(Color.BLACK, 2.5).finished
	camara_de_lino.make_current()
	camara.queue_free()
	await _escapar_del_vacio(camara_de_lino)


func _desvanecer_a_elian() -> void:
	reir.call(1.0, SONIDO_ELIAN_DESAPARECE)
	var sprite := elian.get_node("AnimatedSprite2D") as CanvasItem
	var origen := elian.position
	var vibrar := create_tween()
	for i in 60:
		var sacudida := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		vibrar.tween_property(elian, "position", origen + sacudida, 0.05)
	vibrar.tween_property(elian, "position", origen, 0.05)
	await get_tree().create_timer(0.3).timeout

	# Sin el filtro del mundo, para que se vaya con su color.
	elian.material = null
	sprite.material = null
	var desvanecer := create_tween().set_parallel(true)
	desvanecer.tween_property(elian, "modulate:a", 0.0, DURACION_DESVANECER_ELIAN)
	desvanecer.tween_property(sprite, "modulate:a", 0.0, DURACION_DESVANECER_ELIAN)
	await desvanecer.finished
	elian.queue_free()


func _preparar_fundido() -> void:
	_capa_fundido.layer = 100
	_fundido.color = Color(1.0, 1.0, 1.0, 0.0)
	_fundido.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capa_fundido.add_child(_fundido)
	add_child(_capa_fundido)


## La pantalla se cubre de [param color].
func _fundir(color: Color, duracion: float) -> Tween:
	_fundido.color = Color(color, _fundido.color.a)
	var fundir := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fundir.tween_property(_fundido, "color:a", 1.0, duracion)
	return fundir


func _aclarar(duracion: float) -> Tween:
	var aclarar := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	aclarar.tween_property(_fundido, "color:a", 0.0, duracion)
	return aclarar


func _hacer_flotar_a_lazaro() -> void:
	_altura_lazaro = lazaro.position.y
	lazaro.play(&"idle")
	_flote_lazaro = create_tween().set_loops()
	_flote_lazaro.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flote_lazaro.tween_property(
		lazaro, "position:y", _altura_lazaro - FLOTE_ALTURA, FLOTE_DURACION
	)
	_flote_lazaro.tween_property(lazaro, "position:y", _altura_lazaro, FLOTE_DURACION)


## Luto corre hasta quedar pegado a Lázaro, del lado por el que llega, y se
## queda flotando con él.
func _luto_corre_hacia_lazaro() -> void:
	var lado := signf(luto.global_position.x - lazaro.global_position.x)
	if is_zero_approx(lado):
		lado = -1.0
	var destino := (
		lazaro.global_position + Vector2(lado * DISTANCIA_LUTO_A_LAZARO, ALTURA_LUTO_JUNTO_A_LAZARO)
	)

	_sprite_luto.flip_h = destino.x < luto.global_position.x
	_sprite_luto.play(&"walk")
	_sprite_luto.speed_scale = 2.0
	var duracion := maxf(luto.global_position.distance_to(destino) / VELOCIDAD_LUTO, 0.4)
	var correr := create_tween()
	correr.tween_property(luto, "global_position", destino, duracion).set_trans(Tween.TRANS_SINE)
	await correr.finished

	_sprite_luto.speed_scale = 1.0
	_sprite_luto.play(&"idle")
	_sprite_luto.flip_h = lazaro.global_position.x < luto.global_position.x
	lazaro.flip_h = luto.global_position.x < lazaro.global_position.x

	var altura_luto := _sprite_luto.position.y
	_flote_luto = create_tween().set_loops()
	_flote_luto.tween_method(
		func(_avance: float) -> void:
			_sprite_luto.position.y = altura_luto + lazaro.position.y - _altura_lazaro,
		0.0,
		1.0,
		FLOTE_DURACION
	)


## Lázaro habla y Luto le responde ladrando.
func _hablar_con_lazaro() -> void:
	if not dialogo_lazaro:
		return
	var bloqueo := BloqueoSaltoDialogo.new()
	add_child(bloqueo)
	DialogueManager.show_dialogue_balloon(dialogo_lazaro, titulo_dialogo_lazaro)
	await DialogueManager.dialogue_ended
	bloqueo.queue_free()

	_sprite_luto.play(&"bark")
	Ladrido.sonar(self, luto.global_position)
	await get_tree().create_timer(DURACION_LADRIDO).timeout
	_sprite_luto.play(&"idle")


## Lázaro y Luto se desvanecen en paz, con su color, y la niebla se va.
func _despedir_a_lazaro_y_luto() -> void:
	_flote_lazaro.kill()
	_flote_luto.kill()
	lazaro.position.y = _altura_lazaro
	for figura: CanvasItem in [lazaro, luto, _sprite_luto]:
		figura.use_parent_material = false
		figura.material = null

	efectos.disipar_niebla()
	var despedida := create_tween().set_parallel(true)
	for figura: CanvasItem in [lazaro, luto, _sprite_luto]:
		despedida.tween_property(figura, "modulate:a", 0.0, DURACION_DESPEDIDA)
	await despedida.finished
	lazaro.queue_free()
	luto.queue_free()


## Ya con todo el color, el mundo tiembla con fuerza y Lino corre a la puerta
## mientras el vacío se cierra detrás de él.
func _escapar_del_vacio(camara: Camera2D) -> void:
	if is_instance_valid(saturacion_manager):
		saturacion_manager.tope_saturacion_mundo = 1.0
	efectos.temblar(efectos.TEMBLOR_FUERTE, 0.6)
	particulas_perdon.emitting = true
	puerta_salida.open()

	var puerta := puerta_salida.global_position
	jugador.global_position = puerta + Vector2(0, DISTANCIA_ESCAPE)
	camara.reset_smoothing()
	_aclarar(2.0)
	await get_tree().create_timer(0.8).timeout

	efectos.lanzar_vacio(TIEMPO_ESCAPE_LINO + VENTAJA_SOBRE_EL_VACIO)
	jugador.get_node("%PlayerSprite").play(&"walk")
	var escape := create_tween().set_parallel(true)
	escape.tween_property(jugador, "global_position", puerta, TIEMPO_ESCAPE_LINO)
	escape.tween_property(camara, "zoom", camara.zoom * 0.65, TIEMPO_ESCAPE_LINO).set_trans(
		Tween.TRANS_SINE
	)
	await escape.finished
	await get_tree().create_timer(VENTAJA_SOBRE_EL_VACIO).timeout

	await efectos.iris_blanco_desde(_capa_fundido)
	SceneSwitcher.change_to_packed_with_transition.call_deferred(
		escena_outro, "", Transition.Effect.LEFT_TO_RIGHT_WIPE, Transition.Effect.RIGHT_TO_LEFT_WIPE
	)
