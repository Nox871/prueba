# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name GolpesALino
extends Node
## Lo que le pasa a Lino cuando lo golpea un proyectil en los niveles 3.1 y 3.2.
##
## Cada golpe le quita color (se pone gris). Ya gris del todo, el golpe siguiente
## lo deshila. Tras un golpe parpadea y, por un momento, no recibe daño.
## Los orbes de Elián quitan más color y lo hunden en una sombra al parpadear.

## filtro_gris.gdshader
const FILTRO_GRIS: Shader = preload("uid://gg8y00eu162d")
const FRASE_PRIMER_GOLPE: String = (
	"Si sigo cargando con culpa ajena…\n" + "creo que no podré recuperarte, Manchitas..."
)
## Cuánto gris agrega cada golpe. Con 1.0 Lino queda totalmente gris.
const DANO_PROYECTIL: float = 0.25
## Los orbes de Elián lo deshilan al tercer golpe.
const DANO_ORBE_ELIAN: float = 1.0 / 3.0
const ORBE_ELIAN: String = "boss_projectile.tscn"
const TIEMPO_INVULNERABLE: float = 2.0
## Golpe de una sombra: Lino alterna entre el color que tenía y el que le queda.
const BRILLO_INVULNERABLE := Color(1.5, 1.5, 1.5, 1.0)
const TENUE_INVULNERABLE := Color(1.0, 1.0, 1.0, 0.4)
## Golpe de Elián: Lino se hunde en una sombra gris, más lenta y pesada.
const SOMBRA_DE_ELIAN := Color(0.45, 0.4, 0.6, 0.85)
const PULSO_DE_ELIAN: float = 0.4

## Cuánto gris tiene Lino (puede pasar de 1.0: ahí el siguiente golpe lo deshila).
var gris: float = 0.0
## Mientras es true, los proyectiles se deshacen al tocar a Lino sin dañarlo.
var protegido: bool = false

var _jugador: Player
var _sprite: AnimatedSprite2D
var _hitbox: Area2D
var _panel_pensamiento: Control
var _material := ShaderMaterial.new()
var _invulnerable: bool = false
var _deshilado: bool = false
var _primer_golpe_recibido: bool = false


func _init(jugador: Player, panel_pensamiento: Control = null) -> void:
	_jugador = jugador
	_panel_pensamiento = panel_pensamiento
	_sprite = jugador.get_node("%PlayerSprite")
	_hitbox = jugador.get_node("PlayerHarm/HitBox")


func _ready() -> void:
	_material.shader = FILTRO_GRIS
	_sprite.material = _material
	_sprite.sprite_frames.set_animation_loop("defeated", false)
	_hitbox.body_entered.connect(_al_recibir_proyectil)


func poner_gris(nivel: float) -> void:
	_material.set_shader_parameter("nivel_gris", nivel)


## Gris que se ve en Lino (de 0 a 1).
func gris_visible() -> float:
	return clampf(gris, 0.0, 1.0)


## Ningún proyectil vuelve a tocar a Lino (para las cinemáticas finales).
func proteger_para_siempre() -> void:
	protegido = true
	_hitbox.set_deferred("monitoring", false)
	_hitbox.set_deferred("monitorable", false)


func _al_recibir_proyectil(cuerpo: Node2D) -> void:
	if not cuerpo.is_in_group("projectiles") or _deshilado:
		return
	cuerpo.call_deferred("queue_free")
	if _invulnerable or protegido:
		return

	var es_orbe_elian := cuerpo.scene_file_path.ends_with(ORBE_ELIAN)
	var gris_anterior := gris_visible()
	gris += DANO_ORBE_ELIAN if es_orbe_elian else DANO_PROYECTIL
	poner_gris(gris_visible())

	if not _primer_golpe_recibido and is_instance_valid(_panel_pensamiento):
		_primer_golpe_recibido = true
		_panel_pensamiento.mostrar_pensamiento(FRASE_PRIMER_GOLPE)

	# Un orbe de Elián lo deshila en cuanto queda gris del todo; un proyectil
	# normal, en el golpe siguiente.
	var se_deshila := gris >= 0.999 if es_orbe_elian else gris > 1.001
	if se_deshila:
		_deshilado = true
		proteger_para_siempre()
		_jugador.defeat(false)
	else:
		_parpadear(gris_anterior, gris_visible(), es_orbe_elian)


## En el parpadeo se ve cómo Lino pierde el color, distinto según quién lo golpeó.
func _parpadear(gris_anterior: float, gris_nuevo: float, es_orbe_elian: bool) -> void:
	_invulnerable = true
	var parpadeo := create_tween()
	if es_orbe_elian:
		var medio := PULSO_DE_ELIAN / 2.0
		parpadeo.set_loops(int(TIEMPO_INVULNERABLE / PULSO_DE_ELIAN))
		parpadeo.tween_method(poner_gris, gris_nuevo, 1.0, medio)
		parpadeo.parallel().tween_property(_sprite, "self_modulate", SOMBRA_DE_ELIAN, medio)
		parpadeo.tween_method(poner_gris, 1.0, gris_nuevo, medio)
		parpadeo.parallel().tween_property(_sprite, "self_modulate", Color.WHITE, medio)
	else:
		parpadeo.set_loops(int(TIEMPO_INVULNERABLE / 0.2))
		parpadeo.tween_callback(poner_gris.bind(gris_anterior))
		parpadeo.tween_property(_sprite, "self_modulate", BRILLO_INVULNERABLE, 0.1)
		parpadeo.tween_callback(poner_gris.bind(gris_nuevo))
		parpadeo.tween_property(_sprite, "self_modulate", TENUE_INVULNERABLE, 0.1)
	await get_tree().create_timer(TIEMPO_INVULNERABLE).timeout
	parpadeo.kill()
	poner_gris(gris_nuevo)
	_sprite.self_modulate = Color.WHITE
	_invulnerable = false
