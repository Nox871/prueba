# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name Ladrido
extends RefCounted
## Ladridos de Luto/Manchitas con variación, para que no suenen siempre igual:
## cambia el sonido, el tono y el volumen, y a veces ladra dos o tres veces seguidas.
##
## Uso:
##     Ladrido.sonar(self, posicion_global)
##     Ladrido.sonar(self, posicion_global, 1)  # un solo ladrido, sin ráfaga

## bark01.wav ... bark07.wav
const SONIDOS: Array[AudioStream] = [
	preload("uid://48bp1av30u6w"),
	preload("uid://dkioepw7f5ejj"),
	preload("uid://bf1ptifdmuyoc"),
	preload("uid://cdgv2b0mq1not"),
	preload("uid://c7mgvsoj3pid6"),
	preload("uid://bex8i3c57ruar"),
	preload("uid://6vfe7ntcmxjf"),
]
# Cuántos ladridos seguidos: a veces uno, a veces dos o tres (en menos de 3 s).
const PESOS_RAFAGA: Array[float] = [0.45, 0.35, 0.2]
const PAUSA_EN_RAFAGA := Vector2(0.3, 1.1)

static var _ultimo_sonido: AudioStream


## [param maximo] limita cuántos ladridos seguidos puede haber (1 = uno solo).
static func sonar(padre: Node, posicion: Vector2, maximo: int = 3) -> void:
	var cantidad: int = mini(_cantidad_de_ladridos(), maximo)
	for i in cantidad:
		if i > 0:
			await (
				padre
				. get_tree()
				. create_timer(randf_range(PAUSA_EN_RAFAGA.x, PAUSA_EN_RAFAGA.y))
				. timeout
			)
			if not is_instance_valid(padre) or not padre.is_inside_tree():
				return
		_reproducir(padre, posicion)


static func _cantidad_de_ladridos() -> int:
	var tirada := randf()
	for i in PESOS_RAFAGA.size():
		tirada -= PESOS_RAFAGA[i]
		if tirada <= 0.0:
			return i + 1
	return 1


static func _reproducir(padre: Node, posicion: Vector2) -> void:
	var opciones := SONIDOS.filter(func(sonido): return sonido != _ultimo_sonido)
	_ultimo_sonido = opciones.pick_random()

	var jugador := AudioStreamPlayer2D.new()
	jugador.stream = _ultimo_sonido
	jugador.bus = &"SFX"
	jugador.max_distance = 5000.0
	jugador.attenuation = 0.5
	jugador.pitch_scale = randf_range(0.9, 1.1)
	jugador.volume_db = randf_range(-3.0, 0.0)
	padre.add_child(jugador)
	jugador.global_position = posicion
	jugador.finished.connect(jugador.queue_free)
	jugador.play()
