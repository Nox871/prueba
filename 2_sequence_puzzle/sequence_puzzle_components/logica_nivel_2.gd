# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node2D

const CANTIDAD_PUENTES: int = 3

# Luto se deja oír desde la isla siguiente. Cuando Lino se acerca, ya no
# está: se fue a la próxima. El último punto es donde espera al final.
const ISLAS_LUTO: Array[Vector2] = [
	Vector2(97, 4832),  # Isla del primer hilo (abajo a la izquierda)
	Vector2(97, 2720),  # Isla del segundo hilo (arriba a la izquierda)
	Vector2(3041, 2720),  # Isla del tercer hilo (arriba a la derecha)
]
## Si Lino llega a esta distancia de Luto, Luto se va a la isla siguiente.
const DISTANCIA_PARA_IRSE: float = 750.0
const PAUSA_ENTRE_LADRIDOS := Vector2(60.0, 95.0)
const LADRIDO_TRAS_CAMBIAR_DE_ISLA := Vector2(4.0, 7.0)
const DURACION_DESVANECER: float = 0.6

# Mismo color para todos los haces de luz de las sombras: azul pálido, se ve sobre el
# suelo claro sin resaltar más que lo demás.
const COLOR_HAZ_DE_LUZ := Color(0.72, 0.8, 1.0)
const RESPIRO_TRAS_TEJER: float = 1.5
const COLOR_HALO_FOGATA := Color(1.0, 0.8, 0.45)
## Segundos que aguanta cada tablón de los puentes desde que Lino lo pisa.
const TIEMPO_CAIDA_DE_LOS_PUENTES: float = 1.1
const CinematicaVacio = preload("cinematica_llegada_del_vacio.gd")
const IslaDevorada = preload("cinematica_isla_devorada.gd")
## Las nubes de polvo del vacío, un 20 % más grandes que las de Threadbare.
const NUBES_DEL_VACIO: PackedScene = preload("vacio_particulas_grandes.tscn")
const ROCAS_APAGADAS = preload("../../shared/shaders/el_hilo_que_no_teji_rocas_apagadas.gdshader")

## Puentes ya reparados. Son estáticos para que sigan reparados cuando
## el nivel se recarga después de que Lino cae al vacío.
static var puentes_listos: Array[bool] = [false, false, false]
## Último orden de cada puzzle, para que al reaparecer no se repita.
static var ultimo_orden: Dictionary = {}
## En qué isla está Luto (índice de ISLAS_LUTO; al pasarse, está en su lugar final).
static var isla_de_luto: int = 0

## Al recargar la escena, los hilos que siguen en el nivel emiten
## tree_exited; así no se cuentan como recogidos.
var nivel_apagandose: bool = false
var luto_cambiando_de_isla: bool = false
var proximo_ladrido: float = 0.0
var posicion_final_luto: Vector2

@onready var luto: AnimatedSprite2D = $OnTheGround/Luto
@onready var jugador: Node2D = $OnTheGround/Player


