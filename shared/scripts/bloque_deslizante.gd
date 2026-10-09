# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Area2D
## Bloque que se desliza sin parar de un lado a otro, como una puerta. Se pone
## delante de un jarrón: los proyectiles que lo tocan se deshacen, así que hay
## que elegir el momento para empujarlos. A Lino no lo detiene.
##
## Se ve como un minivacío: el vacío que persigue a Lino en el nivel 2, pero
## pequeño. Solo se traga los proyectiles: no rompe nada, no oscurece la
## pantalla ni mata.

## void_particles.tscn: las nubes de polvo oscuro del vacío que persigue.
const PARTICULAS_VACIO: PackedScene = preload("uid://s2ohp10ssq7l")
## particles_canvasgroup_outline.gdshader: el borde blanco de esas nubes.
const BORDE_VACIO: Shader = preload("uid://dvyec12fgsuta")
## El vacío grande suelta sus nubes en un radio de 120; el mini, en este.
const RADIO_MINIVACIO: float = 14.0
const ESCALA_NUBES_MINIVACIO: float = 0.45

## Hacia dónde y cuánto se mueve desde donde está colocado en la escena.
@export var recorrido: Vector2 = Vector2(0, 160)
## Cuánto tarda en ir de un extremo al otro.
@export_range(0.2, 10.0, 0.1, "suffix:s") var segundos_por_recorrido: float = 2.0
## Cuánto se queda quieto en cada extremo.
@export_range(0.0, 5.0, 0.1, "suffix:s") var pausa_en_extremos: float = 0.4
## Para que varios bloques no vayan al mismo compás.
@export_range(0.0, 10.0, 0.1, "suffix:s") var espera_inicial: float = 0.0

## La imagen de la escena solo sirve para ubicar el bloque en el editor.
@onready var _dibujo: Sprite2D = $Sprite2D
@onready var _choque: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_al_tocar)
	var origen := position
	_crear_minivacio()
	if espera_inicial > 0.0:
		await get_tree().create_timer(espera_inicial).timeout
	var vaiven := create_tween().set_loops()
	(
		vaiven
		. tween_property(self, "position", origen + recorrido, segundos_por_recorrido)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	vaiven.tween_interval(pausa_en_extremos)
	(
		vaiven
		. tween_property(self, "position", origen, segundos_por_recorrido)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	vaiven.tween_interval(pausa_en_extremos)


## Como el vacío del nivel 2: nubes de polvo oscuro con borde blanco, que
## salen todo el tiempo, en pequeño.
func _crear_minivacio() -> void:
	_dibujo.hide()
	var grupo := CanvasGroup.new()
	var borde := ShaderMaterial.new()
	borde.shader = BORDE_VACIO
	borde.set_shader_parameter("outline_color", Color.WHITE)
	borde.set_shader_parameter("thickness", 2.0)
	grupo.material = borde
	add_child(grupo)
	var nubes := PARTICULAS_VACIO.instantiate() as GPUParticles2D
	var proceso := nubes.process_material.duplicate() as ParticleProcessMaterial
	proceso.emission_sphere_radius = RADIO_MINIVACIO
	proceso.radial_velocity_min = 4.0
	proceso.radial_velocity_max = 12.0
	proceso.scale_min *= ESCALA_NUBES_MINIVACIO
	proceso.scale_max *= ESCALA_NUBES_MINIVACIO
	nubes.process_material = proceso
	nubes.one_shot = false
	# Las nubes se mueven con el bloque: no deja estela y ocupa un cuadro.
	nubes.local_coords = true
	nubes.explosiveness = 0.0
	nubes.amount = 40
	nubes.emitting = true
	grupo.add_child(nubes)
	var forma := CircleShape2D.new()
	forma.radius = RADIO_MINIVACIO + 10.0
	_choque.shape = forma


func _al_tocar(cuerpo: Node2D) -> void:
	if cuerpo.is_in_group("projectiles") and cuerpo.has_method("explode"):
		cuerpo.explode.call_deferred()
