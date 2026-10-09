# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name Retejido
extends RefCounted
## Hace aparecer o desaparecer una capa de tiles con el efecto de "retejido" de
## Threadbare (el brillo dorado con trama de tela de world_rewoven.gdshader), el
## mismo que usan las cercas y barreras que se activan con una palanca.
##
## Uso:
##     Retejido.aparecer(puente)
##     Retejido.desaparecer(puente_roto)

## world_rewoven.gdshader
const SHADER: Shader = preload("uid://dui35fhf12sp5")
## fabric_texture.png
const TRAMA_DE_TELA: Texture2D = preload("uid://drlsbgxh5e6vv")
const DURACION: float = 3.0
## Para quitar de en medio algo que estorba (un puente roto) sin que desaparezca de golpe.
const DURACION_BREVE: float = 0.5
const META_TINTE: StringName = &"retejido_tinte_original"
## Sonido de cada franja de puente al tejerse o deshacerse. Basta con poner un
## archivo con este nombre para que suene.
const RUTA_SONIDO_TABLON: String = (
	"res://scenes/quests/story_quests/el_hilo_que_no_teji/shared/assets/sounds/enviroment/"
	+ "puente_tablon.wav"
)
## Crujido y caída de un puente entero, una sola vez (cinemática del nivel 2).
const RUTA_SONIDO_CAIDA: String = (
	"res://scenes/quests/story_quests/el_hilo_que_no_teji/shared/assets/sounds/enviroment/"
	+ "puente_cae.wav"
)
## El golpe de tablón se repite muchas veces seguidas: va más bajo.
const VOLUMEN_TABLON_DB: float = -7.0


## Muestra la capa tejiéndola de un extremo al otro: de arriba hacia abajo si es
## más alta que ancha, y de derecha a izquierda si es más ancha que alta.
## A mitad del efecto ya se puede pisar.
static func aparecer(capa: TileMapLayer, duracion: float = DURACION) -> void:
	if not is_instance_valid(capa):
		return
	var material_original := capa.material
	var material := _crear_material(capa, 0.0)
	# Al aparecer, lo blanco de la máscara se teje primero: va al revés que al deshacer.
	material.set_shader_parameter("mask_texture", _mascara_en_direccion(-_avance_natural(capa)))
	capa.material = material
	capa.show()
	capa.enabled = true
	var tenia_colision := capa.collision_enabled
	capa.collision_enabled = false

	var animacion := capa.create_tween()
	animacion.tween_property(material, "shader_parameter/progress", 0.5, duracion / 2.0)
	animacion.tween_callback(func() -> void: capa.collision_enabled = tenia_colision)
	animacion.tween_property(material, "shader_parameter/progress", 1.0, duracion / 2.0)
	animacion.tween_callback(_devolver_material.bind(capa, material_original))


## Deshace la capa. Al terminar la apaga, o la borra si [param borrar] es true.
## Con [param avance] (por ejemplo Vector2.DOWN) la capa no se deshace toda a la
## vez: se va deshaciendo en esa dirección, de un extremo al otro.
static func desaparecer(
	capa: TileMapLayer,
	borrar: bool = false,
	duracion: float = DURACION,
	avance: Vector2 = Vector2.ZERO
) -> void:
	if not is_instance_valid(capa):
		return
	var material_original := capa.material
	var material := _crear_material(capa, 1.0)
	if avance != Vector2.ZERO:
		material.set_shader_parameter("mask_texture", _mascara_en_direccion(avance))
	capa.material = material

	var animacion := capa.create_tween()
	animacion.tween_property(material, "shader_parameter/progress", 0.5, duracion / 2.0)
	animacion.tween_callback(func() -> void: capa.collision_enabled = false)
	animacion.tween_property(material, "shader_parameter/progress", 0.0, duracion / 2.0)
	if borrar:
		animacion.tween_callback(capa.queue_free)
	else:
		animacion.tween_callback(
			func() -> void:
				capa.enabled = false
				capa.hide()
				_devolver_material(capa, material_original)
		)


