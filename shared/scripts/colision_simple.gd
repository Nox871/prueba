# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name ColisionSimple
extends RefCounted
## Le da cuerpo a un personaje que solo es un sprite (como Lázaro), para que
## Lino no pueda atravesarlo.

const CAPA_PAREDES: int = 16


## [param pies] es dónde quedan los pies respecto del centro del sprite.
static func poner(nodo: Node2D, pies: Vector2 = Vector2(0, 22), radio: float = 14.0) -> void:
	if not is_instance_valid(nodo) or nodo.has_node("CuerpoSolido"):
		return
	var forma := CollisionShape2D.new()
	var circulo := CircleShape2D.new()
	circulo.radius = radio
	forma.shape = circulo
	var cuerpo := StaticBody2D.new()
	cuerpo.name = "CuerpoSolido"
	cuerpo.collision_layer = CAPA_PAREDES
	cuerpo.collision_mask = 0
	cuerpo.position = pies
	cuerpo.add_child(forma)
	nodo.add_child(cuerpo)
