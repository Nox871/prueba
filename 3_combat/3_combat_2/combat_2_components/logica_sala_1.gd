# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends Node2D
## La sala del Archivero (nivel 3.2).
##
## Dos alas, cada una con dos jarrones y sus sombras: al llenar los dos jarrones
## de un ala aparece su hilo. Con los dos hilos se abre la puerta central, donde
## espera Elián con sus tres jarrones. Al llenarlos se teje el puente hasta el
## último hilo, que lleva a la cinemática final.
## Lo que el jugador ya consiguió se guarda aunque Lino se deshile.

const EfectosFinal = preload("efectos_final.gd")
const BendicionDeLazaro = preload("bendicion_de_lazaro.gd")
const FlechaDeEmpuje = preload("flecha_de_empuje.gd")
const CinematicaFinal = preload("cinematica_final.gd")

## Cada hilo recogido le devuelve a Lino esta parte del color que perdió.
const COLOR_QUE_DEVUELVE_UN_HILO: float = 0.25
## Los sonidos de Elián nunca se cortan en seco: se apagan poco a poco.
const FUNDIDO_SONIDO: float = 0.6
const VOLUMEN_APAGADO: float = -60.0
## La luz de la sala según cuántos hilos se recogieron (0 a 3).
const LUZ_POR_HILOS: Array[Color] = [
	Color(0.4, 0.4, 0.4), Color(0.6, 0.6, 0.6), Color(0.8, 0.8, 0.8), Color(1.0, 1.0, 1.0)
]

const FRASE_PUERTA_CERRADA: String = "El final de la búsqueda... ¿será aquí?"
## Lo que dice el Archivero al llenarse cada jarrón suyo (1.º, 2.º y 3.º).
const FRASES_ARCHIVERO: Array[String] = [
	"¿Crees que ese perro todavía te espera?",
	"Suelta ese collar... Ese perro no va a volver...",
	"Si me detienes... ¿quién la va a seguir recordando?",
]
## elian_laugh.wav
const RISA_ELIAN: AudioStream = preload("uid://b6ar0l4qv6p7k")
## elian_jar01.wav, elian_jar02.wav y elian_jar03.wav: lo que suena al llenarse
## cada jarrón de Elián (dos risas y un gruñido).
const SONIDOS_JARRONES_ELIAN: Array[AudioStream] = [
	preload("uid://thc756f2g4sw"), preload("uid://dl5qpyo38pjaa"), preload("uid://lsgarkg6mjsn")
]

const JARRONES_IZQ: Array[String] = ["FillingBarrel", "FillingBarrel2"]
const JARRONES_DER: Array[String] = ["FillingBarrel3", "FillingBarrel4"]
const JARRONES_BOSS: Array[String] = ["FillingBarrel5", "FillingBarrel6", "FillingBarrel7"]
## Letrero y sombra que desaparecen al completar cada jarrón.
## Los jarrones de Elián no tienen sombra propia.
const LETRERO_Y_ENEMIGO_DE_JARRON: Dictionary = {
	"FillingBarrel": ["Sign5", "ThrowingEnemy"],
	"FillingBarrel2": ["Sign4", "ThrowingEnemy2"],
	"FillingBarrel3": ["Sign6", "ThrowingEnemy4"],
	"FillingBarrel4": ["Sign7", "ThrowingEnemy3"],
	"FillingBarrel5": ["Sign", ""],
	"FillingBarrel6": ["Sign3", ""],
	"FillingBarrel7": ["Sign2", ""],
}

# Lo que se guarda aunque Lino se deshile (se borra al empezar una partida nueva).
static var estado_hilo_izq: bool = false
static var estado_hilo_der: bool = false
static var estado_hilo_central: bool = false
## Jarrones llenados por completo (los llenados a medias no se guardan).
static var jarrones_completados: Dictionary = {}
static var frase_puerta_mostrada: bool = false
## El acercamiento a Elián se ve solo la primera vez; al reaparecer, solo se ríe.
static var acercamiento_elian_visto: bool = false

