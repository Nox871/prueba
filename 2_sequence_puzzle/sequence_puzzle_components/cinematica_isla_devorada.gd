# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node
## La isla devorada: cuando Lino cruza un puente reparado y pisa la isla
## siguiente, la cámara se aleja y muestra cómo el vacío da una vuelta a toda
## prisa a la isla que Lino acaba de dejar, y se la lleva entera a su paso.
## Después cruza el puente, lo deshace del todo y sigue su ronda, por el borde
## de la isla nueva.
##
## Se añade sola desde logica_nivel_2.gd. Vale para los dos primeros puentes
## (el tercero lleva a la salida).

const ESTADO_RONDA: int = 0  # State.IDLE del vacío
const MODO_DERROTADO: int = 2  # Player.Mode.DEFEATED
## Cada cuánto suelta polvo el vacío mientras está quieto (si no, no se le ve).
const PAUSA_ENTRE_POLVOS: float = 0.12
## Cuánto tiene que entrar Lino a la isla nueva para que empiece.
const DISTANCIA_DE_DISPARO: float = 230.0
const ZOOM_AL_ALEJAR: float = 0.6
const TIEMPO_CAMARA: float = 0.9
## Velocidad del vacío mientras devora la isla, en píxeles por segundo.
const VELOCIDAD_AL_DEVORAR: float = 1100.0
const TIEMPO_CRECER: float = 0.8
## Parte del cruce del puente en la que vuelve a su tamaño (0.8 = el primer 80 %).
const PARTE_DEL_PUENTE_PARA_CALMARSE: float = 0.8
## Radio de cada nube de polvo del vacío, en píxeles.
const RADIO_DE_UNA_NUBE: float = 144.0
## Cada cuántos píxeles de radio de furia suelta una nube más por cuadro.
const FURIA_POR_NUBE: float = 200.0
## Lo mínimo que dura la vuelta a la isla.
const TIEMPO_MINIMO: float = 1.6
## La vuelta se da a esta parte del radio de la isla (0 = centro, 1 = borde).
const PARTE_DEL_RADIO_PARA_LA_VUELTA: float = 0.55
## A esta distancia del vacío el suelo se deshace a su paso.
const RADIO_AL_DEVORAR: float = 230.0
## Margen para que termine de desvanecerse lo que había sobre la isla.
const TIEMPO_RESTOS: float = 0.7
## Tope de idas del vacío a por trozos sueltos de isla.
const VIAJES_MAXIMOS: int = 40
const TIEMPO_CRUZAR_PUENTE: float = 1.1
const PAUSA_FINAL: float = 0.5
## Tras la cinemática, el vacío no puede atrapar a Lino por un momento.
const TIEMPO_SIN_CAPTURA: float = 2.0
const CELDAS_MAXIMAS: int = 4000
## Velocidad de ronda del vacío en cada isla de puzzle (primera, segunda y
## tercera), en píxeles por segundo: cada isla es más grande y él va más rápido.
const VELOCIDAD_POR_ISLA: Array[float] = [110.0, 135.0, 160.0]
## Segundos que el vacío se queda quieto al llegar a cada isla, antes de
## empezar su ronda: en la última le da ventaja a Lino.
const VENTAJA_POR_ISLA: Array[float] = [0.0, 0.0, 6.0]
## Cada vez que Lino se deshila en este nivel, el vacío va un poco más lento
## (esta parte menos por muerte), hasta quedarse en [constant VELOCIDAD_MINIMA]
## de su velocidad normal.
const FRENO_POR_MUERTE: float = 0.06
const VELOCIDAD_MINIMA: float = 0.6
## Tope de celdas al buscar la isla a la que llega un puente (son las más grandes).
const CELDAS_MAXIMAS_DE_LLEGADA: int = 20000

## Una vez por puente. Si Lino muere y reaparece antes de ese puente, se repite
## (lo decide logica_nivel_2.gd al recargar el nivel).
static var hechas: Array[bool] = [false, false]

