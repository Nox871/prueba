# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node
## Efectos del final del nivel 3.2: la puerta que aparece cuando Elián se va,
## las ondas que devuelven el color, el temblor del mundo, el vacío que se
## cierra y la luz que sale de la puerta.

# La puerta del centro, oculta mientras Elián siga ahí
# Capa que frena a Lino pero no a los proyectiles (que chocan con paredes).
const CAPA_SOLO_JUGADOR: int = 512
const DURACION_APARECE_PUERTA: float = 1.5

# El color vuelve en ondas desde el último hilo
# Saturación del mundo con 8 hilos; el noveno ya no la sube de golpe.
const SATURACION_ANTES_DEL_ULTIMO_HILO: float = 0.15
const ONDA_VELOCIDAD: float = 330.0
const ONDA_INTERVALO: float = 4.5
const ONDA_CANTIDAD: int = 5
const ONDA_ANCHO: float = 260.0
# Cuánto se ilumina el frente de cada onda.
const ONDA_BRILLO: float = 0.6
const DURACION_RECUPERAR_COLOR: float = 1.4
const BRILLO_AL_RECUPERAR := Color(1.5, 1.5, 1.35, 1.0)

# Temblor del mundo: (píxeles, vaivenes por segundo)
const TEMBLOR_LEVE := Vector2(1.2, 1.0)
const TEMBLOR_FUERTE := Vector2(7.0, 8.0)

# Durante el último diálogo de Elián la música baja un poco.
const BUS_MUSICA: StringName = &"Music"
const BAJADA_MUSICA_DB: float = 8.0
# Los proyectiles se dibujan por encima de los puentes y del suelo.
const Z_PROYECTILES: int = 20

# El vacío: Elián lo invoca al reírse
const VELOCIDAD_VACIO: float = 85.0
# Elián solo lanza orbes cuando Lino está a esta distancia o menos.
const ALCANCE_DE_ELIAN: float = 1000.0
# Distancia máxima entre una sombra y el proyectil que acaba de lanzar.
const ALCANCE_DE_LANZAMIENTO: float = 160.0

# Al entrar a la sala, la cámara se acerca a Elián mientras se ríe.
const ZOOM_ACERCAMIENTO_ELIAN := Vector2(1.6, 1.6)
const TIEMPO_IDA_A_ELIAN: float = 1.2
const TIEMPO_MIRANDO_A_ELIAN: float = 5.0
## Lo que dice Elián al reírse, cuando la cámara se acerca a él.
const FRASE_DE_ELIAN_AL_LLEGAR: String = (
	"Llegas tarde... como siempre...\n"
	+ "Ahora los recuerdos que tienes de tu perro me pertenecen."
)
const TIEMPO_VUELTA_A_LINO: float = 0.9
const ZOOM_MIRANDO_AL_VACIO := Vector2(1.0, 1.0)
const TIEMPO_IDA_AL_VACIO: float = 1.0
const TIEMPO_MIRANDO_AL_VACIO: float = 1.8

const PASO_DEL_VACIO: float = 48.0
# Segundos que dura un orbe de Elián sin chocar con nada.
const DURACION_ORBE_DE_ELIAN: float = 6.5
const ORBE_DE_ELIAN: String = "boss_projectile.tscn"
# Las barandas de los puentes dejan la capa de las paredes y pasan a estas dos:
# la de solo jugador (frena a Lino) y una propia de los puentes, con la que
# chocan todos los proyectiles menos los orbes de Elián.
const TERMINACION_DE_LOS_PUENTES: String = "bridges.tres"
const CAPA_DE_LOS_PUENTES: int = 2048
const DURACION_DISIPAR_NIEBLA: float = 3.0
const BendicionDeLuto = preload("bendicion_de_luto.gd")
const DURACION_IRIS: float = 1.6
const SHADER_IRIS: Shader = preload("../../../shared/shaders/iris_blanco.gdshader")

