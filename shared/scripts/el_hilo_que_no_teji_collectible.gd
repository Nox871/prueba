# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
@tool
class_name StealthCollectible extends Node2D

# Imagen del hilo en el suelo según su tipo. Reemplaza la imagen global del
# InventoryItem solo en esta StoryQuest.
const TEXTURA_POR_TIPO: Dictionary = {
	InventoryItem.ItemType.MEMORY: preload("uid://o88v5s43wgiu"),  # fragmento_hilo_verde.png
	InventoryItem.ItemType.IMAGINATION: preload("uid://lw852yagnv86"),  # fragmento_hilo_amarillo.png
	InventoryItem.ItemType.SPIRIT: preload("uid://bhuboc30gq5k0"),  # fragmento_hilo_rojo.png
}
# Color del brillo que rodea al hilo, para que se note desde lejos.
const COLOR_BRILLO_POR_TIPO: Dictionary = {
	InventoryItem.ItemType.MEMORY: Color(0.55, 1.0, 0.6),
	InventoryItem.ItemType.IMAGINATION: Color(1.0, 0.9, 0.45),
	InventoryItem.ItemType.SPIRIT: Color(1.0, 0.5, 0.45),
}
# El hilo del perdón: blanco, sin teñir. Su halo recorre los colores de los otros
# tres hilos y late como un corazón, más rápido cuando Lino se acerca.
const TEXTURA_PERDON: Texture2D = preload("uid://btbo57cbklfhs")  # fragmento_hilo_blanco.png
const COLORES_AURA_PERDON: Array[Color] = [
	Color(0.55, 1.0, 0.6),
	Color(1.0, 0.9, 0.45),
	Color(1.0, 0.5, 0.45),
]
const SEGUNDOS_POR_COLOR: float = 2.5
const ESCALA_AURA_PERDON: float = 1.8
const LATIDOS_POR_SEGUNDO_LEJOS: float = 0.5
const LATIDOS_POR_SEGUNDO_CERCA: float = 1.3
const DISTANCIA_LATIDO_CERCA: float = 120.0
const DISTANCIA_LATIDO_LEJOS: float = 700.0
const ALTURA_FLOTANDO: float = 6.0
## Tamaño de los fragmentos de hilo en el suelo (1 = tamaño del dibujo).
const ESCALA_HILO: float = 0.8
## El hilo blanco se dibujó al doble de tamaño: es el único más grande que los otros.
const ESCALA_HILO_DEL_PERDON: float = 0.62
const DURACION_VAIVEN: float = 1.2

## Texturas ya achicadas, para no repetir el trabajo con cada hilo.
static var texturas_achicadas: Dictionary = {}

## Overworld collectible that can be interacted with. When a player interacts
## with it, an [InventoryItem] is added to the [Inventory]

## Wether the collectible can be seen or collected. This allows the collectible
## to be placed in the scene even when some condition has to be met for it to
## appear.
@export var revealed: bool = true:
	set(new_value):
		revealed = new_value
		_update_based_on_revealed()

## If provided, switch to this scene after collecting and possibly displaying a dialogue.
@export_file("*.tscn") var next_scene: String

## [InventoryItem] provided by this collectible when interacted with.
@export var item: InventoryItem:
	set = _set_item

## Actívalo solo en el último hilo (el del perdón): usa el hilo blanco y un aura
## distinta a la de los demás.
@export var es_hilo_del_perdon: bool = false:
	set(new_value):
		es_hilo_del_perdon = new_value
		if sprite_2d:
			sprite_2d.texture = _textura_del_hilo()

@export_category("Dialogue")
## Si está activado, congela el tiempo mientras se lee el texto.
@export var pause_game_during_dialogue: bool = false

## Si está activado, el jugador no puede adelantar el diálogo.
## Usar solo con diálogos que avanzan solos con [next=...].
@export var bloquear_salto_dialogo: bool = false

## If provided, this dialogue will be displayed after the player collects this item.
@export var collected_dialogue: DialogueResource:
	set(new_value):
		collected_dialogue = new_value
		notify_property_list_changed()

## The dialogue title from where [member collected_dialogue] will start.
@export var dialogue_title: StringName = ""

var brillo: Sprite2D
var animacion_brillo: Tween
var fase_latido: float = 0.0
var tiempo_aura: float = 0.0