var nivel: Node2D
var jugador: Node2D
var vacio: Node2D
var suelo: TileMapLayer
## La ruta de ronda del vacío, que recorre las islas y cruza los puentes.
var ruta: Path2D
## Por cada puente: la capa, por dónde se entra y por dónde se sale.
var cruces: Array[Dictionary] = []
var ocupada: bool = false
var velocidades_del_vacio: CharacterSpeeds
var vacio_esperando: bool = false
## Radio de la nube del vacío mientras está enfurecido (0 = tamaño normal).
var furia: float = 0.0
var proximo_polvo: float = 0.0


func _ready() -> void:
	nivel = get_parent() as Node2D
	jugador = nivel.get_node_or_null("OnTheGround/Player") as Node2D
	vacio = nivel.get_node_or_null("OnTheGround/VoidSpreadingEnemy") as Node2D
	suelo = nivel.get_node_or_null("TileMapLayers/Suelo") as TileMapLayer
	if not jugador or not vacio or not suelo:
		set_process(false)
		return
	ruta = vacio.get("idle_patrol_path") as Path2D
	if not ruta:
		set_process(false)
		return

	# Lino viene del primer puente (isla 1 a isla 2): cada puente se cruza desde
	# el extremo más cercano a donde terminó el anterior.
	var anterior := Vector2.ZERO
	var primer_puente := nivel.get_node_or_null("TileMapLayers/PuenteIsla1a2") as TileMapLayer
	if primer_puente:
		anterior = TileMapMaskBounds.get_world_bounds(primer_puente).get_center()
	for numero in [1, 2]:
		var puente := nivel.get_node_or_null("TileMapLayers/Puente%d" % numero) as TileMapLayer
		if not puente:
			break
		var limites := TileMapMaskBounds.get_world_bounds(puente)
		var centro := limites.get_center()
		var a := Vector2(centro.x, limites.position.y)
		var b := Vector2(centro.x, limites.end.y)
		if limites.size.x > limites.size.y:
			a = Vector2(limites.position.x, centro.y)
			b = Vector2(limites.end.x, centro.y)
		var entrada := a if a.distance_to(anterior) < b.distance_to(anterior) else b
		var salida := b if entrada == a else a
		# La ruta del vacío pasa una sola vez por cada puente: con el punto medio
		# se sabe en qué tramo de la ruta entra y sale de él.
		var medio := ruta.curve.get_closest_offset(ruta.to_local(centro))
		var mitad := entrada.distance_to(salida) / 2.0
		(
			cruces
			. append(
				{
					"puente": puente,
					"entrada": entrada,
					"salida": salida,
					"tramo_entrada": medio - mitad,
					"tramo_salida": medio + mitad,
					"llegada": _isla_de_llegada(entrada, salida),
				}
			)
		)
		anterior = salida
	_dejar_como_estaba.call_deferred()


func _process(delta: float) -> void:
	_ajustar_velocidad_del_vacio()
	# A Lino ya lo atraparon: que nada más lo toque mientras cae (si no, el
	# vacío lo "atrapa" y suena varias veces).
	if jugador.get("mode") == MODO_DERROTADO and jugador.collision_layer != 0:
		jugador.set_deferred("collision_layer", 0)
	_soltar_polvo_de_furia()
	# El vacío solo se ve por el polvo que deja al moverse: quieto, hay que soltarlo.
	if vacio_esperando and is_instance_valid(vacio):
		proximo_polvo -= delta
		if proximo_polvo <= 0.0:
			proximo_polvo = PAUSA_ENTRE_POLVOS
			vacio.call("_emit_particles")
	if ocupada or not is_instance_valid(vacio) or vacio.get("void_layer") == null:
		return
	if jugador.get("mode") != 0:  # solo cuando el jugador tiene el control
		return
	var reparados: Array = (nivel.get_script() as GDScript).get("puentes_listos")
	for indice in cruces.size():
		if hechas[indice] or indice >= reparados.size() or not reparados[indice]:
			continue
		var cruce := cruces[indice]
		# Vale cualquier camino: basta con que Lino pise la isla nueva y se
		# aleje del puente, vaya recto o bordeándola por arriba o por abajo.
		var celda := suelo.local_to_map(suelo.to_local(jugador.global_position))
		var lejos: bool = jugador.global_position.distance_to(cruce.salida) > DISTANCIA_DE_DISPARO
		if lejos and (cruce.llegada as Dictionary).has(celda):
			hechas[indice] = true
			_devorar(cruce)
			return