var material_mundo: ShaderMaterial
var puerta: Node2D
## Los vacíos que Elián invoca (uno a cada lado de la sala).
var vacios: Array = []
var origen_ondas := Vector2.ZERO
var material_puerta: ShaderMaterial
var capa_original_puerta: int = 16
var onda_tiempo: float = -1.0
var temblor_amplitud: float = 0.0
var temblor_frecuencia: float = 0.0
var temblor_fase: float = 0.0
var vacio_offsets: Dictionary = {}
var volumen_musica_original: float = 0.0
var musica_bajada: bool = false
var tween_musica: Tween
var sombras_con_flecha: Array = []
var vacio_invocado: bool = false
var elian: Node2D
var jugador: Node2D


func _ready() -> void:
	if is_instance_valid(elian):
		elian.set("projectile_duration", DURACION_ORBE_DE_ELIAN)
	_dejar_pasar_proyectiles_por_los_puentes()
	var bendicion_de_luto := BendicionDeLuto.new()
	bendicion_de_luto.jugador = jugador
	add_child(bendicion_de_luto)


## Los orbes de Elián solo chocan con las paredes de madera: los puentes (y sus
## restos rotos) los dejan pasar. Los demás proyectiles y Lino siguen chocando.
func _dejar_pasar_proyectiles_por_los_puentes() -> void:
	var capas := get_parent().get_node_or_null("TileMapLayers")
	if not capas:
		return
	# Copia propia de cada juego de tablones: el original lo usan otros niveles.
	var copias: Dictionary = {}
	for capa in capas.get_children():
		var tablones := capa as TileMapLayer
		if not tablones or not tablones.tile_set:
			continue
		var original: TileSet = tablones.tile_set
		if not original.resource_path.ends_with(TERMINACION_DE_LOS_PUENTES):
			continue
		if not copias.has(original):
			var copia: TileSet = original.duplicate()
			if copia.get_physics_layers_count() > 0:
				copia.set_physics_layer_collision_layer(0, CAPA_SOLO_JUGADOR | CAPA_DE_LOS_PUENTES)
			copias[original] = copia
		tablones.tile_set = copias[original]


## La niebla del prado de Lázaro se deshace poco a poco y desaparece.
func disipar_niebla(duracion: float = DURACION_DISIPAR_NIEBLA) -> void:
	var niebla := get_parent().get_node_or_null("Niebla/ColorRectNeblina") as ColorRect
	if not niebla or not niebla.visible:
		return
	var material_niebla := niebla.material as ShaderMaterial
	if not material_niebla:
		niebla.hide()
		return
	var color: Color = material_niebla.get_shader_parameter("fog_color")
	var disipar := create_tween()
	disipar.tween_method(
		func(opacidad: float) -> void:
			material_niebla.set_shader_parameter("fog_color", Color(color, opacidad)),
		color.a,
		0.0,
		duracion
	)
	disipar.tween_callback(niebla.hide)


func _exit_tree() -> void:
	# El material del mundo se comparte con los otros niveles.
	if material_mundo:
		material_mundo.set_shader_parameter("onda_tiempo", -1.0)
	restaurar_musica()


## El color vuelve a Lino poco a poco, con dos destellos suaves, en vez de
## cambiar de golpe. [param poner_gris] es la función que aplica el nivel de gris.
func recuperar_color(poner_gris: Callable, sprite: CanvasItem, de: float, a: float) -> void:
	if is_equal_approx(de, a):
		return
	var vuelta := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	vuelta.tween_method(poner_gris, de, a, DURACION_RECUPERAR_COLOR).set_trans(Tween.TRANS_SINE)
	if not is_instance_valid(sprite):
		return
	var destello := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_loops(2)
	var medio := DURACION_RECUPERAR_COLOR / 4.0
	destello.tween_property(sprite, "self_modulate", BRILLO_AL_RECUPERAR, medio)
	destello.tween_property(sprite, "self_modulate", Color.WHITE, medio)


func _process(delta: float) -> void:
	if onda_tiempo >= 0.0 and material_mundo:
		onda_tiempo += delta
		material_mundo.set_shader_parameter("onda_tiempo", onda_tiempo)

	if material_puerta and material_mundo:
		for parametro in ["saturation", "darkness_factor", "onda_tiempo"]:
			material_puerta.set_shader_parameter(
				parametro, material_mundo.get_shader_parameter(parametro)
			)

	_pausar_a_elian_si_lino_esta_lejos()

	if temblor_amplitud > 0.0:
		temblor_fase += delta * TAU * temblor_frecuencia
		var camara := get_viewport().get_camera_2d()
		if is_instance_valid(camara):
			camara.offset = (
				Vector2(sin(temblor_fase), sin(temblor_fase * 1.37 + 1.0) * 0.7) * temblor_amplitud
			)