@export_category("Cinemática final")
@export var dialogo_lazaro: DialogueResource
@export var titulo_dialogo_lazaro: String = "lazaro_final"
@export var escena_outro: PackedScene
@export var nodo_vacio: Node2D

var risa_central_sonada: bool = false
var jarrones_izq_completados: int = 0
var jarrones_der_completados: int = 0
var jarrones_boss_completados: int = 0
var hilos_recogidos: int = 0
var alas_limpiadas: int = 0
var boss_derrotado: bool = false
var panel_archivero: PanelContainer
var sonido_risa: AudioStreamPlayer
var golpes: GolpesALino
var efectos: Node
var bendicion: Node
var pesadilla: Pesadilla

@onready var jugador: Player = $OnTheGround/Player
@onready var sprite_jugador: AnimatedSprite2D = jugador.get_node("%PlayerSprite")
@onready var panel_pensamiento = $HUD/PanelContainer
@onready var canvas_modulate: CanvasModulate = get_node_or_null("CanvasModulate")
@onready var saturacion_manager = get_node_or_null("SaturacionManager")

@onready var puerta_central = $"OnTheGround/Door Enter"
@onready var puerta_salida = $"OnTheGround/LevelExit/Door Exit"
@onready var hilo_izq = $OnTheGround/CollectibleItem_Izq
@onready var hilo_der = $OnTheGround/CollectibleItem_Der
@onready var hilo_central = $OnTheGround/CollectibleItem_Centro

@onready var sombras_izq: Array[Node] = [$OnTheGround/ThrowingEnemy, $OnTheGround/ThrowingEnemy2]
@onready var sombras_der: Array[Node] = [$OnTheGround/ThrowingEnemy3, $OnTheGround/ThrowingEnemy4]
@onready var elian: Node2D = $OnTheGround/ThrowingEnemy8
@onready var jarrones_izq: Array[Node] = [$OnTheGround/FillingBarrel, $OnTheGround/FillingBarrel2]
@onready var jarrones_der: Array[Node] = [$OnTheGround/FillingBarrel3, $OnTheGround/FillingBarrel4]
@onready var jarrones_boss: Array[Node] = [
	$OnTheGround/FillingBarrel5, $OnTheGround/FillingBarrel6, $OnTheGround/FillingBarrel7
]

@onready var lazaro: AnimatedSprite2D = $OnTheGround2/Lazaro
@onready var luto: Node2D = $OnTheGround2/Luto
@onready var bloqueo_puente = $OnTheGround/BloqueoPuente
@onready var particulas_perdon: GPUParticles2D = $OnTheGround/ParticulasPerdon
@onready var puente_boss_final: TileMapLayer = $TileMapLayers/PuenteBossFinal


func _ready() -> void:
	if ElHiloQueNoTejiState.es_partida_nueva_para("combat_2"):
		_olvidar_lo_guardado()

	golpes = GolpesALino.new(jugador, panel_pensamiento)
	add_child(golpes)
	_preparar_efectos()

	var etiquetas: Array[String] = ["Ira"]
	var colores: Dictionary[String, Color] = {"Ira": Color(0.6, 0.6, 0.6)}
	for sombra in get_tree().get_nodes_in_group("throwing_enemy"):
		if is_ancestor_of(sombra):
			sombra.allowed_labels = etiquetas
			sombra.color_per_label = colores

	for jarron in jarrones_izq + jarrones_der + jarrones_boss:
		if is_instance_valid(jarron):
			jarron.completed.connect(_al_completar_jarron.bind(String(jarron.name)))

	if is_instance_valid(puente_boss_final):
		puente_boss_final.enabled = estado_hilo_central

	_restaurar_hilos_recogidos()
	_preparar_voz_del_archivero()
	_restaurar_jarrones_completados()

	_actualizar_color_ambiente()
	if hilos_recogidos >= 2 and is_instance_valid(puerta_central):
		puerta_central.open()
	if hilos_recogidos >= 3 and is_instance_valid(puerta_salida):
		puerta_salida.open()
	if hilos_recogidos < 2 and not frase_puerta_mostrada:
		_crear_aviso_puerta_cerrada()

	add_child(ReaparicionEnHilo.new())
	if is_instance_valid(luto):
		luto.add_child(EfectoFantasma.new())
	ColisionSimple.poner(lazaro)
	pesadilla = Pesadilla.new()
	pesadilla.grupos = [&"throwing_enemy"]
	pesadilla.intensidad_maxima = 0.35
	add_child(pesadilla)
	_preparar_ayudas()


