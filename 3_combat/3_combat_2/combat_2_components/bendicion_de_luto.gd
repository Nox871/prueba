# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node
## La bendición de Luto: cuando Lino ya se deshiló dos veces en este nivel,
## Luto aparece un momento junto a Lino como fantasma, ladra tres veces, Lino
## lo reconoce en un pensamiento y Luto se desvanece. Desde entonces, los proyectiles que se
## le acercan pierden velocidad, para que pueda esquivarlos o repelerlos.
##
## Se añade sola desde efectos_final.gd.

## El nombre con que el nivel lleva la cuenta en ElHiloQueNoTejiState.
const NIVEL: String = "combat_2"
## Veces que Lino tiene que deshilarse para que llegue la bendición.
const MUERTES_PARA_LA_BENDICION: int = 2
## Título del diálogo de Luto dentro de [constant DIALOGO].
const TITULO_DIALOGO: String = "bendicion_de_luto"
const DIALOGO: DialogueResource = preload("dialogos_lino_minijuego3.dialogue")
## Lo que piensa Lino después de los ladridos. Nombra a Luto porque Luto no
## se ve: solo se le oye.
const PENSAMIENTO_DE_LINO: String = "Luto... tú tampoco quieres que me pierda aquí, ¿verdad?"
## El globo de pensamientos de Lino, en el HUD del nivel.
const RUTA_GLOBO_DE_LINO: NodePath = ^"HUD/PanelContainer"
## luto.tres
const FIGURA_DE_LUTO: SpriteFrames = preload("uid://crrr8ncum86vx")
## Dónde puede aparecer Luto respecto a Lino, en orden de preferencia. Se usa el
## primero que quede libre y a la vista (sin una pared en medio).
const LUGARES_PARA_LUTO: Array[Vector2] = [
	Vector2(-80, 0),
	Vector2(80, 0),
	Vector2(-70, 45),
	Vector2(70, 45),
	Vector2(0, 75),
	Vector2(-110, -15),
	Vector2(110, -15),
]
## Lo que choca con Lino: paredes y bordes (sin las sombras).
const CAPAS_DE_PARED: int = 1 | 16 | 512
## Espacio libre que necesita Luto alrededor de sus pies.
const RADIO_DE_LUTO: float = 22.0
## El dibujo de Luto está centrado; sus pies quedan este tanto más abajo.
const PIES_DE_LUTO: float = 40.0
const OPACIDAD_DE_LUTO: float = 0.8
const DURACION_APARECER: float = 0.5
const DURACION_DESAPARECER: float = 0.9
## Cuánto se queda Luto después de que Lino piensa en él.
const ESPERA_ANTES_DE_IRSE: float = 2.5
const LADRIDOS: int = 3
const PAUSA_ENTRE_LADRIDOS: float = 0.38
## Espera desde que Lino reaparece hasta que Luto ladra.
const ESPERA_INICIAL: float = 1.5
## A esta distancia de Lino, un proyectil que viene hacia él empieza a frenar.
const DISTANCIA_DE_FRENADO: float = 260.0
## Parte de su velocidad con la que se queda (0.65 = un 35 % más lento).
const VELOCIDAD_AL_FRENAR: float = 0.65
## Lo que tarda en perder esa velocidad, en segundos.
const TIEMPO_DE_FRENADO: float = 0.35
const GRUPO_PROYECTILES: StringName = &"projectiles"
const META_VELOCIDAD: StringName = &"velocidad_antes_de_luto"

# Luto solo lo anuncia una vez por partida; el efecto sigue en cada intento.
static var anunciada_en_partida: int = -1

var jugador: Node2D

var _en_dialogo: bool = false
var _espera: float = ESPERA_INICIAL


func _ready() -> void:
	if ElHiloQueNoTejiState.muertes_en(NIVEL) < MUERTES_PARA_LA_BENDICION:
		set_process(false)
		set_physics_process(false)
		return
	if DialogueManager.has_signal("dialogue_started"):
		DialogueManager.dialogue_started.connect(func(_recurso): _en_dialogo = true)
	DialogueManager.dialogue_ended.connect(func(_recurso): _en_dialogo = false)


