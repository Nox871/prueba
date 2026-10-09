# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name BrilloDelCollar
extends Node2D
## El collar que Lino lleva en la mano brilla cuando hay un hilo cerca, más
## fuerte cuanto más cerca está.
##
## Se añade como hijo del jugador (lo hace SaturacionManager en cada nivel).

## Dónde queda la mano con el collar respecto de los pies de Lino, mirando a la
## derecha. Al mirar a la izquierda se refleja.
const POSICION_DE_LA_MANO := Vector2(21, 4)
## A esta distancia de un hilo el collar empieza a brillar.
const DISTANCIA_INICIO: float = 460.0
## A esta distancia (o menos) brilla al máximo.
const DISTANCIA_MAXIMA: float = 110.0
const COLOR := Color(1.0, 0.92, 0.6)
const TAMANO: float = 0.34
const SEGUNDOS_ENTRE_BUSQUEDAS: float = 0.5

var halo: Sprite2D
var hilos: Array[Node2D] = []
var proxima_busqueda: float = 0.0
var tiempo: float = 0.0
var fuerza: float = 0.0


func _ready() -> void:
	var degradado := Gradient.new()
	degradado.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	degradado.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(0.5, 0.0)
	textura.width = 96
	textura.height = 96
	var suma := CanvasItemMaterial.new()
	suma.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	halo = Sprite2D.new()
	halo.texture = textura
	halo.material = suma
	halo.modulate = Color(COLOR, 0.0)
	halo.scale = Vector2.ONE * TAMANO
	halo.z_index = 1
	add_child(halo)


func _process(delta: float) -> void:
	tiempo += delta
	proxima_busqueda -= delta
	if proxima_busqueda <= 0.0:
		proxima_busqueda = SEGUNDOS_ENTRE_BUSQUEDAS
		_buscar_hilos()

	var mas_cerca := INF
	for hilo in hilos:
		if is_instance_valid(hilo) and hilo.is_visible_in_tree() and hilo.get("revealed"):
			mas_cerca = minf(mas_cerca, global_position.distance_to(hilo.global_position))
	var objetivo := 1.0 - smoothstep(DISTANCIA_MAXIMA, DISTANCIA_INICIO, mas_cerca)
	fuerza = move_toward(fuerza, objetivo, delta * 1.5)

	var sprite := get_parent().get_node_or_null("%PlayerSprite") as AnimatedSprite2D
	var lado := -1.0 if sprite and sprite.flip_h else 1.0
	halo.position = Vector2(POSICION_DE_LA_MANO.x * lado, POSICION_DE_LA_MANO.y)
	var latido := 0.75 + 0.25 * sin(tiempo * lerpf(3.0, 9.0, fuerza))
	halo.modulate.a = fuerza * latido * 0.9
	halo.scale = Vector2.ONE * TAMANO * (0.85 + 0.3 * fuerza * latido)


func _buscar_hilos() -> void:
	hilos.clear()
	var escena := get_tree().current_scene
	if not escena:
		return
	for nodo in escena.find_children("*", "", true, false):
		if nodo is StealthCollectible:
			hilos.append(nodo)