## Teje la capa franja a franja (fila a fila si es vertical, de arriba hacia
## abajo; columna a columna si es horizontal, de derecha a izquierda). Cada
## franja aparece entera con el brillo dorado del retejido y un golpe de tablón.
static func tejer_por_franjas(capa: TileMapLayer, duracion: float = DURACION) -> void:
	if not is_instance_valid(capa):
		return
	var avance := _avance_natural(capa)
	var cantidad := maxi(_franjas(capa, avance).size(), 1)
	var material_original := capa.material
	var material := _crear_material(capa, 0.0)
	material.set_shader_parameter("mask_texture", _mascara_escalonada(-avance, cantidad))
	capa.material = material
	capa.show()
	capa.enabled = true

	var tejido := capa.create_tween()
	tejido.tween_property(material, "shader_parameter/progress", 1.0, duracion)
	tejido.tween_callback(_devolver_material.bind(capa, material_original))

	var franjas := _franjas(capa, avance)
	var pausa := (
		_momento_de_franja(1, cantidad, duracion) - _momento_de_franja(0, cantidad, duracion)
	)
	await capa.get_tree().create_timer(_momento_de_franja(0, cantidad, duracion)).timeout
	for franja in franjas:
		if not is_instance_valid(capa):
			return
		_sonar_tablon(capa, franja)
		await capa.get_tree().create_timer(pausa).timeout
	if tejido.is_valid() and tejido.is_running():
		await tejido.finished


## En qué segundo del tejido aparece la primera de [param celdas]. Sirve para
## quitar a tiempo lo que esté dibujado encima (el trozo de puente roto).
static func momento_en_que_aparecen(
	capa: TileMapLayer, celdas: Array[Vector2i], duracion: float = DURACION
) -> float:
	var franjas := _franjas(capa, _avance_natural(capa))
	for indice in franjas.size():
		for celda in franjas[indice]:
			if celda in celdas:
				return _momento_de_franja(indice, franjas.size(), duracion)
	return duracion


## Segundo en que se ve la franja número [param indice] (la 0 es la primera).
static func _momento_de_franja(indice: int, cantidad: int, duracion: float) -> float:
	var avance := float(indice) / maxf(float(cantidad - 1), 1.0)
	# El 1.15 es lo que el shader estira el recorrido para cubrir su borde.
	return duracion * (avance + 0.08) / 1.15


## Máscara en escalones, uno por franja: cada franja aparece toda a la vez.
## Lo blanco se teje primero; va de blanco a negro en la dirección contraria a
## [param hacia_lo_blanco].
static func _mascara_escalonada(hacia_lo_blanco: Vector2, cantidad: int) -> GradientTexture2D:
	var posiciones := PackedFloat32Array()
	var colores := PackedColorArray()
	for i in cantidad:
		var gris := float(i) / maxf(float(cantidad - 1), 1.0)
		posiciones.append(float(i) / float(cantidad))
		colores.append(Color(gris, gris, gris))
	var degradado := Gradient.new()
	degradado.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	degradado.offsets = posiciones
	degradado.colors = colores
	var direccion := hacia_lo_blanco.normalized()
	var mascara := GradientTexture2D.new()
	mascara.gradient = degradado
	mascara.width = 512 if absf(direccion.x) > absf(direccion.y) else 4
	mascara.height = 4 if absf(direccion.x) > absf(direccion.y) else 512
	mascara.fill_from = Vector2(0.5, 0.5) - direccion * 0.5
	mascara.fill_to = Vector2(0.5, 0.5) + direccion * 0.5
	return mascara


## Deshace la capa franja a franja en la dirección de [param avance]. Al
## terminar la deja apagada, pero entera, para poder volver a tejerla.
static func deshacer_por_franjas(capa: TileMapLayer, duracion: float, avance: Vector2) -> void:
	if not is_instance_valid(capa):
		return
	var direccion := Vector2.DOWN if absf(avance.y) >= absf(avance.x) else Vector2.RIGHT
	if avance.dot(direccion) < 0.0:
		direccion = -direccion
	var franjas := _franjas(capa, direccion)
	var celdas := _guardar_celdas(capa)

	var pausa := duracion / maxf(float(franjas.size()), 1.0)
	for franja in franjas:
		for celda in franja:
			capa.erase_cell(celda)
		_sonar_tablon(capa, franja)
		await capa.get_tree().create_timer(pausa).timeout
		if not is_instance_valid(capa):
			return

	capa.enabled = false
	capa.hide()
	for celda in celdas:
		_poner_celda(capa, celda, celdas)


## Las celdas de la capa agrupadas en franjas, en el orden en que avanza el efecto.
static func _franjas(capa: TileMapLayer, avance: Vector2) -> Array:
	var por_vertical := absf(avance.y) >= absf(avance.x)
	var grupos: Dictionary = {}
	for celda in capa.get_used_cells():
		var clave: int = celda.y if por_vertical else celda.x
		if not grupos.has(clave):
			grupos[clave] = []
		grupos[clave].append(celda)
	var claves := grupos.keys()
	claves.sort()
	if (avance.y if por_vertical else avance.x) < 0.0:
		claves.reverse()
	var franjas: Array = []
	for clave in claves:
		franjas.append(grupos[clave])
	return franjas


