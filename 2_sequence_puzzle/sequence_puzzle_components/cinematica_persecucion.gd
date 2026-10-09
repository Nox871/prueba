# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Area2D

## Cada cuánto suelta polvo el vacío mientras está quieto (si no, no se le ve).
const PAUSA_ENTRE_POLVOS: float = 0.12
## Cada vez que Lino se deshila en este nivel, el vacío lo persigue un poco
## más lento (esta parte menos por muerte), sin bajar de [constant VELOCIDAD_MINIMA]
## de su velocidad normal.
const FRENO_POR_MUERTE: float = 0.06
const VELOCIDAD_MINIMA: float = 0.6

@export var enemigo_vacio: Node2D

@export_group("Tiempos de la Cinemática")
@export var tiempo_viaje_ida: float = 1.2  # Segundos que tarda en llegar al monstruo
@export var tiempo_pausa_mirando: float = 1.1  # Segundos que lo ves correr hacia ti
@export var tiempo_viaje_vuelta: float = 0.8  # Segundos que tarda en regresar a Lino
## Zoom durante la cinemática (1.0, 1.0 es el normal).
@export var zoom_acercamiento: Vector2 = Vector2(1.4, 1.4)

@export_group("Persecución")
## Velocidad del vacío mientras persigue a Lino (Lino corre a 230).
@export var velocidad_de_persecucion: float = 145.0
## Si el vacío está más cerca que esto cuando Lino recupera el control, espera
## lo que tardaría en recorrer la diferencia: así Lino siempre sale con ventaja.
@export var ventaja_minima: float = 650.0
## Tope de esa espera, en segundos.
@export var espera_maxima: float = 4.0

var secuencia_activada: bool = false
var vacio_quieto: bool = false
var proximo_polvo: float = 0.0


## El vacío solo se ve por el polvo que deja al moverse: quieto, hay que soltarlo.
func _process(delta: float) -> void:
	if not vacio_quieto or not is_instance_valid(enemigo_vacio):
		return
	proximo_polvo -= delta
	if proximo_polvo <= 0.0:
		proximo_polvo = PAUSA_ENTRE_POLVOS
		enemigo_vacio.call("_emit_particles")


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or secuencia_activada:
		return

	secuencia_activada = true
	var paso_del_vacio: Node = enemigo_vacio.get("path_walk_behavior")
	if paso_del_vacio:
		paso_del_vacio.process_mode = Node.PROCESS_MODE_DISABLED
	_permitir_captura(false)
	vacio_quieto = true

	if body.has_method("take_control"):
		body.take_control(self)
	body.velocity = Vector2.ZERO

	var camara = get_viewport().get_camera_2d()
	var zoom_original = camara.zoom
	var suavizado_original = camara.position_smoothing_enabled
	camara.position_smoothing_enabled = false

	var cinematica = create_tween()

	(
		cinematica
		. tween_property(camara, "global_position", enemigo_vacio.global_position, tiempo_viaje_ida)
		. set_trans(Tween.TRANS_SINE)
	)
	cinematica.parallel().tween_property(camara, "zoom", zoom_acercamiento, tiempo_viaje_ida)

	cinematica.tween_callback(
		func():
			var alerta: AnimationPlayer = enemigo_vacio.get("alert_animation")
			if alerta:
				alerta.play(&"alert")
	)

	cinematica.tween_interval(tiempo_pausa_mirando)

	(
		cinematica
		. tween_property(camara, "global_position", body.global_position, tiempo_viaje_vuelta)
		. set_trans(Tween.TRANS_QUAD)
	)
	cinematica.parallel().tween_property(camara, "zoom", zoom_original, tiempo_viaje_vuelta)

	await cinematica.finished

	camara.position_smoothing_enabled = suavizado_original
	camara.global_position = body.global_position

	if body.has_method("return_control"):
		body.return_control(self)

	var velocidad: float = (
		velocidad_de_persecucion
		* ElHiloQueNoTejiState.alivio_por_muertes(
			"sequence_puzzle", FRENO_POR_MUERTE, VELOCIDAD_MINIMA
		)
	)
	var seguimiento: Node = enemigo_vacio.get("follow_walk_behavior")
	if seguimiento and seguimiento.get("speeds"):
		seguimiento.speeds.walk_speed = velocidad
	var distancia: float = enemigo_vacio.global_position.distance_to(body.global_position)
	var espera := clampf((ventaja_minima - distancia) / velocidad, 0.0, espera_maxima)
	if espera > 0.0:
		await get_tree().create_timer(espera, false).timeout
	vacio_quieto = false
	if is_instance_valid(enemigo_vacio) and enemigo_vacio.has_method("start"):
		enemigo_vacio.start(body)
	_permitir_captura(true)


func _permitir_captura(permitir: bool) -> void:
	var captura := enemigo_vacio.get_node_or_null("PlayerCaptureArea") as Area2D
	if captura:
		captura.set_deferred("monitoring", permitir)
