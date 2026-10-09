# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Area2D
## La llegada del vacío: cuando Lino entra a la isla del primer puzzle, el vacío
## baja desde el norte y deshace los puentes uno por uno. Después se queda
## rondando la isla, como siempre.
##
## Durante la cinemática el vacío NO deja rastro: se le quita su capa de tiles
## para que no vuelva intransitable nada de lo que cruza. Solo se deshacen los
## puentes. Al terminar recupera su capa y empieza su ronda normal.

const ESTADO_RONDA: int = 0  # State.IDLE del vacío
const MODO_DERROTADO: int = 2  # Player.Mode.DEFEATED

## Solo se ve una vez por partida (no se repite si Lino muere y el nivel se recarga).
static var vista: bool = false

@export var enemigo_vacio: Node2D
## Puentes enteros, en el orden en que el vacío los rompe (del más lejano al más cercano).
@export var puentes: Array[TileMapLayer]
## Puente roto que queda en lugar de cada uno, en el mismo orden.
@export var puentes_rotos: Array[TileMapLayer]
## Punto de la ruta de ronda del vacío donde empieza a rondar al terminar. El 2
## está en el borde sur de la isla: desde ahí la rodea entera antes de entrar.
@export var punto_de_inicio_de_ronda: int = 2

@export_group("Tiempos")
@export var tiempo_camara_ida: float = 1.2
## Velocidad del vacío mientras cruza un puente, en píxeles por segundo.
@export var velocidad_sobre_puente: float = 800.0
## Velocidad del vacío entre un puente y el siguiente.
@export var velocidad_entre_puentes: float = 1300.0
@export var pausa_final: float = 0.6
@export var tiempo_camara_vuelta: float = 1.0

var capa_del_vacio: TileMapLayer
var camara: Camera2D
var camara_sigue_al_vacio: bool = false


func _ready() -> void:
	body_entered.connect(_al_entrar)
	if vista or not is_instance_valid(enemigo_vacio):
		return
	if not enemigo_vacio.is_node_ready():
		await enemigo_vacio.ready
	_dormir_al_vacio()


func _process(_delta: float) -> void:
	if camara_sigue_al_vacio and is_instance_valid(camara):
		camara.global_position = enemigo_vacio.global_position


## Antes de la cinemática el vacío espera lejos, al norte, sin moverse, sin
## dejar rastro y sin poder atrapar a Lino.
func _dormir_al_vacio() -> void:
	capa_del_vacio = enemigo_vacio.void_layer
	enemigo_vacio.void_layer = null
	enemigo_vacio.path_walk_behavior.process_mode = Node.PROCESS_MODE_DISABLED
	enemigo_vacio.idle_sfx.stop()
	_permitir_captura(false)
	if not puentes.is_empty():
		enemigo_vacio.global_position = _extremos(puentes[0])[0] + Vector2(0, -600)


