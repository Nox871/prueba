# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends TileMapLayer

@export var tiempo_caida: float = 0.7
@export var jugador: Node2D
@export var ajuste_pies_y: float = 16.0

## Segundos de gracia después de una cinemática, antes de volver a revisar si Lino cae.
@export var tiempo_respiro_post_cinematica: float = 1.25
## Capas hermanas que son suelo firme. Si debajo de un tablón que ya cayó hay
## suelo de alguna de estas capas, Lino puede pisarlo sin caer al vacío.
@export var nombres_capas_suelo: PackedStringArray = [
	"Suelo", "Grass", "GrassVerde", "Madera", "SubMadera", "GrassBossGris", "GrassBossBlanco"
]

var celdas_originales: Array[Vector2i] = []
var celdas_cayendo: Dictionary = {}
var lino_cayendo: bool = false

var estaba_en_cinematica: bool = false
var tiempo_respiro_restante: float = 0.0
var capas_suelo: Array[TileMapLayer] = []


func _ready() -> void:
	celdas_originales = get_used_cells()
	for nombre in nombres_capas_suelo:
		var capa := get_parent().get_node_or_null(NodePath(nombre)) as TileMapLayer
		if capa and capa != self:
			capas_suelo.append(capa)


func _physics_process(delta: float) -> void:
	if not visible or not jugador or lino_cayendo:
		return

	var en_cinematica = jugador.mode == jugador.Mode.SYSTEM_CONTROLLED

	if en_cinematica:
		estaba_en_cinematica = true
		return

	if estaba_en_cinematica:
		estaba_en_cinematica = false
		tiempo_respiro_restante = maxf(tiempo_respiro_restante, tiempo_respiro_post_cinematica)

	if tiempo_respiro_restante > 0.0:
		tiempo_respiro_restante -= delta
		return

	var posicion_pies = jugador.global_position + Vector2(0, ajuste_pies_y)
	var pos_local = to_local(posicion_pies)
	var posicion_celda = local_to_map(pos_local)

	if posicion_celda in celdas_originales:
		if get_cell_source_id(posicion_celda) != -1:
			if not celdas_cayendo.has(posicion_celda):
				celdas_cayendo[posicion_celda] = tiempo_caida
		elif not _hay_suelo_en(posicion_pies):
			_matar_a_lino()

	var celdas_a_borrar = []
	for celda in celdas_cayendo.keys():
		celdas_cayendo[celda] -= delta
		if celdas_cayendo[celda] <= 0:
			set_cell(celda, -1)
			celdas_a_borrar.append(celda)

	for celda in celdas_a_borrar:
		celdas_cayendo.erase(celda)


func _hay_suelo_en(posicion_global: Vector2) -> bool:
	for capa in capas_suelo:
		var celda := capa.local_to_map(capa.to_local(posicion_global))
		if capa.get_cell_source_id(celda) != -1:
			return true
	return false


func _matar_a_lino() -> void:
	lino_cayendo = true

	if jugador.has_method("take_control"):
		jugador.take_control(self)

	jugador.velocity = Vector2.ZERO
	# Mientras cae, nada más puede atraparlo: si no, moriría varias veces.
	if jugador is CollisionObject2D:
		jugador.set_deferred("collision_layer", 0)

	var animacion_caida = create_tween()
	animacion_caida.tween_property(jugador, "scale", Vector2.ZERO, 0.9).set_trans(Tween.TRANS_SINE)
	animacion_caida.tween_property(jugador, "rotation", PI * 4, 0.9)

	await animacion_caida.finished

	var estado_jugador: PlayerState = GameState.player
	if estado_jugador:
		estado_jugador.decrement_lives()

	if not estado_jugador or estado_jugador.lives > 0:
		var ruta_actual = get_tree().current_scene.scene_file_path
		SceneSwitcher.change_to_file_with_transition(ruta_actual)
	else:
		if jugador.has_method("_handle_game_over"):
			jugador._handle_game_over()
