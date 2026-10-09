# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node2D
## La antesala: lo que pasa justo antes de entrar a la sala del Archivero.
##
## Es el nivel 3.2 en pequeño: sombras, jarrones y puentes rotos. Cada jarrón
## que se llena repara su puente. Aquí Lino aprende a repeler sin que nadie se
## lo explique. Los golpes lo dejan gris y puede deshilarse, igual que en el 3.2;
## al volver, los jarrones ya llenos siguen llenos y sus puentes, reparados.

## elian_entrance.wav: suena cuando el puente se repara.
const SONIDO_ENTRADA_ELIAN: AudioStream = preload("uid://5m257w00i35m")
## el_hilo_que_no_teji_combat_round_1.dialogue
const DIALOGO: DialogueResource = preload("uid://buwv0q8u3r1i5")
const TITULO_VOZ_LEJANA: String = "voz_lejana"
## El sonido se apaga poco a poco en sus últimos segundos, para que no corte.
const FUNDIDO_SONIDO: float = 2.0

## Cada jarrón y el puente que repara: [capa del puente roto, capa del reparado].
## El roto se ve desde el principio; el reparado no existe hasta que se llena
## su jarrón. Al llenarse el último, las sombras se van.
const PUENTE_DE_CADA_JARRON: Dictionary[String, Array] = {
	"FillingBarrel": ["PuenteRoto2", "PuenteReparado2"],
	"FillingBarrel3": ["PuenteRoto", "PuenteReparado"],
}
## Capas que son suelo: donde no hay ninguna de ellas, es lago y Lino no pasa.
const CAPAS_DE_SUELO: Array[String] = ["SubsueloPasto", "Madera", "Escalera"]
## La capa que cubre todo el lago, para saber dónde hay agua.
const CAPA_DEL_LAGO: String = "TintaLagoFill"
## Capas con choques que deben detener a Lino pero no a los proyectiles.
const CAPAS_SOLO_PARA_LINO: Array[String] = ["TintaLago", "SubsueloTierra"]
## Capa de choque que solo mira Lino (los proyectiles no la tienen en su máscara).
const CHOQUE_SOLO_LINO: int = 512
## La escalera es suelo: se dibuja debajo de Lino, encima del pasto.
const ESCALERA: String = "Escalera"
const PASTO: String = "SubsueloPasto"
## Lo que está sobre el suelo se dibuja por encima del pasto (que tiene z 1).
const Z_SOBRE_EL_SUELO: int = 1
## Los proyectiles van más lentos que en la sala del Archivero.
const VELOCIDAD_PROYECTIL: float = 22.0
const SEGUNDOS_ENTRE_DISPAROS: float = 4.0
## Los proyectiles se dibujan por encima del suelo.
const Z_PROYECTILES: int = 20

## Jarrones llenos en esta partida: siguen llenos si Lino se deshila.
static var jarrones_guardados: Array[String] = []

## Orbes que necesita cada jarrón para llenarse.
@export var orbes_por_jarron: int = 2

var jarrones_llenos: int = 0
var orillas: TileMapLayer
## Los puentes reparados que ya terminaron de tejerse: solo esos se pueden pisar.
var puentes_tejidos: Array[TileMapLayer] = []

@onready var jugador: Player = $OnTheGround/Player
@onready var capas: Node2D = $TileMapLayers
@onready var panel_pensamiento: Control = get_node_or_null("HUD/PanelContainer")


func _ready() -> void:
	add_child(GolpesALino.new(jugador, panel_pensamiento))
	if ElHiloQueNoTejiState.es_partida_nueva_para(scene_file_path):
		jarrones_guardados.clear()
	child_entered_tree.connect(_subir_proyectil)

	var etiquetas: Array[String] = ["Ira"]
	var colores: Dictionary[String, Color] = {"Ira": Color(0.6, 0.6, 0.6)}
	for sombra in get_tree().get_nodes_in_group("throwing_enemy"):
		if is_ancestor_of(sombra):
			sombra.allowed_labels = etiquetas
			sombra.color_per_label = colores
			sombra.projectile_speed = VELOCIDAD_PROYECTIL
			sombra.throwing_period = SEGUNDOS_ENTRE_DISPAROS

	for nombre in PUENTE_DE_CADA_JARRON:
		var jarron := get_node_or_null("OnTheGround/" + nombre) as FillingBarrel
		if jarron:
			jarron.needed_amount = orbes_por_jarron
			jarron.completed.connect(_al_llenar_jarron.bind(nombre))

	var pesadilla := Pesadilla.new()
	pesadilla.grupos = [&"throwing_enemy"]
	pesadilla.intensidad_maxima = 0.35
	add_child(pesadilla)

	for puentes: Array in PUENTE_DE_CADA_JARRON.values():
		var roto := _capa(puentes[0])
		var reparado := _capa(puentes[1])
		if roto:
			roto.show()
			roto.enabled = true
		if reparado:
			reparado.enabled = false

	_ordenar_lo_que_se_dibuja()
	_dejar_pasar_los_proyectiles()
	_restaurar_jarrones_llenos()
	_crear_orillas()

	add_child(DescensoPorLaCuerda.new())
	add_child(ReaparicionEnHilo.new())


