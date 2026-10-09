# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name ReaparicionEnHilo
extends Node

## Lino ya se puede mover (o no hubo nada que hacer porque era la primera vez).
signal termino
## Al deshilarse, Lino vuelve al último hilo del recuerdo.
##
## La primera vez que se entra al nivel no hace nada. Cuando el nivel se vuelve
## a cargar (porque Lino se deshiló), reproduce la animación "revive" y, si en
## este nivel ya se recogió algún hilo, lleva a Lino a donde estaba ese hilo.
## Si todavía no recogió ninguno, revive en el inicio del nivel.
##
## Uso, al final del _ready() del script principal del nivel:
##     add_child(ReaparicionEnHilo.new())

const ANIMACION_REVIVIR: StringName = &"revive"
const TIEMPO_MAXIMO: float = 4.0


func _ready() -> void:
	var escena := get_tree().current_scene.scene_file_path
	var es_reaparicion := ElHiloQueNoTejiState.registrar_carga_de_nivel(escena)
	var jugador := get_tree().get_first_node_in_group("player") as Player
	if not es_reaparicion or not jugador:
		queue_free()
		return
	_reaparecer(jugador, ElHiloQueNoTejiState.obtener_ultimo_hilo(escena))


func _reaparecer(jugador: Player, posicion: Variant) -> void:
	jugador.take_control(self)
	jugador.velocity = Vector2.ZERO

	var sprite: AnimatedSprite2D = jugador.get_node("%PlayerSprite")
	var animation_player: AnimationPlayer = jugador.get_node("AnimationPlayer")
	var tiene_animacion := sprite.sprite_frames.has_animation(ANIMACION_REVIVIR)

	# El AnimationPlayer del jugador fuerza "idle" en cada cuadro, así que se
	# pausa mientras dura la animación de revivir.
	if tiene_animacion:
		animation_player.pause()
		animation_player.set_process(false)
		sprite.play(ANIMACION_REVIVIR)

	if posicion != null:
		# Esperamos a que el nivel termine de quitar los hilos ya recogidos,
		# para no aparecer encima de su colisión.
		await get_tree().physics_frame
		await get_tree().physics_frame
		jugador.teleport_to(posicion)

	if tiene_animacion:
		# Esperamos a que termine "revive", pero nunca más de TIEMPO_MAXIMO:
		# si algo cambia la animación antes, Lino no se queda sin poder moverse.
		var limite := Time.get_ticks_msec() + int(TIEMPO_MAXIMO * 1000)
		while (
			is_inside_tree()
			and sprite.is_playing()
			and sprite.animation == ANIMACION_REVIVIR
			and Time.get_ticks_msec() < limite
		):
			await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(jugador):
			return
		animation_player.set_process(true)
		animation_player.play(&"idle")

	jugador.return_control(self)
	termino.emit()
	queue_free()
