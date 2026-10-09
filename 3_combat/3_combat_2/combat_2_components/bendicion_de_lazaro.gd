# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node
## La bendición de Lázaro: si el jugador pasa mucho tiempo sin llenar un jarrón,
## Lázaro le habla, una luz envuelve a Lino y desde ahí se ven la flecha de
## empuje y el brillo de los jarrones.

## Segundos sin llenar ningún jarrón para que llegue la bendición.
const TIEMPO_SIN_LLENAR: float = 60.0
## Al cruzar el puente y quedar a esta distancia de Elián, la bendición llega
## siempre, para que Lino no entre solo a la pelea final.
const DISTANCIA_PUENTE_CRUZADO: float = 900.0
## Título del diálogo de Lázaro dentro de [member dialogo].
const TITULO_DIALOGO: String = "bendicion"
const COLOR_LUZ := Color(1.0, 0.88, 0.5, 1.0)
const DURACION_LUZ: float = 2.4

# Una vez concedida, dura toda la partida (también después de deshilarse).
static var concedida: bool = false
# El tiempo sin llenar un jarrón se sigue contando aunque Lino se deshile.
static var tiempo: float = 0.0

var jugador: Node2D
var dialogo: DialogueResource
var flecha: Node
var elian: Node2D

var _en_dialogo: bool = false


func _ready() -> void:
	if concedida:
		_activar_ayudas()
	if DialogueManager.has_signal("dialogue_started"):
		DialogueManager.dialogue_started.connect(func(_recurso): _en_dialogo = true)
	DialogueManager.dialogue_ended.connect(func(_recurso): _en_dialogo = false)


## Se llama cada vez que se llena un jarrón: la cuenta vuelve a empezar.
func reiniciar_cuenta() -> void:
	tiempo = 0.0


func _process(delta: float) -> void:
	if concedida or not is_instance_valid(jugador):
		return
	tiempo += delta
	if tiempo < TIEMPO_SIN_LLENAR and not _cruzo_el_puente():
		return
	if _en_dialogo or jugador.mode != jugador.Mode.USER_CONTROLLED:
		return
	_conceder()


func _cruzo_el_puente() -> bool:
	return (
		is_instance_valid(elian)
		and elian.global_position.distance_to(jugador.global_position) < DISTANCIA_PUENTE_CRUZADO
	)


func _conceder() -> void:
	concedida = true
	_decir_desde_lejos()
	_envolver_en_luz()
	await get_tree().create_timer(DURACION_LUZ * 0.6).timeout
	_activar_ayudas()


## Lázaro habla con el globo de diálogo normal, pero arriba de la pantalla y
## sin detener la pelea: Lino puede seguir moviéndose y repeliendo.
func _decir_desde_lejos() -> void:
	if not dialogo:
		return
	var globo: Node = DialogueManager.show_dialogue_balloon(dialogo, TITULO_DIALOGO)
	if not is_instance_valid(globo):
		return
	globo.set("will_block_other_input", false)
	# El globo arma sus piezas al entrar en escena: hay que esperar a que esté listo.
	if not globo.is_node_ready():
		await globo.ready
	if is_instance_valid(globo) and globo.get("balloon_container") != null:
		globo.anchor_to_top()


func _activar_ayudas() -> void:
	if is_instance_valid(flecha):
		flecha.activa = true


## Un halo dorado que crece desde Lino y motas de luz que suben.
func _envolver_en_luz() -> void:
	var gradiente := Gradient.new()
	gradiente.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradiente.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var textura := GradientTexture2D.new()
	textura.gradient = gradiente
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(0.5, 0.0)
	textura.width = 256
	textura.height = 256
	var suma := CanvasItemMaterial.new()
	suma.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var luz := Node2D.new()
	luz.z_index = 5
	jugador.add_child(luz)

	var halo := Sprite2D.new()
	halo.texture = textura
	halo.material = suma
	halo.modulate = Color(COLOR_LUZ, 0.0)
	halo.scale = Vector2(0.3, 0.3)
	luz.add_child(halo)

	var motas := CPUParticles2D.new()
	motas.material = suma
	motas.amount = 28
	motas.lifetime = 1.6
	motas.one_shot = true
	motas.explosiveness = 0.35
	motas.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	motas.emission_sphere_radius = 34.0
	motas.direction = Vector2.UP
	motas.spread = 25.0
	motas.gravity = Vector2(0, -40)
	motas.initial_velocity_min = 30.0
	motas.initial_velocity_max = 70.0
	motas.scale_amount_min = 3.0
	motas.scale_amount_max = 6.0
	motas.color = COLOR_LUZ
	luz.add_child(motas)
	motas.emitting = true

	luz.create_tween().tween_property(halo, "scale", Vector2(1.5, 1.5), DURACION_LUZ).set_ease(
		Tween.EASE_OUT
	)
	var brillar := luz.create_tween()
	brillar.tween_property(halo, "modulate:a", 0.85, DURACION_LUZ * 0.3)
	brillar.tween_property(halo, "modulate:a", 0.0, DURACION_LUZ * 0.7)
	brillar.tween_callback(luz.queue_free)
