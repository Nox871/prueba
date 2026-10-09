# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
class_name ElHiloQueNoTejiState
extends RefCounted

const MAX_HILOS_MUNDO: int = 9
const PLAYER_SAT_INCREMENT: float = 16.66
const WORLD_SAT_INCREMENT_SMALL: float = 1.875

# Estáticas: sobreviven al cambio de escena.
static var hilos_recogidos: int = 0
static var player_saturation: float = 0.0
static var world_saturation: float = 0.0

# Hilos ya contados (clave: escena + ruta del nodo). Evita contar dos veces
# un hilo que se vuelve a recoger después de morir y reiniciar el nivel.
static var hilos_contados: Dictionary = {}

# Último hilo recogido en cada nivel (clave: ruta de la escena, valor: posición).
# Al deshilarse, Lino vuelve al último hilo del recuerdo en vez de al inicio.
static var ultimo_hilo_por_nivel: Dictionary = {}

# Niveles que ya se cargaron en esta partida. Si un nivel se carga de nuevo,
# es porque Lino se deshiló (lo atraparon, cayó al vacío o lo derrotaron).
static var niveles_visitados: Dictionary = {}

# Cada partida nueva (empezada desde la intro) tiene su propio número. Los niveles
# lo usan para borrar el progreso que guardaron en una partida anterior.
static var numero_partida: int = 0
static var partida_por_nivel: Dictionary = {}

# Veces que Lino se deshiló en cada nivel durante esta partida. Sirve para
# aflojar la dificultad a quien muere muchas veces seguidas.
static var muertes_por_nivel: Dictionary = {}


static func recolectar_hilo(id_hilo: String = "") -> void:
	if id_hilo != "":
		if hilos_contados.has(id_hilo):
			return
		hilos_contados[id_hilo] = true

	if hilos_recogidos < MAX_HILOS_MUNDO:
		hilos_recogidos += 1

		# Lino suma 16.66 % por hilo: con el sexto llega al 100 %.
		player_saturation = clamp(player_saturation + PLAYER_SAT_INCREMENT, 0.0, 100.0)

		if hilos_recogidos < 9:
			world_saturation = clamp(world_saturation + WORLD_SAT_INCREMENT_SMALL, 0.0, 100.0)
		elif hilos_recogidos == 9:
			world_saturation = 100.0


static func guardar_ultimo_hilo(escena: String, posicion: Vector2) -> void:
	ultimo_hilo_por_nivel[escena] = posicion


## Devuelve la posición del último hilo recogido en esa escena, o null si no hay.
static func obtener_ultimo_hilo(escena: String) -> Variant:
	return ultimo_hilo_por_nivel.get(escena)


## Registra que se cargó el nivel. Devuelve true si ya se había cargado antes
## en esta partida, es decir, si es una reaparición y no la primera entrada.
static func registrar_carga_de_nivel(escena: String) -> bool:
	var ya_visitado: bool = niveles_visitados.has(escena)
	niveles_visitados[escena] = true
	return ya_visitado


## Devuelve true la primera vez que el nivel se carga en esta partida.
## Así el nivel sabe que debe borrar lo que guardó en una partida anterior.
static func es_partida_nueva_para(nivel: String) -> bool:
	var es_nueva: bool = partida_por_nivel.get(nivel, -1) != numero_partida
	partida_por_nivel[nivel] = numero_partida
	# Si el nivel se carga otra vez en la misma partida, es que Lino se deshiló.
	muertes_por_nivel[nivel] = 0 if es_nueva else muertes_en(nivel) + 1
	return es_nueva


## Veces que Lino se deshiló en ese nivel en esta partida.
static func muertes_en(nivel: String) -> int:
	return muertes_por_nivel.get(nivel, 0)


## Cuánto se afloja algo por las muertes en un nivel: 1.0 sin muertes, y baja
## [param por_muerte] con cada una, sin pasar de [param minimo].
static func alivio_por_muertes(nivel: String, por_muerte: float, minimo: float) -> float:
	return maxf(1.0 - por_muerte * muertes_en(nivel), minimo)


## Deja el progreso en cero (se llama al empezar una partida nueva).
static func resetear_saturacion() -> void:
	hilos_recogidos = 0
	player_saturation = 0.0
	world_saturation = 0.0
	hilos_contados.clear()
	ultimo_hilo_por_nivel.clear()
	niveles_visitados.clear()
	muertes_por_nivel.clear()
	numero_partida += 1
