# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name AnimacionDeElian
extends RefCounted
## Los tiempos de animación de Elián.
##
## Elián es una sombra que lanza (throwing_enemy), y su AnimationPlayer está
## hecho para las sombras pequeñas: su "idle" pasa los cuadros en 0,7 s y su
## ataque en 1 s, demasiado rápido y a saltos para los dibujos de Elián. Aquí se
## cambian solo para él, sin tocar la escena de las sombras:
##   idle: los 4 cuadros de elian_idle.png, a un ritmo tranquilo.
##   attack: levanta la mano despacio (anticipación), se echa atrás, golpea
##           (sale el orbe), se queda un momento con la mano abierta y baja la
##           mano por los cuadros de la anticipación al revés, hasta la pose
##           del "idle". Así no salta de la mano arriba a la mano en la mesa.
## Además, las sombras se dan vuelta hacia Lino justo al lanzar; en Elián, que es
## enorme, ese giro en medio del golpe se nota. Por eso él se vuelve hacia Lino
## al empezar a preparar el ataque y se queda así hasta el siguiente.

## Segundos de cada cuadro del "idle".
const SEGUNDOS_POR_CUADRO_IDLE: float = 0.28
const CUADROS_IDLE: Array[int] = [0, 1, 2, 3]
## Cada paso del ataque: [animación, cuadro, segundos].
const ATAQUE: Array = [
	[&"attack anticipation", 0, 0.22],
	[&"attack anticipation", 1, 0.22],
	[&"attack anticipation", 2, 0.22],
	[&"attack anticipation", 3, 0.22],
	[&"attack", 0, 0.12],
	[&"attack", 1, 0.12],
	[&"attack", 2, 0.16],
	[&"attack", 3, 0.3],
	[&"attack anticipation", 2, 0.16],
	[&"attack anticipation", 1, 0.16],
	[&"attack anticipation", 0, 0.2],
]
## El orbe sale en el golpe (cuadro 2 de "attack").
const PASO_DEL_LANZAMIENTO: int = 6

## El AnimatedSprite2D avanza solo sus cuadros; para que se quede en el que
## toca, el cuadro se vuelve a poner cada tanto.
const REPETIR_CUADRO_CADA: float = 0.05

const PISTA_ANIMACION := NodePath("AnimatedSprite2D:animation")
const PISTA_CUADRO := NodePath("AnimatedSprite2D:frame")
const MIRADA: StringName = &"MiradaDeElian"


## Le pone a [param elian] su "idle" y su "attack". Las animaciones de las demás
## sombras no cambian: Elián recibe su propia copia.
static func aplicar(elian: Node) -> void:
	var reproductor := elian.get_node_or_null("%AnimationPlayer") as AnimationPlayer
	if not reproductor or not reproductor.has_animation_library(&""):
		return
	var biblioteca := reproductor.get_animation_library(&"").duplicate() as AnimationLibrary
	var idle := biblioteca.get_animation(&"idle").duplicate(true) as Animation
	var ataque := biblioteca.get_animation(&"attack").duplicate(true) as Animation
	_rehacer_idle(idle)
	_rehacer_ataque(ataque)
	biblioteca.add_animation(&"idle", idle)
	biblioteca.add_animation(&"attack", ataque)
	var mirada := Mirada.new()
	mirada.name = MIRADA
	mirada.lado = (elian as Node2D).scale.x
	elian.add_child(mirada)
	var actual := reproductor.current_animation
	reproductor.remove_animation_library(&"")
	reproductor.add_animation_library(&"", biblioteca)
	if actual:
		reproductor.play(actual)


## Cuando la pelea termina, Elián deja de atacar pero sigue en su "idle".
static func quedarse_en_reposo(elian: Node) -> void:
	var temporizador := elian.get_node_or_null("Timer") as Timer
	if temporizador:
		temporizador.stop()
	var reproductor := elian.get_node_or_null("%AnimationPlayer") as AnimationPlayer
	if reproductor:
		reproductor.play(&"idle")
	elian.set(&"_is_attacking", false)


