# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name EfectoFantasma
extends Node
## Hace que Luto no parezca del todo físico: su figura se difumina y vuelve, con
## un parpadeo leve e irregular.
##
## Se añade como hijo de Luto (o de su sprite). Usa self_modulate, así que no
## interfiere con quien cambie su modulate para hacerlo aparecer o desaparecer.
##
## Uso:
##     luto.add_child(EfectoFantasma.new())
##     EfectoFantasma.quitar_de(luto)  # cuando Luto vuelve a ser "real"

const OPACIDAD_BASE: float = 0.55
const OPACIDAD_AL_DESVANECERSE: float = 0.06
const PAUSA_ENTRE_DESVANECIMIENTOS := Vector2(2.0, 4.5)
## Lo que tarda en irse, quedarse casi invisible y volver.
const DURACION_DESVANECIMIENTO: float = 2.6
const DURACION_AL_QUITAR: float = 1.2

var figura: CanvasItem
var tiempo: float = 0.0
var espera: float = 0.0
var desvanecimiento: float = 0.0
var quitando: bool = false


## Deja de parpadear y devuelve a Luto su opacidad completa, poco a poco.
static func quitar_de(nodo: Node) -> void:
	if not is_instance_valid(nodo):
		return
	for hijo in nodo.get_children():
		if hijo is EfectoFantasma:
			hijo.quitar()
		else:
			quitar_de(hijo)


func _ready() -> void:
	figura = _buscar_figura()
	# Un fantasma no tiene cuerpo: Lino lo atraviesa.
	for forma in get_parent().find_children("*", "CollisionShape2D", true, false):
		forma.set_deferred("disabled", true)
	tiempo = randf() * 10.0
	espera = randf_range(PAUSA_ENTRE_DESVANECIMIENTOS.x, PAUSA_ENTRE_DESVANECIMIENTOS.y)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if quitando or not is_instance_valid(figura):
		return
	tiempo += delta
	espera -= delta
	if espera <= 0.0:
		espera = (
			DURACION_DESVANECIMIENTO
			+ randf_range(PAUSA_ENTRE_DESVANECIMIENTOS.x, PAUSA_ENTRE_DESVANECIMIENTOS.y)
		)
		desvanecimiento = 1.0
	desvanecimiento = maxf(desvanecimiento - delta / DURACION_DESVANECIMIENTO, 0.0)

	var opacidad := OPACIDAD_BASE + 0.1 * sin(tiempo * 2.1) + 0.05 * sin(tiempo * 7.3 + 1.0)
	var hueco := smoothstep(0.0, 0.4, desvanecimiento) * smoothstep(1.0, 0.6, desvanecimiento)
	figura.self_modulate.a = lerpf(opacidad, OPACIDAD_AL_DESVANECERSE, hueco)


func quitar() -> void:
	if quitando:
		return
	quitando = true
	if not is_instance_valid(figura):
		queue_free()
		return
	var volver := create_tween()
	volver.tween_property(figura, "self_modulate:a", 1.0, DURACION_AL_QUITAR)
	volver.tween_callback(queue_free)


## El sprite de Luto: el padre si ya es un sprite, o el primero que tenga dentro.
func _buscar_figura() -> CanvasItem:
	var padre := get_parent()
	if padre is AnimatedSprite2D or padre is Sprite2D:
		return padre
	for hijo in padre.find_children("*", "AnimatedSprite2D", true, false):
		return hijo
	return padre as CanvasItem