func _ready() -> void:
	if ElHiloQueNoTejiState.es_partida_nueva_para("sequence_puzzle"):
		puentes_listos = [false, false, false]
		isla_de_luto = 0
		CinematicaVacio.vista = false
		IslaDevorada.hechas = [false, false]
		ultimo_orden.clear()
	else:
		# Lino reaparece en el último hilo que recogió. Una isla sigue devorada
		# solo si ya había recogido el hilo de la isla siguiente; si no, vuelve
		# a estar entera y el vacío la devorará otra vez cuando Lino cruce.
		for indice in IslaDevorada.hechas.size():
			IslaDevorada.hechas[indice] = (
				IslaDevorada.hechas[indice] and puentes_listos[indice + 1]
			)

	GameState.player.set_ability(Enums.PlayerAbilities.ABILITY_B, false)
	nivel_apagandose = false
	tree_exiting.connect(_activar_escudo)

	for numero in range(1, CANTIDAD_PUENTES + 1):
		var puente = get_node_or_null("TileMapLayers/Puente%d" % numero)
		var puente_roto = get_node_or_null("TileMapLayers/PuenteRoto%d" % numero)
		if CinematicaVacio.vista:
			if puente:
				puente.hide()
		else:
			if puente:
				puente.show()
			if puente_roto:
				puente_roto.enabled = false
		if puentes_listos[numero - 1]:
			_restaurar_puente_y_borrar_hilo(numero)

	for capa in $TileMapLayers.get_children():
		if "tiempo_caida" in capa:
			capa.tiempo_caida = TIEMPO_CAIDA_DE_LOS_PUENTES

	_barajar_puzzles()
	_marcar_fogatas()
	add_child(IslaDevorada.new())
	_pintar_haces_de_luz()
	_apagar_rocas()
	posicion_final_luto = luto.global_position
	luto.add_child(EfectoFantasma.new())
	var pesadilla := Pesadilla.new()
	var vacio := get_node_or_null("OnTheGround/VoidSpreadingEnemy") as Node2D
	if vacio:
		pesadilla.amenazas = [vacio]
		vacio.set("void_particles", NUBES_DEL_VACIO)
	add_child(pesadilla)
	_poner_a_luto_en_su_isla()
	proximo_ladrido = randf_range(3.0, 5.0)

	var reaparicion := ReaparicionEnHilo.new()
	reaparicion.termino.connect(_ladrar_al_reaparecer)
	add_child(reaparicion)
	if not reaparicion.is_queued_for_deletion():
		# Lino está reapareciendo: Luto espera a que esté de pie para ladrar.
		proximo_ladrido = INF


func _process(delta: float) -> void:
	if not is_instance_valid(luto) or luto_cambiando_de_isla:
		return

	if isla_de_luto < ISLAS_LUTO.size():
		if jugador.global_position.distance_to(luto.global_position) < DISTANCIA_PARA_IRSE:
			_luto_se_va_a_la_siguiente_isla()
			return

	luto.flip_h = jugador.global_position.x < luto.global_position.x
	proximo_ladrido -= delta
	if proximo_ladrido <= 0.0:
		proximo_ladrido = randf_range(PAUSA_ENTRE_LADRIDOS.x, PAUSA_ENTRE_LADRIDOS.y)
		Ladrido.sonar(self, luto.global_position, 1)


## Al reaparecer, Luto ladra una sola vez desde la isla donde está.
func _ladrar_al_reaparecer() -> void:
	proximo_ladrido = randf_range(PAUSA_ENTRE_LADRIDOS.x, PAUSA_ENTRE_LADRIDOS.y)
	if is_instance_valid(luto):
		Ladrido.sonar(self, luto.global_position, 1)


func _poner_a_luto_en_su_isla() -> void:
	if isla_de_luto < ISLAS_LUTO.size():
		luto.global_position = ISLAS_LUTO[isla_de_luto]
	else:
		luto.global_position = posicion_final_luto


## Un último ladrido, se desvanece y aparece en la isla siguiente.
func _luto_se_va_a_la_siguiente_isla() -> void:
	luto_cambiando_de_isla = true
	Ladrido.sonar(self, luto.global_position, 1)

	var desaparecer := create_tween()
	desaparecer.tween_property(luto, "modulate:a", 0.0, DURACION_DESVANECER)
	await desaparecer.finished

	isla_de_luto += 1
	_poner_a_luto_en_su_isla()

	var aparecer := create_tween()
	aparecer.tween_property(luto, "modulate:a", 1.0, DURACION_DESVANECER)
	await aparecer.finished

	proximo_ladrido = randf_range(LADRIDO_TRAS_CAMBIAR_DE_ISLA.x, LADRIDO_TRAS_CAMBIAR_DE_ISLA.y)
	luto_cambiando_de_isla = false