## La puerta del centro no se ve mientras Elián siga ahí. Sigue frenando a Lino,
## pero los proyectiles la atraviesan.
func ocultar_puerta() -> void:
	if not is_instance_valid(puerta):
		return
	puerta.visible = false
	var colision := puerta.get_node_or_null("ColliderWhenClosed") as StaticBody2D
	if colision:
		capa_original_puerta = colision.collision_layer
		colision.collision_layer = CAPA_SOLO_JUGADOR


## Cuando Elián desaparece, la puerta aparece poco a poco donde él estaba.
func mostrar_puerta() -> void:
	if not is_instance_valid(puerta) or puerta.visible:
		return
	var colision := puerta.get_node_or_null("ColliderWhenClosed") as StaticBody2D
	if colision:
		colision.collision_layer = capa_original_puerta

	if material_mundo:
		material_puerta = material_mundo.duplicate()
		material_puerta.set_shader_parameter("opacidad", 0.0)
		for nombre in ["DoorClosed", "DoorOpened"]:
			var imagen := puerta.get_node_or_null(nombre) as CanvasItem
			if imagen:
				imagen.material = material_puerta
	puerta.visible = true
	if material_puerta:
		create_tween().tween_method(
			func(valor: float): material_puerta.set_shader_parameter("opacidad", valor),
			0.0,
			1.0,
			DURACION_APARECE_PUERTA
		)


## El último hilo devuelve el color al mundo en ondas lentas que salen de donde estaba.
func iniciar_ondas_de_color() -> void:
	if not material_mundo:
		return
	material_mundo.set_shader_parameter("onda_origen", origen_ondas)
	material_mundo.set_shader_parameter("onda_velocidad", ONDA_VELOCIDAD)
	material_mundo.set_shader_parameter("onda_intervalo", ONDA_INTERVALO)
	material_mundo.set_shader_parameter("onda_cantidad", ONDA_CANTIDAD)
	material_mundo.set_shader_parameter("onda_ancho", ONDA_ANCHO)
	material_mundo.set_shader_parameter("onda_solo_cresta", false)
	material_mundo.set_shader_parameter("onda_tinte_fuerza", 0.0)
	material_mundo.set_shader_parameter("onda_brillo_cresta", ONDA_BRILLO)
	if material_puerta:
		for parametro in ["onda_origen", "onda_velocidad", "onda_intervalo", "onda_cantidad"]:
			material_puerta.set_shader_parameter(
				parametro, material_mundo.get_shader_parameter(parametro)
			)
		material_puerta.set_shader_parameter("onda_ancho", ONDA_ANCHO)
	onda_tiempo = 0.0


## Hace temblar el mundo de forma continua. temblor = (píxeles, vaivenes por segundo).
func temblar(temblor: Vector2, transicion: float = 1.5) -> void:
	temblor_frecuencia = temblor.y
	create_tween().tween_property(self, "temblor_amplitud", temblor.x, transicion)


## Lleva al vacío por lo que le queda de su espiral en el tiempo indicado,
## cubriendo todo a su paso (sin dejar huecos aunque vaya muy rápido).
func lanzar_vacio(duracion: float) -> void:
	invocar_vacio()
	for vacio in vacios:
		if not is_instance_valid(vacio):
			continue
		var caminar: Node = vacio.get_node_or_null("PathWalkBehavior")
		var seguir: Node = vacio.get_node_or_null("NavigationFollowWalkBehavior")
		if not is_instance_valid(caminar) or not is_instance_valid(caminar.walking_path):
			continue
		var camino: Path2D = caminar.walking_path
		vacio_offsets[vacio] = caminar.get_closest_offset_to_character()
		caminar.process_mode = Node.PROCESS_MODE_DISABLED
		if is_instance_valid(seguir):
			seguir.process_mode = Node.PROCESS_MODE_DISABLED

		var avance := create_tween()
		avance.tween_method(
			_mover_vacio.bind(vacio, camino),
			vacio_offsets[vacio],
			camino.curve.get_baked_length(),
			duracion
		)


