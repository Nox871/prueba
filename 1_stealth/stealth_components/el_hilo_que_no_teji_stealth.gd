# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node2D

const DIALOGO_STEALTH = preload("uid://cut4yag2eux0s")
## el_hilo_que_no_teji_sequence_puzzle.tscn
const SIGUIENTE_NIVEL: String = "uid://ds04vtvl5lrkt"
const HILOS: Array[String] = ["CollectibleItem", "CollectibleItem2", "CollectibleItem3"]
# Zona en la mitad de arriba del puente de la colina (x 512-704, y -4416 a -3648):
# desde ahí Lino ve a Luto. Queda pasando BloqueoPuente, así que solo se alcanza
# con el puente abierto.
const ZONA_PUENTE_CENTRO := Vector2(608, -4150)
const ZONA_PUENTE_TAMANO := Vector2(190, 60)
const DISTANCIA_HUIDA_LUTO: float = 420.0
# Dónde aparece Luto respecto de Lino al verlo desde el puente (dentro de la pantalla).
const DISTANCIA_LUTO_A_LINO: float = 250.0
const DURACION_HUIDA_LUTO: float = 2.4
# Si Lino se pierde, un ladrido le recuerda hacia dónde ir (cada 1:40 a 2:20).
const INTERVALO_LADRIDO := Vector2(100.0, 140.0)
# Donde patrulla Luto, al norte, pasando el puente de la colina.
const PUNTO_LUTO := Vector2(620, -4500)
const TIEMPO_MAXIMO_REVIVIR: float = 4.0
# Tronco de small_tree.png dentro de el_hilo_que_no_teji_enviroment.tres.
const FUENTE_ARBOL: int = 7
const ATLAS_TRONCO := Vector2i(2, 3)
# Tamaño del tapón entre dos troncos en diagonal, relativo a una celda.
const TAPON_DIAGONAL: float = 0.7

# Progreso del nivel. Es estático para conservarlo cuando el nivel
# se recarga después de que atrapan a Lino.
static var hilos_totales: int = 0
static var hilo1_tomado: bool = false
static var hilo2_tomado: bool = false
static var hilo3_tomado: bool = false

## Al recargar la escena, los hilos que siguen en el nivel emiten
## tree_exited; así no se cuentan como recogidos.
var nivel_apagandose: bool = false
var temporizador_ladrido: Timer

@onready var particulas_doradas = $TileMapLayers/Tree/ParticulasDoradas
@onready var flecha = $TileMapLayers/Tree/Flecha


func _ready() -> void:
	if ElHiloQueNoTejiState.es_partida_nueva_para("stealth"):
		hilos_totales = 0
		hilo1_tomado = false
		hilo2_tomado = false
		hilo3_tomado = false

	GameState.player.set_ability(Enums.PlayerAbilities.ABILITY_B, false)
	nivel_apagandose = false
	tree_exiting.connect(_activar_escudo)

	_mostrar_rocas_hilo_3(hilo3_tomado)

	if hilo3_tomado:
		_abrir_puente()
	else:
		var puente_normal = get_node_or_null("TileMapLayers/PuenteNormal")
		if puente_normal:
			puente_normal.visible = false
			puente_normal.process_mode = Node.PROCESS_MODE_DISABLED

	if hilo1_tomado:
		if has_node("CollectibleItem"):
			$CollectibleItem.queue_free()
		var rocas_1 = get_node_or_null("TileMapLayers/RocasBloqueoHilo1")
		if rocas_1:
			rocas_1.queue_free()

	if hilo2_tomado:
		if has_node("CollectibleItem2"):
			$CollectibleItem2.queue_free()
		var rocas_2 = get_node_or_null("TileMapLayers/RocasBloqueoHilo2")
		if rocas_2:
			rocas_2.queue_free()
		if has_node("Sign"):
			$Sign.queue_free()

	if hilo3_tomado and has_node("CollectibleItem3"):
		$CollectibleItem3.queue_free()

	verificar_progreso()
	_preparar_ladridos()
	_bloquear_salto_dialogo_inicial()
	_crear_zona_puente_luto()
	_tapar_huecos_diagonales_de_arboles()
	_preparar_pesadilla_y_fantasma()
	_mostrar_cartel_de_shift(hilo2_tomado)
	var reaparicion := ReaparicionEnHilo.new()
	if GameState.scene.intro_dialogue_shown:
		reaparicion.termino.connect(_ladrar_hacia_lo_siguiente)
	add_child(reaparicion)