func _olvidar_lo_guardado() -> void:
	estado_hilo_izq = false
	estado_hilo_der = false
	estado_hilo_central = false
	jarrones_completados.clear()
	frase_puerta_mostrada = false
	acercamiento_elian_visto = false
	BendicionDeLazaro.concedida = false
	BendicionDeLazaro.tiempo = 0.0


## La puerta de salida, las ondas de color, el vacío y la música del final.
func _preparar_efectos() -> void:
	efectos = EfectosFinal.new()
	efectos.puerta = puerta_salida
	efectos.vacios = [nodo_vacio, get_node_or_null("OnTheGround/VoidSpreadingEnemy2")]
	efectos.elian = elian
	efectos.jugador = jugador
	if is_instance_valid(elian):
		AnimacionDeElian.aplicar(elian)
	if is_instance_valid(saturacion_manager):
		efectos.material_mundo = saturacion_manager.material_mundo
	if is_instance_valid(hilo_central):
		efectos.origen_ondas = hilo_central.global_position
	add_child(efectos)
	if not estado_hilo_central:
		efectos.ocultar_puerta()
		# El último hilo no devuelve el color de golpe: lo hacen las ondas.
		if is_instance_valid(saturacion_manager):
			saturacion_manager.tope_saturacion_mundo = efectos.SATURACION_ANTES_DEL_ULTIMO_HILO

	child_entered_tree.connect(efectos.subir_proyectil)
	if is_instance_valid(hilo_central) and hilo_central.has_node("InteractArea"):
		hilo_central.get_node("InteractArea").interaction_started.connect(
			efectos.bajar_musica.unbind(2)
		)


## La flecha de empuje y la bendición de Lázaro, que la activa.
func _preparar_ayudas() -> void:
	efectos.sombras_con_flecha = sombras_izq + sombras_der + [elian]
	efectos.dormir_vacio()
	var flecha := FlechaDeEmpuje.new()
	flecha.jugador = jugador
	flecha.jarrones = jarrones_izq + jarrones_der + jarrones_boss
	add_child(flecha)
	bendicion = BendicionDeLazaro.new()
	bendicion.jugador = jugador
	bendicion.dialogo = dialogo_lazaro
	bendicion.flecha = flecha
	bendicion.elian = elian
	add_child(bendicion)


## Al volver al nivel, quita lo que ya se resolvió y deja listos los hilos que faltan.
func _restaurar_hilos_recogidos() -> void:
	if estado_hilo_izq:
		_quitar(sombras_izq + jarrones_izq + [hilo_izq])
		hilos_recogidos += 1
		alas_limpiadas += 1
	elif is_instance_valid(hilo_izq):
		hilo_izq.revealed = false
		hilo_izq.tree_exited.connect(_al_recoger_hilo.bind("izq"))

	if estado_hilo_der:
		_quitar(sombras_der + jarrones_der + [hilo_der])
		hilos_recogidos += 1
		alas_limpiadas += 1
	elif is_instance_valid(hilo_der):
		hilo_der.revealed = false
		hilo_der.tree_exited.connect(_al_recoger_hilo.bind("der"))

	if estado_hilo_central:
		_quitar(jarrones_boss + [elian, hilo_central, lazaro, luto])
		hilos_recogidos += 1
	elif is_instance_valid(hilo_central):
		hilo_central.revealed = false
		hilo_central.tree_exited.connect(_al_recoger_hilo.bind("central"))


