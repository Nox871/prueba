# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Label
## Contador de fragmentos de hilo del nivel. El icono del fragmento es el nodo hijo
## "IconoFragmento" de la escena: se mueve desde el editor.

# Estáticas para que sobrevivan cuando el nivel se recarga al morir.
static var base_hilos_nivel: int = -1
static var ultima_escena_cargada: String = ""


func _ready() -> void:
	var escena_actual = get_tree().current_scene.scene_file_path

	# Escena distinta a la última: es un nivel nuevo, no una recarga.
	if escena_actual != ultima_escena_cargada:
		ultima_escena_cargada = escena_actual
		base_hilos_nivel = ElHiloQueNoTejiState.hilos_recogidos


func _process(_delta: float) -> void:
	var hilos_actuales = ElHiloQueNoTejiState.hilos_recogidos

	var fragmentos_en_este_nivel = hilos_actuales - base_hilos_nivel

	if fragmentos_en_este_nivel <= 0:
		text = "0/3"
	elif fragmentos_en_este_nivel >= 3:
		text = "3/3"
	else:
		text = str(fragmentos_en_este_nivel) + "/3"
