# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name Pesadilla
extends CanvasLayer
## Bordes oscuros que se cierran sobre la pantalla cuando algo amenaza a Lino.
##
## Por defecto mide la distancia de Lino a las sombras (grupo "guard_enemy") y a
## los nodos de [member amenazas] (por ejemplo, el vacío). Con
## [member intensidad_fija] en 0 o más deja de medir y usa ese valor: así la
## controla una cinemática.
##
## Uso, en el _ready() del script del nivel:
##     var pesadilla := Pesadilla.new()
##     pesadilla.amenazas = [vacio]
##     add_child(pesadilla)

## pesadilla.gdshader
const SHADER: Shader = preload("../shaders/pesadilla.gdshader")
const GRUPO_SOMBRAS: StringName = &"guard_enemy"
## Estados de una sombra en los que ya tiene a Lino en la mira: lo está
## detectando (lo alumbra) o ya lo descubrió.
const ESTADOS_EN_LA_MIRA: Array[int] = [Guard.State.DETECTING, Guard.State.ALERTED]

## Grupos de nodos que dan miedo. En los niveles de combate son las sombras que
## lanzan proyectiles ("throwing_enemy").
var grupos: Array[StringName] = [GRUPO_SOMBRAS]
## Otros nodos que también dan miedo, además de las sombras.
var amenazas: Array[Node2D] = []
## Nodos del grupo de las sombras que no asustan (Luto, en el nivel 1).
var inofensivos: Array[Node] = []
## A esta distancia la pantalla empieza a oscurecerse.
var distancia_inicio: float = 520.0
## A esta distancia (o menos) la oscuridad es la máxima.
var distancia_maxima: float = 170.0
## Tope de la oscuridad (0 a 1) cuando la amenaza solo está cerca.
var intensidad_maxima: float = 0.8
## Oscuridad cuando una sombra ya tiene a Lino en la mira.
var intensidad_en_la_mira: float = 1.0
## En 0 o más, se usa este valor y no se miden distancias.
var intensidad_fija: float = -1.0
## Qué tan rápido entra y sale la oscuridad, en unidades por segundo.
var velocidad_entrada: float = 1.8
var velocidad_salida: float = 0.6
## Con el juego en pausa (por ejemplo, mientras una fogata muestra la secuencia
## del puzzle) la oscuridad se retira así de rápido, para ver con claridad.
var velocidad_salida_en_pausa: float = 3.0

var intensidad: float = 0.0
var material: ShaderMaterial


func _ready() -> void:
	# Sigue funcionando en pausa, para poder retirarse.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 1
	material = ShaderMaterial.new()
	material.shader = SHADER
	var velo := ColorRect.new()
	velo.material = material
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(velo)
	_ir_debajo_de_la_interfaz.call_deferred()


## Las capas de interfaz del juego (las teclas en pantalla, el HUD) están en la
## misma capa de dibujo. Para quedar por debajo de todas, la pesadilla se cuelga
## al principio de la raíz, y se borra sola cuando el nivel termina.
func _ir_debajo_de_la_interfaz() -> void:
	var nivel := get_parent()
	var raiz := get_tree().root
	if not nivel or nivel == raiz:
		return
	nivel.tree_exiting.connect(queue_free)
	reparent(raiz)
	raiz.move_child(self, 0)


func _process(delta: float) -> void:
	var objetivo := intensidad_fija if intensidad_fija >= 0.0 else _medir_amenaza()
	var velocidad := velocidad_entrada if objetivo > intensidad else velocidad_salida
	if get_tree().paused:
		objetivo = 0.0
		velocidad = velocidad_salida_en_pausa
	intensidad = move_toward(intensidad, objetivo, velocidad * delta)
	material.set_shader_parameter("intensidad", intensidad)


func _medir_amenaza() -> float:
	var lino := get_tree().get_first_node_in_group("player") as Node2D
	if not lino:
		return 0.0
	var mas_cerca := INF
	for grupo in grupos:
		for sombra in get_tree().get_nodes_in_group(grupo):
			if not (sombra is Node2D) or not sombra.is_visible_in_tree() or sombra in inofensivos:
				continue
			if sombra.process_mode == Node.PROCESS_MODE_DISABLED:
				continue
			if sombra is Guard and (sombra as Guard).state in ESTADOS_EN_LA_MIRA:
				return intensidad_en_la_mira
			mas_cerca = minf(mas_cerca, lino.global_position.distance_to(sombra.global_position))
	for amenaza in amenazas:
		if is_instance_valid(amenaza):
			mas_cerca = minf(mas_cerca, lino.global_position.distance_to(amenaza.global_position))
	var cercania := 1.0 - smoothstep(distancia_maxima, distancia_inicio, mas_cerca)
	return cercania * intensidad_maxima