func _quitar(nodos: Array) -> void:
	for nodo in nodos:
		if is_instance_valid(nodo):
			nodo.queue_free()


## El Archivero usa un globo como el de los pensamientos de Lino, pero sobre él,
## para que sus frases no detengan la pelea.
func _preparar_voz_del_archivero() -> void:
	if not is_instance_valid(panel_pensamiento) or not is_instance_valid(elian):
		return
	panel_archivero = panel_pensamiento.duplicate()
	panel_pensamiento.get_parent().add_child(panel_archivero)
	panel_archivero.jugador_objetivo = elian
	panel_archivero.distancia_cabeza = 120.0


## Reproduce un sonido de Elián. Si otro seguía sonando, se apaga poco a poco en
## vez de cortarse, y el final de cada sonido también se desvanece.
func _reir(tono: float = 1.0, sonido: AudioStream = RISA_ELIAN) -> void:
	if is_instance_valid(sonido_risa) and sonido_risa.playing:
		var anterior := sonido_risa
		var apagar := anterior.create_tween()
		apagar.tween_property(anterior, "volume_db", VOLUMEN_APAGADO, FUNDIDO_SONIDO)
		apagar.tween_callback(anterior.queue_free)

	sonido_risa = AudioStreamPlayer.new()
	sonido_risa.stream = sonido
	sonido_risa.bus = &"SFX"
	sonido_risa.pitch_scale = tono
	# Sigue sonando aunque el juego se pause para un diálogo.
	sonido_risa.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sonido_risa)
	sonido_risa.play()

	var duracion: float = sonido.get_length() / tono
	var cola := sonido_risa.create_tween()
	cola.tween_interval(maxf(duracion - FUNDIDO_SONIDO, 0.0))
	cola.tween_property(sonido_risa, "volume_db", VOLUMEN_APAGADO, FUNDIDO_SONIDO)
	cola.tween_callback(sonido_risa.queue_free)


func _decir_como_archivero(frase: String) -> void:
	if is_instance_valid(panel_archivero):
		panel_archivero.mostrar_pensamiento(frase)


## Frente a la puerta central, mientras sigue cerrada.
func _crear_aviso_puerta_cerrada() -> void:
	if not is_instance_valid(puerta_central):
		return
	var zona := Area2D.new()
	zona.collision_mask = $OnTheGround/TriggerCentral.collision_mask
	var forma := CollisionShape2D.new()
	var rectangulo := RectangleShape2D.new()
	rectangulo.size = Vector2(260, 160)
	forma.shape = rectangulo
	zona.add_child(forma)
	$OnTheGround.add_child(zona)
	zona.global_position = puerta_central.global_position + Vector2(0, 80)
	zona.body_entered.connect(_al_llegar_a_puerta_cerrada.bind(zona))


func _al_llegar_a_puerta_cerrada(body: Node2D, zona: Area2D) -> void:
	if not body.is_in_group("player"):
		return
	zona.queue_free()
	if frase_puerta_mostrada or hilos_recogidos >= 2:
		return
	frase_puerta_mostrada = true
	if is_instance_valid(panel_pensamiento):
		panel_pensamiento.mostrar_pensamiento(FRASE_PUERTA_CERRADA)


func _actualizar_color_ambiente() -> void:
	if is_instance_valid(canvas_modulate):
		canvas_modulate.color = LUZ_POR_HILOS[mini(hilos_recogidos, LUZ_POR_HILOS.size() - 1)]