func _devorar(cruce: Dictionary) -> void:
	ocupada = true
	var puente: TileMapLayer = cruce.puente
	var entrada: Vector2 = cruce.entrada
	var salida: Vector2 = cruce.salida
	var direccion := (salida - entrada).normalized()

	jugador.take_control(self)
	jugador.velocity = Vector2.ZERO
	var sombras := _congelar_sombras()
	_permitir_captura(false)
	vacio.path_walk_behavior.process_mode = Node.PROCESS_MODE_DISABLED

	var celdas := _celdas_de_la_isla(entrada - direccion * 96.0)
	var centro := Vector2.ZERO
	for celda in celdas:
		centro += suelo.to_global(suelo.map_to_local(celda))
	if not celdas.is_empty():
		centro /= float(celdas.size())

	var camara := get_viewport().get_camera_2d()
	var posicion_camara := camara.position
	var zoom_camara := camara.zoom
	var suavizado := camara.position_smoothing_enabled
	camara.position_smoothing_enabled = false
	var alejar := create_tween().set_parallel(true)
	alejar.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	alejar.tween_property(camara, "global_position", centro, TIEMPO_CAMARA)
	alejar.tween_property(camara, "zoom", zoom_camara * ZOOM_AL_ALEJAR, TIEMPO_CAMARA)
	await alejar.finished

	var hasta: float = cruce.tramo_entrada
	var pie_del_puente := ruta.to_global(ruta.curve.sample_baked(hasta))
	var pendientes := celdas.duplicate()
	var radio_isla := 0.0
	for celda in celdas:
		radio_isla = maxf(
			radio_isla, centro.distance_to(suelo.to_global(suelo.map_to_local(celda)))
		)
	var radio_vuelta := radio_isla * PARTE_DEL_RADIO_PARA_LA_VUELTA
	var alcance := radio_isla - radio_vuelta + 96.0
	var angulo := (pie_del_puente - centro).angle()
	var duracion_vuelta := maxf(TAU * radio_vuelta / VELOCIDAD_AL_DEVORAR, TIEMPO_MINIMO)
	_desvanecer_lo_que_hay_en(celdas, duracion_vuelta + TIEMPO_RESTOS)
	var alerta: AnimationPlayer = vacio.get("alert_animation")
	if alerta:
		alerta.play(&"alert")
	var crecer := create_tween()
	crecer.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	crecer.tween_property(self, "furia", alcance, TIEMPO_CRECER)
	while crecer.is_running():
		_devorar_cerca_del_vacio(pendientes, furia)
		await get_tree().process_frame
	if _tramo_actual() < cruce.tramo_salida:
		await _llevar_al_vacio(
			centro + Vector2.from_angle(angulo) * radio_vuelta, pendientes, alcance
		)
		var vuelta := create_tween()
		vuelta.tween_method(
			func(giro: float) -> void:
				vacio.global_position = centro + Vector2.from_angle(angulo + giro) * radio_vuelta,
			0.0,
			TAU,
			duracion_vuelta
		)
		while vuelta.is_running():
			_devorar_cerca_del_vacio(pendientes, alcance)
			await get_tree().process_frame
	await _ir_por_los_restos(pendientes, pie_del_puente)

	Retejido.sonar_caida(puente)
	Retejido.deshacer_por_franjas(puente, TIEMPO_CRUZAR_PUENTE, direccion)
	var cruzar := create_tween().set_parallel(true)
	cruzar.tween_method(_poner_vacio_en_el_tramo, hasta, cruce.tramo_salida, TIEMPO_CRUZAR_PUENTE)
	cruzar.tween_property(camara, "global_position", salida, TIEMPO_CRUZAR_PUENTE)
	(
		cruzar
		. tween_property(self, "furia", 0.0, TIEMPO_CRUZAR_PUENTE * PARTE_DEL_PUENTE_PARA_CALMARSE)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	await cruzar.finished
	await get_tree().create_timer(PAUSA_FINAL).timeout

	var volver := create_tween().set_parallel(true)
	volver.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	volver.tween_property(camara, "position", posicion_camara, TIEMPO_CAMARA)
	volver.tween_property(camara, "zoom", zoom_camara, TIEMPO_CAMARA)
	await volver.finished
	camara.position = posicion_camara
	camara.position_smoothing_enabled = suavizado

	vacio.state = ESTADO_RONDA
	var ventaja := VENTAJA_POR_ISLA[mini(cruces.find(cruce) + 1, VENTAJA_POR_ISLA.size() - 1)]
	if ventaja > 0.0:
		vacio.path_walk_behavior.process_mode = Node.PROCESS_MODE_DISABLED
		vacio_esperando = true
	_descongelar_sombras(sombras)
	_devolver_el_control()
	ocupada = false
	await get_tree().create_timer(maxf(TIEMPO_SIN_CAPTURA, ventaja), false).timeout
	vacio_esperando = false
	if is_instance_valid(vacio) and vacio.state == ESTADO_RONDA:
		vacio.path_walk_behavior.process_mode = Node.PROCESS_MODE_INHERIT
	_permitir_captura(true)


## Al volver al nivel: las islas que el vacío ya devoró antes del último hilo
## recogido siguen devoradas, y el vacío espera en el borde de la isla siguiente.
func _dejar_como_estaba() -> void:
	var ultima := -1
	for indice in cruces.size():
		if not hechas[indice]:
			continue
		ultima = indice
		var cruce := cruces[indice]
		var direccion: Vector2 = (cruce.salida - cruce.entrada).normalized()
		var celdas := _celdas_de_la_isla(cruce.entrada - direccion * 96.0)
		_desvanecer_lo_que_hay_en(celdas, 0.0)
		_consumir(celdas, true)
		var puente: TileMapLayer = cruce.puente
		puente.enabled = false
		puente.hide()
	if ultima >= 0:
		_poner_vacio_en_el_tramo(cruces[ultima].tramo_salida)


## Enfurecido, el vacío es una nube mucho más grande: suelta sus nubes de polvo
## repartidas por todo el radio de [member furia].
func _soltar_polvo_de_furia() -> void:
	if furia <= 0.0 or not is_instance_valid(vacio):
		return
	var nubes: PackedScene = vacio.get("void_particles")
	var grupo: Node = vacio.get("particles_canvas_group")
	if not nubes or not grupo:
		return
	var alcance_del_polvo := maxf(furia - RADIO_DE_UNA_NUBE, 0.0)
	for i in int(ceil(furia / FURIA_POR_NUBE)):
		var nube: GPUParticles2D = nubes.instantiate()
		nube.position = Vector2.from_angle(randf() * TAU) * alcance_del_polvo * sqrt(randf())
		nube.emitting = true
		nube.finished.connect(nube.queue_free)
		grupo.add_child(nube)


## El vacío ronda más rápido en cada isla. Se sabe en cuál está por los
## puentes que su ruta ya dejó atrás.
func _ajustar_velocidad_del_vacio() -> void:
	if not is_instance_valid(vacio) or not ruta:
		return
	var tramo := _tramo_actual()
	var isla := 0
	for cruce in cruces:
		if tramo >= cruce.tramo_salida - 32.0:
			isla += 1
	var velocidad := VELOCIDAD_POR_ISLA[mini(isla, VELOCIDAD_POR_ISLA.size() - 1)]
	velocidad *= ElHiloQueNoTejiState.alivio_por_muertes(
		"sequence_puzzle", FRENO_POR_MUERTE, VELOCIDAD_MINIMA
	)
	var paso: Node = vacio.path_walk_behavior
	if not velocidades_del_vacio:
		# Copia propia: la original es un recurso compartido de Threadbare.
		velocidades_del_vacio = paso.speeds.duplicate()
		paso.speeds = velocidades_del_vacio
	velocidades_del_vacio.walk_speed = velocidad


## En qué punto de su ruta (en píxeles desde el inicio) está el vacío.
func _tramo_actual() -> float:
	return ruta.curve.get_closest_offset(ruta.to_local(vacio.global_position))


func _poner_vacio_en_el_tramo(tramo: float) -> void:
	vacio.global_position = ruta.to_global(ruta.curve.sample_baked(tramo))


## Convierte en vacío las celdas de suelo de [param celdas].
func _consumir(celdas: Array[Vector2i], al_instante: bool = false) -> void:
	var capa_vacio: TileMapLayer = vacio.get("void_layer")
	if not capa_vacio or celdas.is_empty():
		return
	var lote: Array[Vector2i] = []
	for celda in celdas:
		var punto := suelo.to_global(suelo.map_to_local(celda))
		lote.append(capa_vacio.local_to_map(capa_vacio.to_local(punto)))
	capa_vacio.call("consume_cells", lote, al_instante)


## Devora (y quita de [param pendientes]) las celdas a menos de [param radio] del vacío.
func _devorar_cerca_del_vacio(pendientes: Array[Vector2i], radio: float) -> void:
	var cerca: Array[Vector2i] = []
	for i in range(pendientes.size() - 1, -1, -1):
		var punto := suelo.to_global(suelo.map_to_local(pendientes[i]))
		if punto.distance_to(vacio.global_position) <= radio:
			cerca.append(pendientes[i])
			pendientes.remove_at(i)
	_consumir(cerca)


## El vacío va él mismo, uno por uno, a los trozos de isla que su ronda no
## alcanzó, y vuelve al puente.
func _ir_por_los_restos(pendientes: Array[Vector2i], regreso: Vector2) -> void:
	var viajes := 0
	while not pendientes.is_empty() and viajes < VIAJES_MAXIMOS:
		viajes += 1
		var destino := vacio.global_position
		var mas_cerca := INF
		for celda in pendientes:
			var punto := suelo.to_global(suelo.map_to_local(celda))
			var distancia := punto.distance_to(vacio.global_position)
			if distancia < mas_cerca:
				mas_cerca = distancia
				destino = punto
		await _llevar_al_vacio(destino, pendientes, RADIO_AL_DEVORAR)
	_devorar_cerca_del_vacio(pendientes, INF)
	await _llevar_al_vacio(regreso, pendientes, RADIO_AL_DEVORAR)


## Mueve al vacío en línea recta, devorando el suelo a su paso.
func _llevar_al_vacio(destino: Vector2, pendientes: Array[Vector2i], alcance: float) -> void:
	while vacio.global_position.distance_to(destino) > 4.0:
		vacio.global_position = vacio.global_position.move_toward(
			destino, VELOCIDAD_AL_DEVORAR * get_process_delta_time()
		)
		_devorar_cerca_del_vacio(pendientes, alcance)
		await get_tree().process_frame


## Las celdas de la isla a la que lleva un puente, como conjunto (celda: true).
func _isla_de_llegada(entrada: Vector2, salida: Vector2) -> Dictionary:
	var direccion := (salida - entrada).normalized()
	var llegada: Dictionary = {}
	for celda in _celdas_de_la_isla(salida + direccion * 96.0, CELDAS_MAXIMAS_DE_LLEGADA):
		llegada[celda] = true
	return llegada


## Todas las celdas de suelo unidas a la que está en [param punto].
func _celdas_de_la_isla(punto: Vector2, maximo: int = CELDAS_MAXIMAS) -> Array[Vector2i]:
	var inicio := suelo.local_to_map(suelo.to_local(punto))
	var isla: Array[Vector2i] = []
	if suelo.get_cell_source_id(inicio) == -1:
		# El punto cayó justo fuera: se busca la celda de suelo más cercana.
		var mejor := INF
		for celda in suelo.get_used_cells():
			var distancia := Vector2(celda - inicio).length()
			if distancia < mejor:
				mejor = distancia
				inicio = celda
		if mejor > 6.0:
			return isla
	var vistas: Dictionary = {inicio: true}
	var pendientes: Array[Vector2i] = [inicio]
	while not pendientes.is_empty() and isla.size() < maximo:
		var celda: Vector2i = pendientes.pop_back()
		isla.append(celda)
		for vecina in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var otra: Vector2i = celda + vecina
			if not vistas.has(otra) and suelo.get_cell_source_id(otra) != -1:
				vistas[otra] = true
				pendientes.append(otra)
	return isla


## Lo que había sobre la isla (rocas del puzzle, fogata, sombras) se desvanece
## con ella, para que no quede flotando sobre el vacío.
func _desvanecer_lo_que_hay_en(celdas: Array[Vector2i], duracion: float) -> void:
	var de_la_isla: Dictionary = {}
	for celda in celdas:
		de_la_isla[celda] = true
	var cosas: Array[Node2D] = []
	for hijo in nivel.get_node("OnTheGround").get_children():
		if hijo == jugador or hijo == vacio or hijo.name == &"Luto" or not (hijo is Node2D):
			continue
		if hijo is Path2D:
			continue
		# Los puzzles están en el origen: lo que cuenta es dónde están sus piezas.
		var piezas: Array[Node] = [hijo]
		if String(hijo.name).begins_with("Puzzle_"):
			piezas = hijo.find_children("*", "Node2D", true, false)
		for pieza in piezas:
			var celda := suelo.local_to_map(suelo.to_local((pieza as Node2D).global_position))
			if de_la_isla.has(celda):
				cosas.append(hijo)
				break
	if cosas.is_empty():
		return
	var ocultar := func() -> void:
		for cosa in cosas:
			if is_instance_valid(cosa):
				cosa.hide()
				cosa.process_mode = Node.PROCESS_MODE_DISABLED
	if duracion <= 0.0:
		ocultar.call()
		return
	var desvanecer := create_tween().set_parallel(true)
	for cosa in cosas:
		desvanecer.tween_property(cosa, "modulate:a", 0.0, duracion)
	desvanecer.chain().tween_callback(ocultar)


## Si a Lino ya lo atraparon, devolverle el control lo dejaría "vivo" otra vez
## y moriría dos veces: en ese caso solo se retira esta cinemática.
func _devolver_el_control() -> void:
	if jugador.get("mode") == MODO_DERROTADO:
		jugador.get("_system_controllers").erase(self)
		return
	jugador.return_control(self)


func _permitir_captura(permitir: bool) -> void:
	if not is_instance_valid(vacio):
		return
	var captura := vacio.get_node_or_null("PlayerCaptureArea") as Area2D
	if captura:
		captura.set_deferred("monitoring", permitir)


func _congelar_sombras() -> Dictionary:
	var congeladas: Dictionary = {}
	for sombra in get_tree().get_nodes_in_group("guard_enemy"):
		congeladas[sombra] = sombra.process_mode
		sombra.process_mode = Node.PROCESS_MODE_DISABLED
	return congeladas


func _descongelar_sombras(congeladas: Dictionary) -> void:
	for sombra in congeladas:
		if is_instance_valid(sombra) and sombra.is_visible_in_tree():
			sombra.process_mode = congeladas[sombra]