@onready var interact_area: InteractArea = $InteractArea
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var appear_sound: AudioStreamPlayer = %AppearSound
@onready var physical_collider: CollisionShape2D = $StaticBody2D/CollisionShape2D


func _validate_property(property: Dictionary) -> void:
	match property.name:
		"dialogue_title":
			if not collected_dialogue:
				property.usage |= PROPERTY_USAGE_READ_ONLY


func _get_configuration_warnings() -> PackedStringArray:
	if not item:
		return ["item property must be set"]
	return []


func _set_item(new_value: InventoryItem) -> void:
	item = new_value

	if sprite_2d:
		sprite_2d.texture = _textura_del_hilo()

	if interact_area:
		interact_area.action_text = "Collect " + item.type_name() if item else "Collect"

	update_configuration_warnings()


func _ready() -> void:
	_set_item(item)
	_update_based_on_revealed()
	sprite_2d.modulate = Color.WHITE if revealed else Color.TRANSPARENT

	if Engine.is_editor_hint():
		return

	interact_area.interaction_started.connect(self._on_interacted)
	_brillar_y_flotar()


func _process(delta: float) -> void:
	if not es_hilo_del_perdon or not is_instance_valid(brillo) or not brillo.visible:
		return

	tiempo_aura += delta
	var paso := tiempo_aura / SEGUNDOS_POR_COLOR
	var indice := int(paso) % COLORES_AURA_PERDON.size()
	var siguiente := (indice + 1) % COLORES_AURA_PERDON.size()
	var color := COLORES_AURA_PERDON[indice].lerp(COLORES_AURA_PERDON[siguiente], fmod(paso, 1.0))

	var cercania := 0.0
	var lino := get_tree().get_first_node_in_group("player") as Node2D
	if lino:
		var distancia := global_position.distance_to(lino.global_position)
		cercania = 1.0 - smoothstep(DISTANCIA_LATIDO_CERCA, DISTANCIA_LATIDO_LEJOS, distancia)
	fase_latido += delta * lerpf(LATIDOS_POR_SEGUNDO_LEJOS, LATIDOS_POR_SEGUNDO_CERCA, cercania)

	# Dos golpes seguidos y una pausa, como un corazón.
	var t := fmod(fase_latido, 1.0)
	var latido := exp(-pow((t - 0.12) / 0.07, 2.0)) + 0.6 * exp(-pow((t - 0.34) / 0.08, 2.0))

	color.a = 0.4 + 0.4 * latido
	brillo.modulate = color
	brillo.scale = Vector2.ONE * ESCALA_AURA_PERDON * (1.0 + 0.2 * latido)


## Make the collectible appear
func reveal() -> void:
	revealed = true
	appear_sound.play()
	animation_player.play("reveal")
	await animation_player.animation_finished


## When interacted with, the collectible will display a brief animation
## and when that finishes, a new [InventoryItem] will be added to the
## [GameState] and the interaction will have ended.
func _on_interacted(player: Player, _from_right: bool) -> void:
	_detener_brillo()
	z_index += 1
	animation_player.play("collected")
	await animation_player.animation_finished

	# Si Lino se deshiló y vuelve a recogerlo, no se cuenta dos veces.
	var escena := get_tree().current_scene
	var id_hilo := escena.scene_file_path + "::" + str(escena.get_path_to(self))
	if not ElHiloQueNoTejiState.hilos_contados.has(id_hilo):
		GameState.quest.inventory.add_collected_item(item)
	ElHiloQueNoTejiState.recolectar_hilo(id_hilo)
	ElHiloQueNoTejiState.guardar_ultimo_hilo(escena.scene_file_path, global_position)

	# Una onda del color del hilo sale de donde estaba. El hilo del perdón tiene las suyas,
	# más grandes, que lanza el nivel.
	var saturacion := escena.find_child("SaturacionManager", true, false)
	if not es_hilo_del_perdon and saturacion and saturacion.has_method("onda_de_hilo"):
		var color: Color = (
			COLOR_BRILLO_POR_TIPO.get(item.type, Color.WHITE) if item else Color.WHITE
		)
		saturacion.onda_de_hilo(global_position, color)

	if collected_dialogue:
		if pause_game_during_dialogue:
			get_tree().paused = true

		var bloqueo: BloqueoSaltoDialogo = null
		if bloquear_salto_dialogo:
			bloqueo = BloqueoSaltoDialogo.new(pause_game_during_dialogue)
			get_tree().current_scene.add_child(bloqueo)

		var balloon = DialogueManager.show_dialogue_balloon(
			collected_dialogue, dialogue_title, [self, player]
		)

		# Este globo debe seguir funcionando con el juego en pausa.
		if pause_game_during_dialogue and balloon:
			balloon.process_mode = Node.PROCESS_MODE_ALWAYS

		await DialogueManager.dialogue_ended

		if bloqueo:
			bloqueo.queue_free()

		if pause_game_during_dialogue:
			get_tree().paused = false

	interact_area.end_interaction()
	queue_free()

	if next_scene:
		GameState.set_challenge_start_scene(next_scene)
		SceneSwitcher.change_to_file_with_transition(next_scene)