func _sacudir_pantalla() -> void:
	var camara := get_viewport().get_camera_2d()
	if not is_instance_valid(camara):
		return
	var sacudir := create_tween()
	for i in 10:
		sacudir.tween_property(
			camara, "offset", Vector2(randf_range(-8, 8), randf_range(-8, 8)), 0.05
		)
	sacudir.tween_property(camara, "offset", Vector2.ZERO, 0.05)


func _al_recoger_hilo(id_hilo: String) -> void:
	if not is_inside_tree():
		return

	match id_hilo:
		"izq":
			estado_hilo_izq = true
		"der":
			estado_hilo_der = true
		"central":
			estado_hilo_central = true

	hilos_recogidos += 1
	_actualizar_color_ambiente()
	var gris_antes := golpes.gris_visible()
	golpes.gris = maxf(golpes.gris - COLOR_QUE_DEVUELVE_UN_HILO, 0.0)
	efectos.recuperar_color(golpes.poner_gris, sprite_jugador, gris_antes, golpes.gris)

	if id_hilo == "central":
		_empezar_cinematica_final()
	elif hilos_recogidos == 2:
		_cinematica_apertura_puerta()


func _empezar_cinematica_final() -> void:
	jugador.take_control(self)
	jugador.velocity = Vector2.ZERO
	# Nada puede dañar ni atrapar a Lino: el vacío casi lo alcanza, pero no lo mata.
	golpes.proteger_para_siempre()
	jugador.set_deferred("collision_layer", 0)
	efectos.desactivar_captura()
	if is_instance_valid(panel_archivero):
		panel_archivero.hide()

	var cinematica := CinematicaFinal.new()
	cinematica.jugador = jugador
	cinematica.elian = elian
	cinematica.lazaro = lazaro
	cinematica.luto = luto
	cinematica.puerta_salida = puerta_salida
	cinematica.particulas_perdon = particulas_perdon
	cinematica.efectos = efectos
	cinematica.saturacion_manager = saturacion_manager
	cinematica.dialogo_lazaro = dialogo_lazaro
	cinematica.titulo_dialogo_lazaro = titulo_dialogo_lazaro
	cinematica.escena_outro = escena_outro
	cinematica.interfaz = [$HUD, $ScreenOverlay]
	cinematica.reir = _reir
	add_child(cinematica)
	cinematica.reproducir()


## Con dos hilos, la cámara va a la puerta central, la puerta tiembla, se abre
## y la cámara vuelve a Lino.
func _cinematica_apertura_puerta() -> void:
	var foco_camara = get_node_or_null("TileMapLayers/FocoCamaraPuerta")
	var destino = foco_camara.global_position if foco_camara else puerta_central.global_position

	jugador.take_control(self)
	jugador.velocity = Vector2.ZERO

	var camara_de_lino := get_viewport().get_camera_2d()
	var camara := Camera2D.new()
	camara.global_position = camara_de_lino.get_screen_center_position()
	camara.zoom = camara_de_lino.zoom
	camara.limit_left = camara_de_lino.limit_left
	camara.limit_right = camara_de_lino.limit_right
	camara.limit_top = camara_de_lino.limit_top
	camara.limit_bottom = camara_de_lino.limit_bottom
	add_child(camara)
	camara.make_current()

	var cinematica := create_tween()
	cinematica.tween_property(camara, "global_position", destino, 1.2).set_trans(Tween.TRANS_SINE)
	cinematica.parallel().tween_property(camara, "zoom", Vector2(1.5, 1.5), 1.2).set_trans(
		Tween.TRANS_SINE
	)
	cinematica.tween_interval(0.2)

	var origen_puerta: Vector2 = puerta_central.position
	for i in 30:
		var fuerza := float(i) / 30.0
		var sacudida := Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)) * fuerza
		cinematica.tween_property(puerta_central, "position", origen_puerta + sacudida, 0.04)
	cinematica.tween_property(puerta_central, "position", origen_puerta, 0.05)
	cinematica.tween_callback(puerta_central.open)
	cinematica.tween_callback(_sacudir_pantalla)

	cinematica.tween_interval(1.2)
	(
		cinematica
		. tween_property(
			camara, "global_position", camara_de_lino.get_screen_center_position(), 0.8
		)
		. set_trans(Tween.TRANS_QUAD)
	)
	cinematica.parallel().tween_property(camara, "zoom", camara_de_lino.zoom, 0.8)
	await cinematica.finished

	camara_de_lino.make_current()
	camara.queue_free()
	jugador.return_control(self)