## Cada isla sin resolver recibe un orden nuevo al azar (también cada vez que
## Lino muere y el nivel se recarga). Se mantiene el largo de cada secuencia.
func _barajar_puzzles() -> void:
	for numero in range(1, CANTIDAD_PUENTES + 1):
		if puentes_listos[numero - 1]:
			continue
		var puzzle := get_node_or_null("OnTheGround/Puzzle_Isla%d" % numero) as SequencePuzzle
		if not puzzle:
			continue
		var rocas: Array[SequencePuzzleObject] = []
		for hijo in puzzle.get_node("Objects").get_children():
			if hijo is SequencePuzzleObject:
				rocas.append(hijo)
		if rocas.size() < 2:
			continue
		for paso in puzzle.steps:
			var clave := String(paso.get_path())
			paso.sequence = _orden_al_azar(rocas, paso.sequence.size(), ultimo_orden.get(clave, []))
			ultimo_orden[clave] = paso.sequence.map(func(roca): return roca.name)


func _orden_al_azar(
	rocas: Array[SequencePuzzleObject], largo: int, anterior: Array
) -> Array[SequencePuzzleObject]:
	var orden: Array[SequencePuzzleObject] = []
	for intento in 20:
		orden.clear()
		if largo <= rocas.size():
			var mezcla := rocas.duplicate()
			mezcla.shuffle()
			orden.assign(mezcla.slice(0, largo))
		else:
			for i in largo:
				var opciones := rocas.filter(
					func(roca): return orden.is_empty() or roca != orden[-1]
				)
				orden.append(opciones.pick_random())
		if orden.map(func(roca): return roca.name) != anterior:
			break
	return orden


## La fogata del centro de cada isla es la que enseña la secuencia. Hasta que
## Lino la usa por primera vez, un halo cálido late sobre ella para llamarlo.
func _marcar_fogatas() -> void:
	var degradado := Gradient.new()
	degradado.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	degradado.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(0.5, 0.0)
	textura.width = 128
	textura.height = 128
	var suma := CanvasItemMaterial.new()
	suma.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	for numero in range(1, CANTIDAD_PUENTES + 1):
		if puentes_listos[numero - 1]:
			continue
		var ruta := "OnTheGround/Puzzle_Isla%d/Hints/SequencePuzzleHintSign%d" % [numero, numero]
		var fogata := get_node_or_null(ruta) as Node2D
		if not fogata or not fogata.get("interact_area"):
			continue
		var halo := Sprite2D.new()
		halo.texture = textura
		halo.material = suma
		halo.modulate = Color(COLOR_HALO_FOGATA, 0.0)
		halo.position = Vector2(0, -24)
		fogata.add_child(halo)

		var latido := halo.create_tween().set_loops()
		latido.tween_property(halo, "modulate:a", 0.75, 0.9).set_trans(Tween.TRANS_SINE)
		latido.parallel().tween_property(halo, "scale", Vector2.ONE * 1.5, 0.9)
		latido.tween_property(halo, "modulate:a", 0.15, 0.9).set_trans(Tween.TRANS_SINE)
		latido.parallel().tween_property(halo, "scale", Vector2.ONE, 0.9)

		fogata.interact_area.interaction_started.connect(
			func(_jugador: Node, _desde_la_derecha: bool) -> void:
				if is_instance_valid(halo):
					halo.queue_free(),
			CONNECT_ONE_SHOT
		)


func _pintar_haces_de_luz() -> void:
	for guardia in $OnTheGround.get_children():
		var luz := guardia.get_node_or_null("DetectionArea/Light") as PointLight2D
		if luz:
			luz.color = COLOR_HAZ_DE_LUZ


func _apagar_rocas() -> void:
	var material_rocas := ShaderMaterial.new()
	material_rocas.shader = ROCAS_APAGADAS
	for capa in $TileMapLayers.get_children():
		if capa is TileMapLayer and String(capa.name).begins_with("Rocas"):
			capa.material = material_rocas


func _activar_escudo() -> void:
	nivel_apagandose = true