## Un halo suave que pulsa detrás del hilo y un vaivén lento hacia arriba y abajo.
func _brillar_y_flotar() -> void:
	var gradiente := Gradient.new()
	gradiente.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	gradiente.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var textura := GradientTexture2D.new()
	textura.gradient = gradiente
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(0.5, 0.0)
	textura.width = 128
	textura.height = 128

	var material_suma := CanvasItemMaterial.new()
	material_suma.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	brillo = Sprite2D.new()
	brillo.texture = textura
	brillo.material = material_suma
	brillo.show_behind_parent = true
	brillo.modulate = COLOR_BRILLO_POR_TIPO.get(item.type, Color.WHITE) if item else Color.WHITE
	brillo.modulate.a = 0.5
	sprite_2d.add_child(brillo)

	if es_hilo_del_perdon:
		return

	animacion_brillo = create_tween().set_loops().set_parallel(true)
	for nodo_y_propiedad in [[sprite_2d, "offset:y"], [brillo, "position:y"]]:
		var nodo: Node = nodo_y_propiedad[0]
		var propiedad: String = nodo_y_propiedad[1]
		(
			animacion_brillo
			. tween_property(nodo, propiedad, -ALTURA_FLOTANDO, DURACION_VAIVEN)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			animacion_brillo
			. tween_property(nodo, propiedad, 0.0, DURACION_VAIVEN)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
			. set_delay(DURACION_VAIVEN)
		)
	animacion_brillo.tween_property(brillo, "modulate:a", 0.25, DURACION_VAIVEN).set_trans(
		Tween.TRANS_SINE
	)
	(
		animacion_brillo
		. tween_property(brillo, "modulate:a", 0.5, DURACION_VAIVEN)
		. set_trans(Tween.TRANS_SINE)
		. set_delay(DURACION_VAIVEN)
	)


func _detener_brillo() -> void:
	if animacion_brillo:
		animacion_brillo.kill()
	sprite_2d.offset.y = 0.0
	if is_instance_valid(brillo):
		brillo.hide()


func _textura_del_hilo() -> Texture2D:
	if not item:
		return null
	if es_hilo_del_perdon:
		return _achicar(TEXTURA_PERDON, ESCALA_HILO_DEL_PERDON)
	return _achicar(TEXTURA_POR_TIPO.get(item.type, item.get_world_texture()), ESCALA_HILO)


## Devuelve la textura a menor tamaño. Se achica la imagen (y no el sprite)
## porque las animaciones de aparecer y recoger le cambian la escala al sprite.
static func _achicar(textura: Texture2D, escala: float) -> Texture2D:
	if not textura or is_equal_approx(escala, 1.0):
		return textura
	var clave := "%s@%s" % [textura.resource_path, escala]
	if texturas_achicadas.has(clave):
		return texturas_achicadas[clave]
	var imagen := textura.get_image()
	if not imagen:
		return textura
	if imagen.is_compressed():
		imagen.decompress()
	var ancho := maxi(int(round(imagen.get_width() * escala)), 1)
	var alto := maxi(int(round(imagen.get_height() * escala)), 1)
	imagen.resize(ancho, alto, Image.INTERPOLATE_NEAREST)
	var achicada := ImageTexture.create_from_image(imagen)
	texturas_achicadas[clave] = achicada
	return achicada


func _update_based_on_revealed() -> void:
	if interact_area:
		interact_area.disabled = not revealed
	if sprite_2d:
		sprite_2d.visible = revealed
	if physical_collider:
		physical_collider.disabled = not revealed
