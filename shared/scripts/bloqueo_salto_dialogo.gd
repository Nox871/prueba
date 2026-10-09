# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name BloqueoSaltoDialogo
extends Node
## Mientras este nodo esté en la escena, el jugador no puede adelantar ni
## saltar el diálogo (ni con teclado, ni con mando, ni con clic).
##
## Pensado para diálogos que avanzan solos con [next=...], donde la idea es
## que se lean con calma. No usarlo en diálogos que esperan que el jugador
## pulse para continuar, porque se quedarían detenidos.
##
## Uso:
##     var bloqueo := BloqueoSaltoDialogo.new()
##     add_child(bloqueo)
##     # ... mostrar el diálogo y esperar a que termine ...
##     bloqueo.queue_free()
##
## Si el diálogo se muestra con el juego en pausa, usar
## [code]BloqueoSaltoDialogo.new(true)[/code].

const ACCIONES_BLOQUEADAS: Array[StringName] = [
	&"dialogue_next",
	&"dialogue_skip",
	&"ui_accept",
]


func _init(funciona_en_pausa: bool = false) -> void:
	if funciona_en_pausa:
		process_mode = Node.PROCESS_MODE_ALWAYS


# _input se procesa antes que la interfaz, así el globo de diálogo
# nunca llega a recibir estas pulsaciones.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		return
	for accion in ACCIONES_BLOQUEADAS:
		if InputMap.has_action(accion) and event.is_action(accion):
			get_viewport().set_input_as_handled()
			return
