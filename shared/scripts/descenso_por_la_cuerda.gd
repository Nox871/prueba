# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name DescensoPorLaCuerda
extends CanvasLayer
## La cuerda por la que Lino llega al nivel, y su bajada.
##
## La cuerda cuelga desde muy arriba hasta el punto donde empieza Lino, y se
## queda ahí todo el nivel. Se dibuja en primer plano y en perspectiva: fina
## donde toca el suelo, enorme y medio transparente (por tramado) arriba, cerca
## de la cámara. Al caminar se inclina y crece, como un objeto que queda entre
## la cámara y el suelo.
##
## La primera vez en cada partida, además, se ve la bajada: no se ve a Lino; la
## cámara baja junto a la cuerda, en la oscuridad, y Lino aparece al tocar el
## suelo.
##
## Uso, al final del _ready() del script del nivel:
##     add_child(DescensoPorLaCuerda.new())

## cuerda_en_primer_plano.gdshader
const SHADER_CUERDA: Shader = preload("../shaders/cuerda_en_primer_plano.gdshader")
## Qué tan alejada empieza la cámara (parte de su zoom normal).
const ZOOM_AL_EMPEZAR: float = 0.42
const OSCURIDAD_AL_EMPEZAR: float = 0.8
const PAUSA_ARRIBA: float = 0.6
const DURACION_DESCENSO: float = 5.0
## Lino cae el último tramo y aparece con un pequeño rebote.
const ALTURA_DE_LA_CAIDA: float = 34.0
const DURACION_APARECER: float = 0.28
const DURACION_SOLTAR_CAMARA: float = 0.8
## Cuánto corren las hebras de la cuerda durante la bajada.
const HEBRAS_AL_BAJAR: float = 14.0

## Solo se ve una vez por partida.
static var partida_vista: int = -1

var jugador: Player
var camara: Camera2D
var material_cuerda: ShaderMaterial
## Dónde toca el suelo la cuerda, en el mundo: donde empieza Lino.
var pie_de_la_cuerda: Vector2
## 0 = la cámara baja pegada a la cuerda; 1 = la cámara ya sigue a Lino.
var camara_suelta: float = 1.0


## Devuelve true la primera vez que se pregunta en cada partida.
static func toca_verlo() -> bool:
	if partida_vista == ElHiloQueNoTejiState.numero_partida:
		return false
	partida_vista = ElHiloQueNoTejiState.numero_partida
	return true


func _ready() -> void:
	layer = 0
	jugador = get_tree().get_first_node_in_group("player") as Player
	if not jugador:
		queue_free()
		return
	pie_de_la_cuerda = jugador.global_position
	material_cuerda = ShaderMaterial.new()
	material_cuerda.shader = SHADER_CUERDA
	material_cuerda.set_shader_parameter("corrimiento", 0.0)
	material_cuerda.set_shader_parameter("desvanecer", 0.0)
	var cuerda := ColorRect.new()
	cuerda.material = material_cuerda
	cuerda.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cuerda.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cuerda)
	if toca_verlo():
		_bajar.call_deferred()


func _process(_delta: float) -> void:
	# La cuerda sigue clavada en su sitio del mundo, se mueva como se mueva la cámara.
	var vista := get_viewport()
	material_cuerda.set_shader_parameter("pantalla", vista.get_visible_rect().size)
	var ancla := vista.get_canvas_transform() * pie_de_la_cuerda
	material_cuerda.set_shader_parameter("ancla", ancla)
	material_cuerda.set_shader_parameter(
		"bajo_la_camara", ancla.lerp(vista.get_visible_rect().size / 2.0, camara_suelta)
	)
	var camara_actual := vista.get_camera_2d()
	if camara_actual:
		material_cuerda.set_shader_parameter("zoom", camara_actual.zoom.x)


func _bajar() -> void:
	camara_suelta = 0.0
	jugador.take_control(self)
	jugador.velocity = Vector2.ZERO
	var visible_antes := jugador.modulate
	jugador.modulate.a = 0.0

	var oscuridad := ColorRect.new()
	oscuridad.color = Color(0, 0, 0, OSCURIDAD_AL_EMPEZAR)
	oscuridad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oscuridad.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(oscuridad)
	move_child(oscuridad, 0)

	camara = get_viewport().get_camera_2d()
	var zoom_normal := Vector2.ONE
	var suavizado := false
	if camara:
		zoom_normal = camara.zoom
		suavizado = camara.position_smoothing_enabled
		camara.position_smoothing_enabled = false
		camara.zoom = zoom_normal * ZOOM_AL_EMPEZAR
	await get_tree().create_timer(PAUSA_ARRIBA).timeout

	var bajar := create_tween().set_parallel(true)
	bajar.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bajar.tween_property(
		material_cuerda, "shader_parameter/corrimiento", HEBRAS_AL_BAJAR, DURACION_DESCENSO
	)
	bajar.tween_property(oscuridad, "color:a", 0.0, DURACION_DESCENSO)
	if camara:
		bajar.tween_property(camara, "zoom", zoom_normal, DURACION_DESCENSO)
	await bajar.finished

	var figura := jugador.get_node_or_null("%PlayerSprite") as AnimatedSprite2D
	var aparecer := create_tween().set_parallel(true)
	aparecer.tween_property(jugador, "modulate", visible_antes, DURACION_APARECER * 0.5)
	if figura:
		var lugar := figura.position
		figura.position = lugar - Vector2(0, ALTURA_DE_LA_CAIDA)
		(
			aparecer
			. tween_property(figura, "position", lugar, DURACION_APARECER)
			. set_trans(Tween.TRANS_BOUNCE)
			. set_ease(Tween.EASE_OUT)
		)
	await aparecer.finished

	if camara:
		camara.position_smoothing_enabled = suavizado
	jugador.return_control(self)
	oscuridad.queue_free()
	create_tween().tween_property(self, "camara_suelta", 1.0, DURACION_SOLTAR_CAMARA)