func _mover_vacio(offset: float, vacio: Node2D, camino: Path2D) -> void:
	if not is_instance_valid(vacio):
		return
	var capa = vacio.get("void_layer")
	var celdas: Dictionary = {}
	var punto: float = vacio_offsets[vacio]
	while capa and punto < offset:
		var posicion: Vector2 = camino.to_global(camino.curve.sample_baked(punto))
		var celda: Vector2i = capa.local_to_map(capa.to_local(posicion))
		celdas[celda] = true
		for vecina in capa.get_surrounding_cells(celda):
			celdas[vecina] = true
		punto += PASO_DEL_VACIO
	if not celdas.is_empty():
		var lista: Array[Vector2i] = []
		lista.assign(celdas.keys())
		capa.consume_cells(lista)
	vacio_offsets[vacio] = offset
	vacio.global_position = camino.to_global(camino.curve.sample_baked(offset))


## En la cinemática final el vacío persigue a Lino, pero no puede atraparlo.
func desactivar_captura() -> void:
	for vacio in vacios:
		if is_instance_valid(vacio):
			var captura := vacio.get_node_or_null("PlayerCaptureArea") as Area2D
			if captura:
				captura.set_deferred("monitoring", false)


## La pantalla se llena de blanco desde el centro de la puerta hacia afuera.
func iris_blanco_desde(capa: CanvasLayer) -> void:
	var pantalla := get_viewport().get_visible_rect().size
	var iris := ColorRect.new()
	iris.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material_iris := ShaderMaterial.new()
	material_iris.shader = SHADER_IRIS
	material_iris.set_shader_parameter("tamano", pantalla)
	material_iris.set_shader_parameter(
		"centro", puerta.get_global_transform_with_canvas().origin + Vector2(0, -40)
	)
	material_iris.set_shader_parameter("radio", 0.0)
	iris.material = material_iris
	capa.add_child(iris)

	var abrir := create_tween()
	(
		abrir
		. tween_method(
			func(valor: float): material_iris.set_shader_parameter("radio", valor),
			0.0,
			pantalla.length() + 120.0,
			DURACION_IRIS
		)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)
	await abrir.finished


## Los proyectiles se agregan a la raíz del nivel y quedaban tapados por los
## puentes: aquí se suben para que siempre se vean.
func subir_proyectil(nodo: Node) -> void:
	if nodo is Node2D and nodo.is_in_group("projectiles"):
		nodo.z_index = maxi(nodo.z_index, Z_PROYECTILES)
		if not nodo.scene_file_path.ends_with(ORBE_DE_ELIAN) and nodo is CollisionObject2D:
			nodo.collision_mask |= CAPA_DE_LOS_PUENTES
		for sombra in sombras_con_flecha:
			if (
				is_instance_valid(sombra)
				and sombra.global_position.distance_to(nodo.position) < ALCANCE_DE_LANZAMIENTO
			):
				nodo.set_meta("con_flecha", true)
				break
		# Los demás (las sombras del puente) no rebotan: se deshacen al tocar
		# cualquier pared, para que repelerlos sea predecible.
		if not nodo.has_meta("con_flecha") and nodo.has_signal("body_entered"):
			nodo.body_entered.connect(_deshacer_proyectil.bind(nodo))


func _deshacer_proyectil(_cuerpo: Node, proyectil: Node) -> void:
	if is_instance_valid(proyectil) and proyectil.has_method("explode"):
		proyectil.explode.call_deferred()


## Sin Lino cerca, Elián no dispara: así no llena sus jarrones él solo.
func _pausar_a_elian_si_lino_esta_lejos() -> void:
	if not is_instance_valid(elian) or not is_instance_valid(jugador):
		return
	var reloj := elian.get_node_or_null("Timer") as Timer
	if reloj:
		var lejos: bool = (
			elian.global_position.distance_to(jugador.global_position) > ALCANCE_DE_ELIAN
		)
		reloj.paused = lejos or jugador.mode != jugador.Mode.USER_CONTROLLED


## El vacío no existe hasta que Elián lo invoca con su risa.
func dormir_vacio() -> void:
	for vacio in vacios:
		if is_instance_valid(vacio):
			vacio.visible = false
			vacio.process_mode = Node.PROCESS_MODE_DISABLED