func _al_completar_jarron(nombre: String) -> void:
	jarrones_completados[nombre] = true
	bendicion.reiniciar_cuenta()
	_aplicar_jarron_completado(nombre, false)


## Al volver a cargar el nivel, deja completos los jarrones que ya se habían llenado.
func _restaurar_jarrones_completados() -> void:
	for nombre in jarrones_completados:
		var jarron = get_node_or_null("OnTheGround/" + nombre)
		if not is_instance_valid(jarron) or jarron.is_queued_for_deletion():
			continue  # Ya se quitó al restaurar un hilo recogido.
		jarron.queue_free()
		_aplicar_jarron_completado(nombre, true)


func _aplicar_jarron_completado(nombre: String, restaurando: bool) -> void:
	for ruta in LETRERO_Y_ENEMIGO_DE_JARRON.get(nombre, []):
		if ruta != "":
			_quitar([get_node_or_null("OnTheGround/" + ruta)])

	if nombre in JARRONES_IZQ:
		jarrones_izq_completados += 1
		if jarrones_izq_completados == JARRONES_IZQ.size():
			_limpiar_ala(sombras_izq, hilo_izq)
	elif nombre in JARRONES_DER:
		jarrones_der_completados += 1
		if jarrones_der_completados == JARRONES_DER.size():
			_limpiar_ala(sombras_der, hilo_der)
	elif nombre in JARRONES_BOSS:
		_al_completar_jarron_boss(restaurando)


## Con los jarrones de un ala llenos, sus sombras se van y aparece su hilo.
func _limpiar_ala(sombras: Array[Node], hilo: Node) -> void:
	alas_limpiadas += 1
	_quitar(sombras)
	get_tree().call_group("projectiles", "remove")
	if is_instance_valid(hilo):
		hilo.dialogue_title = "hilo_1" if alas_limpiadas == 1 else "hilo_2"
		hilo.reveal()


func _al_completar_jarron_boss(restaurando: bool) -> void:
	if boss_derrotado:
		return

	jarrones_boss_completados += 1
	if not restaurando:
		_reir(1.0, SONIDOS_JARRONES_ELIAN[jarrones_boss_completados - 1])
		_decir_como_archivero(FRASES_ARCHIVERO[jarrones_boss_completados - 1])
	if jarrones_boss_completados < JARRONES_BOSS.size():
		return

	boss_derrotado = true
	get_tree().call_group("projectiles", "remove")
	$ScreenOverlay.visible = false
	pesadilla.intensidad_fija = 0.0
	if is_instance_valid(elian):
		AnimacionDeElian.quedarse_en_reposo(elian)
	if not restaurando:
		_sacudir_pantalla()

	_quitar([bloqueo_puente])
	if is_instance_valid(puente_boss_final):
		if restaurando:
			puente_boss_final.enabled = true
		else:
			Retejido.tejer_por_franjas(puente_boss_final)
	if is_instance_valid(hilo_central):
		hilo_central.reveal()


func _on_trigger_central_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or risa_central_sonada:
		return
	risa_central_sonada = true
	if acercamiento_elian_visto or not is_instance_valid(elian):
		_reir()
		efectos.invocar_vacio()
		return
	acercamiento_elian_visto = true
	golpes.protegido = true
	await efectos.acercamiento_a_elian(jugador, elian, _reir, _decir_como_archivero)
	golpes.protegido = false