func _process(delta: float) -> void:
	if anunciada_en_partida == ElHiloQueNoTejiState.numero_partida:
		set_process(false)
		return
	_espera -= delta
	if _espera > 0.0 or _en_dialogo or not is_instance_valid(jugador):
		return
	if jugador.get("mode") != 0:
		return
	anunciada_en_partida = ElHiloQueNoTejiState.numero_partida
	set_process(false)
	_anunciar()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(jugador):
		return
	for proyectil in get_tree().get_nodes_in_group(GRUPO_PROYECTILES):
		var cuerpo := proyectil as RigidBody2D
		if not cuerpo:
			continue
		var hacia_lino: Vector2 = jugador.global_position - cuerpo.global_position
		var velocidad: Vector2 = cuerpo.linear_velocity
		# Solo los que vienen hacia Lino: los que él repele se van a su velocidad.
		if hacia_lino.length() > DISTANCIA_DE_FRENADO or velocidad.dot(hacia_lino) <= 0.0:
			continue
		# Su velocidad normal es la mayor que haya traído (rebota sin perderla).
		var normal: float = maxf(cuerpo.get_meta(META_VELOCIDAD, 0.0), velocidad.length())
		cuerpo.set_meta(META_VELOCIDAD, normal)
		var frenada: float = normal * VELOCIDAD_AL_FRENAR
		if velocidad.length() <= frenada:
			continue
		var paso: float = (normal - frenada) * delta / TIEMPO_DE_FRENADO
		cuerpo.linear_velocity = velocidad.normalized() * maxf(velocidad.length() - paso, frenada)


## Luto ladra tres veces. Su globo sale arriba y no detiene la pelea.
func _anunciar() -> void:
	var luto := _aparecer_luto()
	var globo: Node = DialogueManager.show_dialogue_balloon(DIALOGO, TITULO_DIALOGO)
	if is_instance_valid(globo):
		globo.set("will_block_other_input", false)
		# El globo arma sus piezas al entrar en escena: hay que esperar a que esté listo.
		if not globo.is_node_ready():
			await globo.ready
		if is_instance_valid(globo) and globo.get("balloon_container") != null:
			globo.anchor_to_top()
	if is_instance_valid(luto):
		luto.play(&"bark")
	for i in LADRIDOS:
		if not is_instance_valid(jugador):
			return
		var desde := luto.global_position if is_instance_valid(luto) else jugador.global_position
		Ladrido.sonar(self, desde, 1)
		await get_tree().create_timer(PAUSA_ENTRE_LADRIDOS).timeout
	if is_instance_valid(luto):
		luto.play(&"idle")
	if _en_dialogo:
		await DialogueManager.dialogue_ended
	if not is_instance_valid(jugador) or not jugador.owner:
		_desvanecer(luto)
		return
	var globo_de_lino := jugador.owner.get_node_or_null(RUTA_GLOBO_DE_LINO)
	if is_instance_valid(globo_de_lino) and globo_de_lino.has_method("mostrar_pensamiento"):
		globo_de_lino.mostrar_pensamiento(PENSAMIENTO_DE_LINO)
	await get_tree().create_timer(ESPERA_ANTES_DE_IRSE).timeout
	_desvanecer(luto)


## Luto aparece como fantasma junto a Lino, mirándolo, en un lugar libre y a la
## vista. Si no hay ninguno, no aparece (solo se le oye).
func _aparecer_luto() -> AnimatedSprite2D:
	var lugar: Variant = _lugar_libre_junto_a_lino()
	if lugar == null:
		return null
	var luto := AnimatedSprite2D.new()
	luto.sprite_frames = FIGURA_DE_LUTO
	luto.animation = &"idle"
	luto.play()
	luto.z_index = jugador.z_index
	jugador.get_parent().add_child(luto)
	luto.global_position = (lugar as Vector2) - Vector2(0, PIES_DE_LUTO)
	luto.flip_h = jugador.global_position.x < luto.global_position.x
	# Fantasma, pero bien visible: aquí aparece solo unos segundos, así que no
	# lleva el parpadeo de EfectoFantasma (que a veces lo deja casi invisible).
	luto.self_modulate.a = OPACIDAD_DE_LUTO
	luto.modulate.a = 0.0
	luto.create_tween().tween_property(luto, "modulate:a", 1.0, DURACION_APARECER)
	return luto


func _lugar_libre_junto_a_lino() -> Variant:
	var espacio := jugador.get_world_2d().direct_space_state
	var pies := CircleShape2D.new()
	pies.radius = RADIO_DE_LUTO
	var consulta := PhysicsShapeQueryParameters2D.new()
	consulta.shape = pies
	consulta.collision_mask = CAPAS_DE_PARED
	for desplazamiento in LUGARES_PARA_LUTO:
		var lugar := jugador.global_position + desplazamiento
		consulta.transform = Transform2D(0.0, lugar)
		if not espacio.intersect_shape(consulta, 1).is_empty():
			continue
		var rayo := PhysicsRayQueryParameters2D.create(
			jugador.global_position, lugar, CAPAS_DE_PARED
		)
		if jugador is CollisionObject2D:
			rayo.exclude = [(jugador as CollisionObject2D).get_rid()]
		if espacio.intersect_ray(rayo).is_empty():
			return lugar
	return null


func _desvanecer(luto: AnimatedSprite2D) -> void:
	if not is_instance_valid(luto):
		return
	var irse := luto.create_tween()
	irse.tween_property(luto, "modulate:a", 0.0, DURACION_DESAPARECER)
	irse.tween_callback(luto.queue_free)