func _al_entrar(cuerpo: Node2D) -> void:
	if vista or not cuerpo.is_in_group("player") or not is_instance_valid(enemigo_vacio):
		return
	vista = true

	cuerpo.take_control(self)
	cuerpo.velocity = Vector2.ZERO
	var sombras := _congelar_sombras()

	camara = get_viewport().get_camera_2d()
	var posicion_camara := camara.position
	var suavizado := camara.position_smoothing_enabled
	camara.position_smoothing_enabled = false

	var extremos := _extremos(puentes[0])
	var posicion := extremos[0]
	if (
		extremos[1].distance_to(cuerpo.global_position)
		> posicion.distance_to(cuerpo.global_position)
	):
		posicion = extremos[1]
	enemigo_vacio.global_position = posicion

	var ida := create_tween()
	ida.tween_property(camara, "global_position", posicion, tiempo_camara_ida).set_trans(
		Tween.TRANS_SINE
	)
	await ida.finished
	camara_sigue_al_vacio = true

	for i in puentes.size():
		extremos = _extremos(puentes[i])
		var entrada := extremos[0]
		var salida := extremos[1]
		if salida.distance_to(posicion) < entrada.distance_to(posicion):
			entrada = extremos[1]
			salida = extremos[0]

		await _mover_vacio(entrada, velocidad_entre_puentes)

		var duracion := entrada.distance_to(salida) / velocidad_sobre_puente
		_deshacer_puente(puentes[i], duracion + 0.3, salida - entrada, i)
		await _mover_vacio(salida, velocidad_sobre_puente)
		posicion = salida

	var inicio_de_ronda := _inicio_de_ronda()
	await _mover_vacio(inicio_de_ronda, velocidad_sobre_puente)
	await get_tree().create_timer(maxf(pausa_final, 1.0)).timeout

	camara_sigue_al_vacio = false
	var vuelta := create_tween()
	vuelta.tween_property(camara, "position", posicion_camara, tiempo_camara_vuelta).set_trans(
		Tween.TRANS_QUAD
	)
	await vuelta.finished
	camara.position = posicion_camara
	camara.position_smoothing_enabled = suavizado

	_despertar_al_vacio()
	_descongelar_sombras(sombras)
	# Si a Lino ya lo atraparon, devolverle el control lo haría morir dos veces.
	if cuerpo.get("mode") != MODO_DERROTADO:
		cuerpo.return_control(self)


## El puente se deshace franja a franja, en la dirección en que avanza el
## vacío. Después aparece el puente roto que queda en su lugar.
func _deshacer_puente(puente: TileMapLayer, duracion: float, avance: Vector2, indice: int) -> void:
	Retejido.sonar_caida(puente)
	await Retejido.deshacer_por_franjas(puente, duracion, avance)
	if indice < puentes_rotos.size() and is_instance_valid(puentes_rotos[indice]):
		Retejido.aparecer(puentes_rotos[indice], Retejido.DURACION_BREVE)


func _mover_vacio(destino: Vector2, velocidad: float) -> void:
	var distancia := enemigo_vacio.global_position.distance_to(destino)
	if distancia < 1.0:
		return
	var viaje := create_tween()
	viaje.tween_property(enemigo_vacio, "global_position", destino, distancia / velocidad)
	await viaje.finished


## Devuelve al vacío su capa de tiles y lo pone a rondar la isla.
func _despertar_al_vacio() -> void:
	enemigo_vacio.void_layer = capa_del_vacio
	enemigo_vacio.state = ESTADO_RONDA
	_permitir_captura(true)


func _inicio_de_ronda() -> Vector2:
	var ruta: Path2D = enemigo_vacio.idle_patrol_path
	if not ruta or ruta.curve.point_count == 0:
		return enemigo_vacio.global_position
	var punto := clampi(punto_de_inicio_de_ronda, 0, ruta.curve.point_count - 1)
	return ruta.to_global(ruta.curve.get_point_position(punto))


func _permitir_captura(permitir: bool) -> void:
	var captura := enemigo_vacio.get_node_or_null("PlayerCaptureArea") as Area2D
	if captura:
		captura.set_deferred("monitoring", permitir)


## Los dos extremos de un puente, según sea vertical u horizontal.
func _extremos(puente: TileMapLayer) -> Array[Vector2]:
	var limites := TileMapMaskBounds.get_world_bounds(puente)
	var centro := limites.get_center()
	if limites.size.y >= limites.size.x:
		return [Vector2(centro.x, limites.position.y), Vector2(centro.x, limites.end.y)]
	return [Vector2(limites.position.x, centro.y), Vector2(limites.end.x, centro.y)]


## Mientras Lino no puede moverse, las sombras tampoco: no sería justo que lo
## descubrieran durante la cinemática.
func _congelar_sombras() -> Dictionary:
	var congeladas: Dictionary = {}
	for sombra in get_tree().get_nodes_in_group("guard_enemy"):
		congeladas[sombra] = sombra.process_mode
		sombra.process_mode = Node.PROCESS_MODE_DISABLED
	return congeladas


func _descongelar_sombras(congeladas: Dictionary) -> void:
	for sombra in congeladas:
		if is_instance_valid(sombra):
			sombra.process_mode = congeladas[sombra]