func verificar_progreso() -> void:
	if hilos_totales >= 3 and flecha:
		flecha.visible = true


## Primera vez en el nivel: Lino se levanta (animación "revive"), queda confundido
## ("c_confused") y recién ahí aparece el diálogo de entrada, que avanza solo.
## Si ya se mostró (por ejemplo, al reaparecer tras ser atrapado), no hace nada.
func _bloquear_salto_dialogo_inicial() -> void:
	if GameState.scene.intro_dialogue_shown:
		return
	var lino := get_tree().get_first_node_in_group("player") as Player
	var sprite: AnimatedSprite2D = lino.get_node("%PlayerSprite")
	var animation_player: AnimationPlayer = lino.get_node("AnimationPlayer")

	lino.take_control(self)
	# El AnimationPlayer del jugador fuerza "idle" en cada cuadro: se pausa.
	animation_player.pause()
	animation_player.set_process(false)

	sprite.play(&"revive")
	var limite := Time.get_ticks_msec() + int(TIEMPO_MAXIMO_REVIVIR * 1000)
	while sprite.is_playing() and sprite.animation == &"revive" and Time.get_ticks_msec() < limite:
		await get_tree().process_frame
	sprite.play(&"c_confused")

	var bloqueo := BloqueoSaltoDialogo.new()
	add_child(bloqueo)
	$Cinematic.start()
	await $Cinematic.cinematic_finished
	bloqueo.queue_free()

	animation_player.set_process(true)
	animation_player.play(&"idle")
	lino.return_control(self)
	_ladrar_hacia_lo_siguiente()


## Ladra al entrar al nivel, al terminar el diálogo de cada hilo y, si Lino
## se pierde, cada INTERVALO_LADRIDO segundos.
func _preparar_ladridos() -> void:
	temporizador_ladrido = Timer.new()
	temporizador_ladrido.one_shot = true
	temporizador_ladrido.wait_time = randf_range(INTERVALO_LADRIDO.x, INTERVALO_LADRIDO.y)
	temporizador_ladrido.timeout.connect(_ladrar_hacia_lo_siguiente)
	add_child(temporizador_ladrido)
	if GameState.scene.intro_dialogue_shown:
		temporizador_ladrido.start()


## El ladrido viene del hilo más cercano que Lino todavía no recogió.
## Si ya tiene los tres, viene de donde está Luto.
func _ladrar_hacia_lo_siguiente() -> void:
	if not is_inside_tree() or nivel_apagandose:
		return
	temporizador_ladrido.start(randf_range(INTERVALO_LADRIDO.x, INTERVALO_LADRIDO.y))

	var lino := get_tree().get_first_node_in_group("player") as Node2D
	if not lino:
		return
	var mas_cercano: Node2D = null
	if hilos_totales >= 3:
		_ladrar_en(PUNTO_LUTO)
		return
	for nombre in HILOS:
		var hilo := get_node_or_null(nombre) as Node2D
		if not hilo or not hilo.is_inside_tree() or hilo.is_queued_for_deletion():
			continue
		var distancia := hilo.global_position.distance_to(lino.global_position)
		if (
			not mas_cercano
			or distancia < mas_cercano.global_position.distance_to(lino.global_position)
		):
			mas_cercano = hilo
	if mas_cercano:
		_ladrar_en(mas_cercano.global_position)
		return

	_ladrar_en(PUNTO_LUTO)


## Un solo ladrido desde donde esté el nodo (se usa mientras Luto corre).
func _ladrar_desde(nodo: Node2D) -> void:
	if is_instance_valid(nodo):
		Ladrido.sonar(self, nodo.global_position, 1)


func _ladrar_en(posicion: Vector2) -> void:
	Ladrido.sonar(self, posicion)


func _activar_escudo() -> void:
	nivel_apagandose = true


func _on_collectible_item_tree_exited() -> void:
	if nivel_apagandose:
		return
	if not hilo1_tomado:
		hilo1_tomado = true
		hilos_totales += 1
		verificar_progreso()
		await _romper_rocas_sin_camara("TileMapLayers/RocasBloqueoHilo1")
		_ladrar_hacia_lo_siguiente()