func _subir_proyectil(nodo: Node) -> void:
	if nodo is Node2D and nodo.is_in_group("projectiles"):
		nodo.z_index = maxi(nodo.z_index, Z_PROYECTILES)


func _al_llenar_jarron(nombre: String) -> void:
	jarrones_llenos += 1
	jarrones_guardados.append(nombre)
	var puentes: Array = PUENTE_DE_CADA_JARRON[nombre]
	_reparar_el_puente(_capa(puentes[0]), _capa(puentes[1]))
	if jarrones_llenos >= PUENTE_DE_CADA_JARRON.size():
		_despejar_la_antesala()


## El puente roto se deshace y el reparado se teje. Lino puede cruzarlo solo
## cuando termina de tejerse.
func _reparar_el_puente(roto: TileMapLayer, reparado: TileMapLayer) -> void:
	if roto:
		Retejido.desaparecer(roto, false, Retejido.DURACION_BREVE)
	if not reparado:
		return
	await Retejido.tejer_por_franjas(reparado)
	_quitar_bordes_bajo(reparado)
	puentes_tejidos.append(reparado)
	_crear_orillas()


## Al volver tras deshilarse: los jarrones que ya se habían llenado no están y
## sus puentes ya están reparados, sin animación.
func _restaurar_jarrones_llenos() -> void:
	for nombre in jarrones_guardados:
		var jarron := get_node_or_null("OnTheGround/" + nombre)
		if jarron:
			jarron.queue_free()
		jarrones_llenos += 1
		var puentes: Array = PUENTE_DE_CADA_JARRON[nombre]
		var roto := _capa(puentes[0])
		var reparado := _capa(puentes[1])
		if roto:
			roto.enabled = false
		if reparado:
			reparado.enabled = true
			_quitar_bordes_bajo(reparado)
			puentes_tejidos.append(reparado)
	if jarrones_llenos >= PUENTE_DE_CADA_JARRON.size():
		for sombra in get_tree().get_nodes_in_group("throwing_enemy"):
			if is_ancestor_of(sombra):
				sombra.queue_free()


## Con todos los jarrones llenos las sombras se van, mientras alguien habla
## desde lejos.
func _despejar_la_antesala() -> void:
	for sombra in get_tree().get_nodes_in_group("throwing_enemy"):
		if is_ancestor_of(sombra):
			sombra.queue_free()
	get_tree().call_group("projectiles", "remove")
	_sonar_entrada_de_elian()
	_decir_desde_lejos()


func _capa(nombre: String) -> TileMapLayer:
	return capas.get_node_or_null(nombre) as TileMapLayer


## La escalera y los puentes son suelo: van debajo de Lino (la escalera tenía
## z 5 y lo tapaba) pero encima del pasto. Los jarrones, sombras y demás van por encima del pasto.
func _ordenar_lo_que_se_dibuja() -> void:
	var pasto := _capa(PASTO)
	if pasto:
		var encima: Array[String] = [ESCALERA]
		for puentes: Array in PUENTE_DE_CADA_JARRON.values():
			encima.append_array(puentes)
		for nombre in encima:
			var capa := _capa(nombre)
			if capa:
				capa.z_index = pasto.z_index
				capas.move_child(capa, pasto.get_index())
	for cosa in $OnTheGround.get_children():
		if cosa is CanvasItem:
			cosa.z_index = maxi(cosa.z_index, Z_SOBRE_EL_SUELO)


## Los bordes del lago detienen a Lino, pero los proyectiles los cruzan: si no,
## se deshacen antes de llegar a los jarrones. Solo cambia en este nivel.
func _dejar_pasar_los_proyectiles() -> void:
	for nombre in CAPAS_SOLO_PARA_LINO:
		var capa := _capa(nombre)
		if not capa or not capa.tile_set:
			continue
		var tiles := capa.tile_set.duplicate() as TileSet
		for capa_fisica in tiles.get_physics_layers_count():
			tiles.set_physics_layer_collision_layer(capa_fisica, CHOQUE_SOLO_LINO)
		capa.tile_set = tiles