func invocar_vacio() -> void:
	if vacio_invocado:
		return
	vacio_invocado = true
	for vacio in vacios:
		if not is_instance_valid(vacio):
			continue
		var caminar: Node = vacio.get_node_or_null("PathWalkBehavior")
		if is_instance_valid(caminar) and caminar.get("speeds"):
			caminar.speeds = caminar.speeds.duplicate()
			caminar.speeds.walk_speed = VELOCIDAD_VACIO
		vacio.visible = true
		vacio.process_mode = Node.PROCESS_MODE_INHERIT


## Punto medio entre los vacíos, para que la cámara los muestre a la vez.
func _centro_de_los_vacios() -> Variant:
	var suma := Vector2.ZERO
	var cantidad: int = 0
	for vacio in vacios:
		if is_instance_valid(vacio):
			suma += vacio.global_position
			cantidad += 1
	return suma / cantidad if cantidad > 0 else null


## La primera vez que Lino entra a la sala, la cámara va hasta Elián mientras se
## ríe, luego muestra el vacío que acaba de invocar y vuelve. Lino queda quieto
## y a salvo: con el control tomado, el puente no se cae.
func acercamiento_a_elian(
	jugador: Node2D, elian: Node2D, reir: Callable, decir: Callable = Callable()
) -> void:
	jugador.take_control(self)
	jugador.velocity = Vector2.ZERO

	var cam_lino := get_viewport().get_camera_2d()
	var centro_lino: Vector2 = cam_lino.get_screen_center_position()
	var camara := Camera2D.new()
	camara.global_position = centro_lino
	camara.zoom = cam_lino.zoom
	camara.limit_left = cam_lino.limit_left
	camara.limit_right = cam_lino.limit_right
	camara.limit_top = cam_lino.limit_top
	camara.limit_bottom = cam_lino.limit_bottom
	add_child(camara)
	camara.make_current()

	await _mover_camara(camara, elian.global_position, ZOOM_ACERCAMIENTO_ELIAN, TIEMPO_IDA_A_ELIAN)
	reir.call()
	if decir.is_valid():
		decir.call(FRASE_DE_ELIAN_AL_LLEGAR)
	await get_tree().create_timer(TIEMPO_MIRANDO_A_ELIAN).timeout

	invocar_vacio()
	var centro_vacios: Variant = _centro_de_los_vacios()
	if centro_vacios != null:
		await _mover_camara(camara, centro_vacios, ZOOM_MIRANDO_AL_VACIO, TIEMPO_IDA_AL_VACIO)
		await get_tree().create_timer(TIEMPO_MIRANDO_AL_VACIO).timeout

	await _mover_camara(camara, centro_lino, cam_lino.zoom, TIEMPO_VUELTA_A_LINO)
	cam_lino.make_current()
	camara.queue_free()
	get_tree().call_group("projectiles", "remove")
	jugador.return_control(self)


func _mover_camara(camara: Camera2D, destino: Vector2, zoom: Vector2, duracion: float) -> void:
	var viaje := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	viaje.tween_property(camara, "global_position", destino, duracion)
	viaje.tween_property(camara, "zoom", zoom, duracion)
	await viaje.finished


func bajar_musica() -> void:
	var bus: int = AudioServer.get_bus_index(BUS_MUSICA)
	if bus < 0 or musica_bajada:
		return
	musica_bajada = true
	volumen_musica_original = AudioServer.get_bus_volume_db(bus)
	# El diálogo pausa el juego, así que este cambio debe seguir en pausa.
	tween_musica = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween_musica.tween_method(
		func(valor: float): AudioServer.set_bus_volume_db(bus, valor),
		volumen_musica_original,
		volumen_musica_original - BAJADA_MUSICA_DB,
		1.0
	)


func restaurar_musica() -> void:
	var bus: int = AudioServer.get_bus_index(BUS_MUSICA)
	if bus < 0 or not musica_bajada:
		return
	musica_bajada = false
	if is_instance_valid(tween_musica):
		tween_musica.kill()
	AudioServer.set_bus_volume_db(bus, volumen_musica_original)