func _on_collectible_item_2_tree_exited() -> void:
	if nivel_apagandose:
		return
	if not hilo2_tomado:
		hilo2_tomado = true
		hilos_totales += 1
		verificar_progreso()
		await _romper_rocas(
			"TileMapLayers/RocasBloqueoHilo2",
			"TileMapLayers/FocoCamaraRocas2",
			get_node_or_null("Sign") as Node2D
		)
		_mostrar_cartel_de_shift(true)
		_ladrar_hacia_lo_siguiente()


## Las rocas que rodean al hilo 1 se deshacen ahí mismo, sin mover la cámara.
func _romper_rocas_sin_camara(ruta_rocas: String) -> void:
	var rocas := get_node_or_null(ruta_rocas) as TileMapLayer
	if not rocas:
		return
	var desintegracion := create_tween()
	_desintegrar(desintegracion, rocas)
	await desintegracion.finished


## La cámara va hasta las rocas que tapaban el camino y muestra cómo se
## desintegran. [param acompanante] (si hay) se desvanece junto con ellas.
func _romper_rocas(ruta_rocas: String, ruta_foco: String, acompanante: Node2D = null) -> void:
	var rocas := get_node_or_null(ruta_rocas) as TileMapLayer
	var lino := get_tree().get_first_node_in_group("player") as Player
	if not rocas or not lino:
		return
	var foco := get_node_or_null(ruta_foco) as Node2D

	lino.take_control(self)
	lino.velocity = Vector2.ZERO
	var guardias := get_node_or_null("EnemyGuards")
	if guardias:
		guardias.process_mode = Node.PROCESS_MODE_DISABLED

	var camara := get_viewport().get_camera_2d()
	var zoom_original := camara.zoom
	var suavizado_original := camara.position_smoothing_enabled
	camara.position_smoothing_enabled = false

	var cinematica := create_tween()
	var destino_camara := foco.global_position if foco else _centro_de(rocas)
	cinematica.tween_property(camara, "global_position", destino_camara, 1.2).set_trans(
		Tween.TRANS_SINE
	)
	cinematica.parallel().tween_property(camara, "zoom", Vector2(1.4, 1.4), 1.2)
	cinematica.chain().tween_interval(0.3)
	if acompanante:
		cinematica.tween_callback(func(): _desintegrar(create_tween(), acompanante))
	_desintegrar(cinematica, rocas)
	cinematica.tween_interval(0.8)
	cinematica.tween_property(camara, "global_position", lino.global_position, 0.8).set_trans(
		Tween.TRANS_QUAD
	)
	cinematica.parallel().tween_property(camara, "zoom", zoom_original, 0.8)
	await cinematica.finished

	camara.position_smoothing_enabled = suavizado_original
	camara.global_position = lino.global_position
	if is_instance_valid(guardias):
		guardias.process_mode = Node.PROCESS_MODE_INHERIT
	lino.return_control(self)