static func _rehacer_idle(idle: Animation) -> void:
	var cuadros := _pista(idle, PISTA_CUADRO)
	_vaciar(idle, cuadros)
	idle.value_track_set_update_mode(cuadros, Animation.UPDATE_DISCRETE)
	var tiempo := 0.0
	for cuadro in CUADROS_IDLE:
		_sostener(idle, cuadros, tiempo, SEGUNDOS_POR_CUADRO_IDLE, cuadro)
		tiempo += SEGUNDOS_POR_CUADRO_IDLE
	idle.length = tiempo


static func _rehacer_ataque(ataque: Animation) -> void:
	var nombres := _pista(ataque, PISTA_ANIMACION)
	var cuadros := _pista(ataque, PISTA_CUADRO)
	_vaciar(ataque, nombres)
	_vaciar(ataque, cuadros)
	ataque.value_track_set_update_mode(cuadros, Animation.UPDATE_DISCRETE)
	var tiempo := 0.0
	var lanzamiento := 0.0
	var anterior := &""
	for indice in ATAQUE.size():
		var paso: Array = ATAQUE[indice]
		if paso[0] != anterior:
			ataque.track_insert_key(nombres, tiempo, paso[0])
			anterior = paso[0]
		_sostener(ataque, cuadros, tiempo, paso[2], paso[1])
		if indice == PASO_DEL_LANZAMIENTO:
			lanzamiento = tiempo
		tiempo += paso[2]
	ataque.length = tiempo
	for pista in ataque.get_track_count():
		if ataque.track_get_type(pista) == Animation.TYPE_METHOD:
			for clave in ataque.track_get_key_count(pista):
				ataque.track_set_key_time(pista, clave, lanzamiento)
	# Al empezar mira a Lino; al lanzar (en una pista que va después de la del
	# lanzamiento) deshace la vuelta que da la sombra al disparar.
	var mirar := ataque.add_track(Animation.TYPE_METHOD)
	ataque.track_set_path(mirar, NodePath(MIRADA))
	ataque.track_insert_key(mirar, 0.0, {"method": &"mirar_a_lino", "args": []})
	var mantener := ataque.add_track(Animation.TYPE_METHOD)
	ataque.track_set_path(mantener, NodePath(MIRADA))
	ataque.track_insert_key(mantener, lanzamiento, {"method": &"mantener", "args": []})


## Pone [param cuadro] desde [param desde] durante [param duracion].
static func _sostener(
	animacion: Animation, pista: int, desde: float, duracion: float, cuadro: int
) -> void:
	var tiempo := 0.0
	while tiempo < duracion - 0.001:
		animacion.track_insert_key(pista, desde + tiempo, cuadro)
		tiempo += REPETIR_CUADRO_CADA


static func _pista(animacion: Animation, ruta: NodePath) -> int:
	var pista := animacion.find_track(ruta, Animation.TYPE_VALUE)
	if pista < 0:
		pista = animacion.add_track(Animation.TYPE_VALUE)
		animacion.track_set_path(pista, ruta)
	return pista


static func _vaciar(animacion: Animation, pista: int) -> void:
	while animacion.track_get_key_count(pista) > 0:
		animacion.track_remove_key(pista, 0)


## Hacia qué lado mira Elián (1 o -1 en scale.x).
class Mirada:
	extends Node

	var lado: float = 1.0

	func mirar_a_lino() -> void:
		var elian := get_parent() as Node2D
		var lino := get_tree().get_first_node_in_group("player") as Node2D
		if lino:
			lado = 1.0 if lino.global_position.x < elian.global_position.x else -1.0
		elian.scale.x = lado

	func mantener() -> void:
		(get_parent() as Node2D).scale.x = lado