static func _guardar_celdas(capa: TileMapLayer) -> Dictionary:
	var celdas: Dictionary = {}
	for celda in capa.get_used_cells():
		celdas[celda] = [
			capa.get_cell_source_id(celda),
			capa.get_cell_atlas_coords(celda),
			capa.get_cell_alternative_tile(celda),
		]
	return celdas


static func _poner_celda(capa: TileMapLayer, celda: Vector2i, celdas: Dictionary) -> void:
	if celdas.has(celda):
		var datos: Array = celdas[celda]
		capa.set_cell(celda, datos[0], datos[1], datos[2])


## Un golpe de tablón por franja, en el lugar de la franja. Usa el archivo de
## RUTA_SONIDO_TABLON si existe; si no, no suena nada.
static func _sonar_tablon(capa: TileMapLayer, franja: Array) -> void:
	if franja.is_empty() or not ResourceLoader.exists(RUTA_SONIDO_TABLON):
		return
	var sonido := AudioStreamPlayer2D.new()
	sonido.stream = load(RUTA_SONIDO_TABLON)
	sonido.bus = &"SFX"
	sonido.max_distance = 4000.0
	sonido.pitch_scale = randf_range(0.92, 1.08)
	sonido.volume_db = VOLUMEN_TABLON_DB
	capa.get_tree().current_scene.add_child(sonido)
	sonido.global_position = capa.to_global(capa.map_to_local(franja[franja.size() / 2]))
	sonido.finished.connect(sonido.queue_free)
	sonido.play()


## Suena una vez, en el centro de la capa, el crujido de un puente que cae.
static func sonar_caida(capa: TileMapLayer) -> void:
	if not is_instance_valid(capa) or not ResourceLoader.exists(RUTA_SONIDO_CAIDA):
		return
	var sonido := AudioStreamPlayer2D.new()
	sonido.stream = load(RUTA_SONIDO_CAIDA)
	sonido.bus = &"SFX"
	sonido.max_distance = 4000.0
	capa.get_tree().current_scene.add_child(sonido)
	sonido.global_position = TileMapMaskBounds.get_world_bounds(capa).get_center()
	sonido.finished.connect(sonido.queue_free)
	sonido.play()


static func _crear_material(capa: TileMapLayer, progreso: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("target_canvas_group", false)
	material.set_shader_parameter("fabric_texture", TRAMA_DE_TELA)
	material.set_shader_parameter("progress", progreso)

	var limites := TileMapMaskBounds.get_world_bounds(capa)
	if limites.has_area():
		material.set_shader_parameter("mask_origin", limites.position)
		material.set_shader_parameter("mask_size", limites.size)

	# Mientras dura el efecto la capa no lleva el filtro del mundo: se copia su
	# gris y su oscuridad para que no cambie de tono al empezar ni al terminar.
	var filtro_del_mundo := capa.material as ShaderMaterial
	if filtro_del_mundo:
		var saturacion = filtro_del_mundo.get_shader_parameter("saturation")
		if saturacion != null:
			material.set_shader_parameter("gray_intensity", 1.0 - float(saturacion))
		var oscuridad = filtro_del_mundo.get_shader_parameter("darkness_factor")
		if oscuridad != null and not capa.has_meta(META_TINTE):
			capa.set_meta(META_TINTE, capa.self_modulate)
			var tono := float(oscuridad)
			capa.self_modulate = capa.self_modulate * Color(tono, tono, tono, 1.0)
	return material


## Arriba hacia abajo para capas verticales; derecha a izquierda para horizontales.
static func _avance_natural(capa: TileMapLayer) -> Vector2:
	var limites := TileMapMaskBounds.get_world_bounds(capa)
	return Vector2.DOWN if limites.size.y >= limites.size.x else Vector2.LEFT


## Degradado de negro a blanco en la dirección dada: lo negro se deshace primero.
static func _mascara_en_direccion(avance: Vector2) -> GradientTexture2D:
	var direccion := avance.normalized()
	var degradado := Gradient.new()
	degradado.set_color(0, Color.BLACK)
	degradado.set_color(1, Color.WHITE)
	var mascara := GradientTexture2D.new()
	mascara.gradient = degradado
	mascara.width = 64
	mascara.height = 64
	mascara.fill_from = Vector2(0.5, 0.5) - direccion * 0.5
	mascara.fill_to = Vector2(0.5, 0.5) + direccion * 0.5
	return mascara


static func _devolver_material(capa: TileMapLayer, material_original: Material) -> void:
	capa.material = material_original
	if capa.has_meta(META_TINTE):
		capa.self_modulate = capa.get_meta(META_TINTE)
		capa.remove_meta(META_TINTE)