## Agrega a [param animacion] el temblor, el destello y el polvo que se lleva a [param objeto].
func _desintegrar(animacion: Tween, objeto: Node2D) -> void:
	var pos_original := objeto.position
	for i in range(24):
		var intensidad := float(i) / 24.0
		var fuerza_x := randf_range(-1.0, 1.0) + randf_range(-4.0, 4.0) * intensidad
		var fuerza_y := randf_range(-1.0, 1.0) + randf_range(-2.0, 2.0) * intensidad
		animacion.tween_property(
			objeto, "position", pos_original + Vector2(fuerza_x, fuerza_y), 0.05
		)

	# Los shaders de saturación ignoran el modulate; sin ellos se ven el
	# destello y el desvanecimiento.
	animacion.tween_callback(
		func():
			if is_instance_valid(objeto):
				_quitar_materiales(objeto)
				objeto.modulate = Color(2.0, 2.0, 2.0, 1.0)
	)
	(
		animacion
		. tween_property(objeto, "position", pos_original + Vector2(0, -15), 0.6)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	animacion.parallel().tween_property(objeto, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.6)
	animacion.tween_callback(objeto.queue_free)


func _quitar_materiales(nodo: Node) -> void:
	if nodo is CanvasItem:
		nodo.material = null
	for hijo in nodo.get_children():
		_quitar_materiales(hijo)


func _centro_de(capa: TileMapLayer) -> Vector2:
	var celdas := capa.get_used_cells()
	if celdas.is_empty():
		return capa.global_position
	var suma := Vector2.ZERO
	for celda in celdas:
		suma += capa.to_global(capa.map_to_local(celda))
	return suma / celdas.size()


func _on_collectible_item_3_tree_exited() -> void:
	if nivel_apagandose:
		return
	if not hilo3_tomado:
		hilo3_tomado = true
		hilos_totales += 1
		verificar_progreso()

		_mostrar_rocas_hilo_3(true)
		_abrir_puente()
		_ladrar_hacia_lo_siguiente()


## Las rocas del hilo 3 aparecen recién cuando se recoge ese hilo.
func _mostrar_rocas_hilo_3(mostrar: bool) -> void:
	var rocas_3 = get_node_or_null("TileMapLayers/RocasBloqueoHilo3")
	if not rocas_3:
		return
	rocas_3.visible = mostrar
	# Escondidas, se mueven lejos para que tampoco bloqueen el paso.
	rocas_3.position = Vector2.ZERO if mostrar else Vector2(9999, 9999)


## Cambia el puente roto por el sano y quita el muro invisible que bloqueaba el paso.
func _abrir_puente() -> void:
	var puente_roto = get_node_or_null("TileMapLayers/PuenteRoto")
	if puente_roto:
		puente_roto.queue_free()

	var bloqueo_puente = get_node_or_null("TileMapLayers/BloqueoPuente")
	if bloqueo_puente:
		bloqueo_puente.queue_free()

	var puente_normal = get_node_or_null("TileMapLayers/PuenteNormal")
	if puente_normal:
		puente_normal.visible = true
		puente_normal.process_mode = Node.PROCESS_MODE_INHERIT


func _on_zona_climax_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if hilos_totales >= 3:
			body.velocity = Vector2.ZERO
			body.take_control(self)
			$ZonaClimax.set_deferred("monitoring", false)

			if has_node("EnemyGuards"):
				$EnemyGuards.queue_free()

			particulas_doradas.emitting = true
			if flecha:
				flecha.visible = false

			add_child(BloqueoSaltoDialogo.new())
			DialogueManager.show_dialogue_balloon(DIALOGO_STEALTH, "arbol_climax")
			await DialogueManager.dialogue_ended
			SceneSwitcher.change_to_file_with_transition(SIGUIENTE_NIVEL)


## Al cruzar el puente de la colina, Luto ve a Lino, le ladra y corre hacia el norte.
## Los bordes de la pantalla se oscurecen cuando hay una sombra cerca. Luto es
## del mismo tipo de nodo que las sombras, pero no asusta: él parpadea como un
## fantasma.
func _preparar_pesadilla_y_fantasma() -> void:
	var pesadilla := Pesadilla.new()
	var luto := find_child("Luto-Guard", true, false)
	if luto:
		pesadilla.inofensivos = [luto]
		luto.add_child(EfectoFantasma.new())
	add_child(pesadilla)


## El cartel firmado "Shift" está detrás de las rocas del segundo hilo: no se
## ve ni estorba hasta que esas rocas se deshacen y la cámara vuelve con Lino.
func _mostrar_cartel_de_shift(mostrar: bool) -> void:
	var cartel := get_node_or_null("CartelShift") as Node2D
	if not cartel:
		return
	var choque := cartel.get_node_or_null("Collider/CollisionShape2D") as CollisionShape2D
	if choque:
		choque.set_deferred("disabled", not mostrar)
	if not mostrar:
		cartel.hide()
	elif not cartel.visible:
		cartel.modulate.a = 0.0
		cartel.show()
		create_tween().tween_property(cartel, "modulate:a", 1.0, 0.8)


func _crear_zona_puente_luto() -> void:
	var zona := Area2D.new()
	zona.collision_mask = $ZonaClimax.collision_mask
	var forma := CollisionShape2D.new()
	var rectangulo := RectangleShape2D.new()
	rectangulo.size = ZONA_PUENTE_TAMANO
	forma.shape = rectangulo
	zona.add_child(forma)
	add_child(zona)
	zona.global_position = ZONA_PUENTE_CENTRO
	zona.body_entered.connect(_al_cruzar_puente_luto.bind(zona))


func _al_cruzar_puente_luto(body: Node2D, zona: Area2D) -> void:
	if not body.is_in_group("player") or not hilo3_tomado:
		return
	zona.queue_free()
	temporizador_ladrido.stop()
	# Se sale de la señal de física antes de cambiar a Luto de padre.
	await get_tree().process_frame

	var luto := find_child("Luto-Guard", true, false) as Node2D
	if not luto:
		_ladrar_en(PUNTO_LUTO)
		return
	var sprite := luto.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	# EnemyGuards se borra al llegar al árbol; Luto sale de ahí para seguir
	# corriendo mientras Lino habla.
	luto.reparent(self)
	luto.z_index = 11  # por encima de las copas de los árboles

	# La cámara de Lino (zoom 1.4) solo ve unos 380 px hacia arriba y no pasa de
	# limit_top, y Luto patrulla justo en ese borde: por eso no se veía. Se lo
	# pone delante de Lino, a la vista, antes de que ladre.
	luto.global_position = Vector2(
		ZONA_PUENTE_CENTRO.x, body.global_position.y - DISTANCIA_LUTO_A_LINO
	)

	# Luto deja su ruta de guardia: se mueve a mano, pero su sprite sigue animado.
	luto.process_mode = Node.PROCESS_MODE_DISABLED
	if sprite:
		sprite.process_mode = Node.PROCESS_MODE_ALWAYS
		sprite.flip_h = body.global_position.x < luto.global_position.x
		sprite.play(&"bark")
	Ladrido.sonar(self, luto.global_position, 1)
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(luto):
		return

	if sprite:
		sprite.play(&"walk")
		sprite.speed_scale = 2.5
	var camara := get_viewport().get_camera_2d()
	var destino_y := luto.global_position.y - DISTANCIA_HUIDA_LUTO
	if camara:
		destino_y = camara.limit_top - 80.0
	var huida := create_tween()
	huida.tween_property(luto, "global_position:y", destino_y, DURACION_HUIDA_LUTO)
	huida.parallel().tween_property(luto, "modulate:a", 0.0, 0.8).set_delay(
		DURACION_HUIDA_LUTO - 0.8
	)
	huida.parallel().tween_callback(_ladrar_desde.bind(luto)).set_delay(1.2)
	huida.tween_callback(luto.queue_free)


## Entre dos árboles que se tocan en diagonal quedaba un hueco por el que Lino
## podía colarse. Aquí se tapa cada una de esas esquinas.
func _tapar_huecos_diagonales_de_arboles() -> void:
	var troncos := get_node_or_null("TileMapLayers/SmallTreesBase") as TileMapLayer
	if not troncos:
		return

	var celdas_tronco: Dictionary = {}
	for celda in troncos.get_used_cells():
		if (
			troncos.get_cell_source_id(celda) == FUENTE_ARBOL
			and troncos.get_cell_atlas_coords(celda) == ATLAS_TRONCO
		):
			celdas_tronco[celda] = true

	var tapones := StaticBody2D.new()
	tapones.collision_layer = troncos.tile_set.get_physics_layer_collision_layer(0)
	tapones.collision_mask = 0
	var lado: float = troncos.tile_set.tile_size.x * troncos.global_scale.x * TAPON_DIAGONAL

	for celda in celdas_tronco:
		for dx in [-1, 1]:
			var diagonal: Vector2i = celda + Vector2i(dx, 1)
			var hay_hueco: bool = (
				celdas_tronco.has(diagonal)
				and not celdas_tronco.has(celda + Vector2i(0, 1))
				and not celdas_tronco.has(celda + Vector2i(dx, 0))
			)
			if not hay_hueco:
				continue
			var forma := CollisionShape2D.new()
			var cuadrado := RectangleShape2D.new()
			cuadrado.size = Vector2(lado, lado)
			forma.shape = cuadrado
			forma.position = (
				(
					troncos.to_global(troncos.map_to_local(celda))
					+ troncos.to_global(troncos.map_to_local(diagonal))
				)
				/ 2.0
			)
			tapones.add_child(forma)

	add_child(tapones)