## Quita los bordes de tierra que quedan bajo un puente reparado, para que no
## cierren el paso al bajar del puente.
func _quitar_bordes_bajo(puente: TileMapLayer) -> void:
	for nombre in CAPAS_SOLO_PARA_LINO:
		var capa := _capa(nombre)
		if not capa:
			continue
		for celda in capa.get_used_cells():
			var lugar := capa.to_global(capa.map_to_local(celda))
			if puente.get_cell_source_id(puente.local_to_map(puente.to_local(lugar))) != -1:
				capa.erase_cell(celda)


## Una capa invisible que cubre el lago donde no hay suelo. Detiene a Lino (no
## puede caminar sobre el lago ni sobre un puente roto) y deja pasar los
## proyectiles. Se rehace cada vez que se repara un puente.
func _crear_orillas() -> void:
	var lago := _capa(CAPA_DEL_LAGO)
	if not lago:
		return
	if not orillas:
		orillas = TileMapLayer.new()
		orillas.name = "OrillasDelLago"
		orillas.visible = false
		orillas.position = lago.position
		orillas.tile_set = _tiles_de_orilla(lago.tile_set.tile_size)
		capas.add_child(orillas)
	orillas.clear()
	var suelos: Array[TileMapLayer] = []
	for nombre in CAPAS_DE_SUELO:
		if _capa(nombre):
			suelos.append(_capa(nombre))
	suelos.append_array(puentes_tejidos)
	for celda in lago.get_used_cells():
		var lugar := lago.to_global(lago.map_to_local(celda))
		if not _hay_suelo(suelos, lugar):
			orillas.set_cell(celda, 0, Vector2i.ZERO)


func _hay_suelo(suelos: Array[TileMapLayer], lugar: Vector2) -> bool:
	for suelo in suelos:
		if suelo.get_cell_source_id(suelo.local_to_map(suelo.to_local(lugar))) != -1:
			return true
	return false


## Un solo tile cuadrado, sin dibujo, que choca solo con Lino.
func _tiles_de_orilla(tamano: Vector2i) -> TileSet:
	var tiles := TileSet.new()
	tiles.tile_size = tamano
	tiles.add_physics_layer()
	tiles.set_physics_layer_collision_layer(0, CHOQUE_SOLO_LINO)
	tiles.set_physics_layer_collision_mask(0, 0)
	var imagen := Image.create_empty(tamano.x, tamano.y, false, Image.FORMAT_RGBA8)
	var fuente := TileSetAtlasSource.new()
	fuente.texture = ImageTexture.create_from_image(imagen)
	fuente.texture_region_size = tamano
	tiles.add_source(fuente, 0)
	fuente.create_tile(Vector2i.ZERO)
	var medio := Vector2(tamano) / 2.0
	var datos := fuente.get_tile_data(Vector2i.ZERO, 0)
	datos.add_collision_polygon(0)
	datos.set_collision_polygon_points(
		0,
		0,
		PackedVector2Array([-medio, Vector2(medio.x, -medio.y), medio, Vector2(-medio.x, medio.y)])
	)
	return tiles


func _sonar_entrada_de_elian() -> void:
	var sonido := AudioStreamPlayer.new()
	sonido.stream = SONIDO_ENTRADA_ELIAN
	sonido.bus = &"SFX"
	add_child(sonido)
	sonido.play()
	var apagar := sonido.create_tween()
	apagar.tween_interval(maxf(SONIDO_ENTRADA_ELIAN.get_length() - FUNDIDO_SONIDO, 0.0))
	# Se baja el volumen real (no los decibelios) para que la bajada se oiga pareja.
	apagar.tween_method(
		func(volumen: float) -> void: sonido.volume_db = linear_to_db(volumen),
		1.0,
		0.0,
		FUNDIDO_SONIDO
	)
	apagar.tween_callback(sonido.queue_free)


## La voz usa el globo de diálogo normal, pero arriba de la pantalla y sin
## detener a Lino.
func _decir_desde_lejos() -> void:
	var globo: Node = DialogueManager.show_dialogue_balloon(DIALOGO, TITULO_VOZ_LEJANA)
	if not is_instance_valid(globo):
		return
	globo.set("will_block_other_input", false)
	# El globo arma sus piezas al entrar en escena: hay que esperar a que esté listo.
	if not globo.is_node_ready():
		await globo.ready
	if is_instance_valid(globo) and globo.get("balloon_container") != null:
		globo.anchor_to_top()
