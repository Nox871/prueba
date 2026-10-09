# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node

## La onda pequeña que sale de cada hilo al recogerlo.
## Es lenta y suave, como las del final del 3.2: sale mientras Lino habla.
const ONDA_HILO_VELOCIDAD: float = 140.0
const ONDA_HILO_ANCHO: float = 260.0
const ONDA_HILO_ALCANCE: float = 900.0
const ONDA_HILO_BRILLO: float = 0.5
## Cuánto color propio de las cosas deja ver el anillo (1 = color pleno).
const ONDA_HILO_COLOR: float = 0.85
## Cuánto se tiñe el anillo del color del hilo.
const ONDA_HILO_TINTE: float = 0.7
## Brillo del anillo en las ondas grandes del final (lo usa efectos_final.gd).
const ONDA_BRILLO_NORMAL: float = 0.6
## Brillo del mundo (1 = sin oscurecer).
const BRILLO_DEL_MUNDO: float = 0.6
## Lino no se oscurece, para que resalte en el mapa oscuro.
const BRILLO_DE_LINO: float = 1.0

@export var material_mundo: ShaderMaterial
@export var material_jugador: ShaderMaterial

## Límite de la saturación del mundo (0-1). Un nivel puede bajarlo para devolver
## el color a su manera (por ejemplo, con las ondas del final del 3.2).
var tope_saturacion_mundo: float = 1.0


func _ready() -> void:
	if material_mundo:
		# El material se comparte entre niveles: las ondas empiezan apagadas.
		_apagar_onda_de_hilo()
		_aplicar_material_al_mundo(get_tree().current_scene)

	var lino := get_tree().get_first_node_in_group("player")
	if lino:
		lino.add_child.call_deferred(BrilloDelCollar.new())


## Un anillo del color del hilo sale de donde estaba y cruza el mundo cercano,
## despacio: así se ve que son los hilos los que devuelven el color.
func onda_de_hilo(origen: Vector2, color: Color = Color.WHITE) -> void:
	if not material_mundo or float(material_mundo.get_shader_parameter("onda_tiempo")) >= 0.0:
		return
	material_mundo.set_shader_parameter("onda_origen", origen)
	material_mundo.set_shader_parameter("onda_velocidad", ONDA_HILO_VELOCIDAD)
	material_mundo.set_shader_parameter("onda_cantidad", 1)
	material_mundo.set_shader_parameter("onda_ancho", ONDA_HILO_ANCHO)
	material_mundo.set_shader_parameter("onda_brillo_cresta", ONDA_HILO_BRILLO)
	material_mundo.set_shader_parameter("onda_alcance", ONDA_HILO_ALCANCE)
	material_mundo.set_shader_parameter("onda_color_cresta", ONDA_HILO_COLOR)
	material_mundo.set_shader_parameter("onda_tinte", Color(color.r, color.g, color.b))
	material_mundo.set_shader_parameter("onda_tinte_fuerza", ONDA_HILO_TINTE)
	material_mundo.set_shader_parameter("onda_solo_cresta", true)

	var duracion := (ONDA_HILO_ALCANCE + ONDA_HILO_ANCHO) / ONDA_HILO_VELOCIDAD
	# Sigue aunque el juego esté en pausa por el diálogo del hilo.
	var onda := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	onda.tween_property(material_mundo, "shader_parameter/onda_tiempo", duracion, duracion).from(
		0.0
	)
	onda.tween_callback(_apagar_onda_de_hilo)


## Deja el material como lo esperan las ondas grandes del final del 3.2.
func _apagar_onda_de_hilo() -> void:
	material_mundo.set_shader_parameter("onda_tiempo", -1.0)
	material_mundo.set_shader_parameter("onda_solo_cresta", false)
	material_mundo.set_shader_parameter("onda_alcance", 0.0)
	material_mundo.set_shader_parameter("onda_tinte_fuerza", 0.0)
	material_mundo.set_shader_parameter("onda_color_cresta", 1.0)
	material_mundo.set_shader_parameter("onda_brillo_cresta", ONDA_BRILLO_NORMAL)


## Pone el filtro del mundo a todo lo que se dibuja, menos a Lino y a lo que
## está en el grupo "ignorar_shader" (como el vacío).
func _aplicar_material_al_mundo(nodo: Node) -> void:
	if nodo.is_in_group("player") or nodo.is_in_group("ignorar_shader"):
		return
	if nodo is TileMapLayer or nodo is Sprite2D or nodo is AnimatedSprite2D:
		nodo.material = material_mundo
	for hijo in nodo.get_children():
		_aplicar_material_al_mundo(hijo)


func _process(_delta: float) -> void:
	if material_mundo:
		var saturacion := minf(ElHiloQueNoTejiState.world_saturation / 100.0, tope_saturacion_mundo)
		material_mundo.set_shader_parameter("saturation", saturacion)
		material_mundo.set_shader_parameter("darkness_factor", BRILLO_DEL_MUNDO)

	if material_jugador:
		var saturacion_lino := ElHiloQueNoTejiState.player_saturation / 100.0
		material_jugador.set_shader_parameter("saturation", saturacion_lino)
		material_jugador.set_shader_parameter("darkness_factor", BRILLO_DE_LINO)