# Conectadas a la señal tree_exited de cada hilo en la escena.
func reparar_puente_1() -> void:
	_reparar_puente(1)


func reparar_puente_2() -> void:
	_reparar_puente(2)


func reparar_puente_3() -> void:
	_reparar_puente(3)


func _reparar_puente(numero: int) -> void:
	if nivel_apagandose:
		return
	puentes_listos[numero - 1] = true
	_mostrar_puente_reparado(numero, true)


## Con [param retejer] el puente roto se deshace y el reparado se teje a la vista
## (al recoger el hilo). Sin él cambian al instante (al volver al nivel).
func _mostrar_puente_reparado(numero: int, retejer: bool = false) -> void:
	var puente = get_node_or_null("TileMapLayers/Puente%d" % numero)
	var puente_roto = get_node_or_null("TileMapLayers/PuenteRoto%d" % numero)
	if retejer:
		_tejer_puente(puente, puente_roto)
		return
	if puente:
		puente.show()
	if puente_roto:
		puente_roto.queue_free()


## El puente se teje franja a franja. Mientras tanto una barrera invisible no
## deja entrar a Lino: así no puede cruzarlo a ciegas ni caerse por adelantarse.
func _tejer_puente(puente: TileMapLayer, puente_roto: TileMapLayer) -> void:
	if not puente:
		return
	var zona := TileMapMaskBounds.get_world_bounds(puente)
	if puente_roto:
		# El trozo roto es parte del puente y Lino puede estar parado en él:
		# queda fuera de la barrera, y se quita justo cuando el tejido llega a él.
		var trozo_roto: Array[Vector2i] = puente_roto.get_used_cells()
		var roto := TileMapMaskBounds.get_world_bounds(puente_roto)
		if zona.size.y >= zona.size.x:
			if roto.get_center().y > zona.get_center().y:
				zona.end.y = roto.position.y
			else:
				zona.position.y = roto.end.y
		elif roto.get_center().x > zona.get_center().x:
			zona.end.x = roto.position.x
		else:
			zona.position.x = roto.end.x
		var espera := Retejido.momento_en_que_aparecen(puente, trozo_roto)
		get_tree().create_timer(espera).timeout.connect(
			func() -> void:
				if is_instance_valid(puente_roto):
					puente_roto.queue_free()
		)

	var barrera := StaticBody2D.new()
	barrera.collision_layer = 16  # paredes
	barrera.collision_mask = 0
	var forma := CollisionShape2D.new()
	var rectangulo := RectangleShape2D.new()
	rectangulo.size = zona.size
	forma.shape = rectangulo
	barrera.add_child(forma)
	add_child(barrera)
	barrera.global_position = zona.get_center()

	puente.set("tiempo_respiro_restante", Retejido.DURACION + RESPIRO_TRAS_TEJER)
	await Retejido.tejer_por_franjas(puente)
	if is_instance_valid(barrera):
		barrera.queue_free()


## Al volver al nivel, deja como estaba todo lo que el jugador ya había resuelto.
func _restaurar_puente_y_borrar_hilo(numero: int) -> void:
	_mostrar_puente_reparado(numero)

	var coleccionable = get_node_or_null("CollectibleItem%d" % numero)
	if coleccionable:
		# Sin la conexión a tree_exited, borrar el hilo no cuenta como recogerlo.
		for conexion in coleccionable.tree_exited.get_connections():
			coleccionable.tree_exited.disconnect(conexion.callable)
		coleccionable.queue_free()

	var ruta_letrero := (
		"OnTheGround/Puzzle_Isla%d/Hints/SequencePuzzleHintSign%d" % [numero, numero]
	)
	var letrero = get_node_or_null(ruta_letrero)
	if not letrero:
		push_warning("No se encontró el letrero en la ruta: %s" % ruta_letrero)
		return

	letrero.is_solved = true
	if "animated_sprite" in letrero and letrero.animated_sprite != null:
		letrero.animated_sprite.play("solved")
