// SPDX-FileCopyrightText: The Threadbare Authors
// SPDX-License-Identifier: MPL-2.0
shader_type canvas_item;
// La niebla del Deshilado entrando en la pantalla. Usa el mismo ruido que la
// niebla del nivel 1 (el_hilo_que_no_teji_sequence_puzzle.gdshader), para que
// se reconozca como la misma, pero aquí se amontona en nubes y avanza:
// - por la derecha, hasta un frente (modo lateral), o
// - desde los bordes hacia un punto (modo bordes).
// Se usa sobre un ColorRect a pantalla completa.

uniform vec4 color_niebla : source_color = vec4(0.72, 0.74, 0.8, 1.0);
uniform float opacidad_maxima : hint_range(0.0, 1.0) = 0.9;

// --- Modo lateral ---
uniform bool lateral = false;
// Dónde está el frente, en ancho de pantalla (1.3 = fuera, a la derecha).
uniform float frente = 1.3;

// --- Modo bordes ---
// 0 = no hay niebla; 1 = llega hasta radio_minimo del centro.
uniform float intensidad : hint_range(0.0, 1.0) = 0.0;
uniform float radio_minimo = 0.35;
uniform vec2 centro = vec2(0.5);

// Al final la niebla lo cubre todo, sin huecos (0 a 1).
uniform float cubrir : hint_range(0.0, 1.0) = 0.0;

float rand(vec2 coord) {
	return fract(sin(dot(coord, vec2(12.9898, 78.233))) * 43758.5453123);
}

float noise(vec2 coord) {
	vec2 i = floor(coord);
	vec2 f = fract(coord);
	float a = rand(i);
	float b = rand(i + vec2(1.0, 0.0));
	float c = rand(i + vec2(0.0, 1.0));
	float d = rand(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 coord) {
	float value = 0.0;
	float scale = 1.0;
	mat2 magic_rotation = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		value += noise(coord) * scale;
		coord = magic_rotation * coord * 3.5;
		scale *= 0.25;
	}
	return value;
}

void fragment() {
	// Proporción de pantalla, para que las nubes no salgan aplastadas.
	vec2 p = UV * vec2(1.78, 1.0);
	// El viento empuja siempre hacia la izquierda, despacio.
	vec2 viento = vec2(-1.0, -0.05) * TIME;

	// Bultos grandes y redondeados: dan el borde de nube.
	float bultos = fbm(p * 1.6 + viento * 0.05);
	// Jirones más finos dentro de la nube, como en el nivel 1.
	float jirones = fbm(p * vec2(1.4, 3.2) + viento * 0.09 + vec2(3.0, 7.0));

	float masa = 0.0;
	if (lateral) {
		float borde = frente - (bultos - 0.6) * 0.45;
		masa = smoothstep(borde, borde + 0.28, UV.x);
	} else {
		float distancia = length((UV - centro) * vec2(1.78, 1.0)) / 1.02;
		// Cuanto más pequeño es el claro, menos lo deforman las nubes: así queda
		// centrado en lo que rodea y no se va hacia un lado.
		float deformacion = 0.5 * intensidad * clamp(radio_minimo / 0.42, 0.25, 1.0);
		// El borde del claro se ondula con nubes pequeñas: las grandes lo
		// empujarían entero hacia un lado y dejaría de estar centrado.
		float borde_del_claro = fbm(p * 4.5 + viento * 0.05 + vec2(11.0, 5.0));
		float inicio = mix(1.3, radio_minimo, intensidad) - (borde_del_claro - 0.66) * deformacion;
		masa = smoothstep(inicio, inicio + 0.45, distancia) * smoothstep(0.0, 0.2, intensidad);
	}

	// Dentro de la nube la densidad no es pareja: se ven sus volutas.
	float densidad = masa * mix(0.55, 1.0, smoothstep(0.35, 0.95, jirones));
	densidad = mix(densidad, 1.0, cubrir);

	// Un poco más clara donde es más densa, para que tenga volumen.
	vec3 color = color_niebla.rgb * mix(0.82, 1.08, smoothstep(0.4, 1.0, bultos));
	COLOR = vec4(color, densidad * mix(opacidad_maxima, 1.0, cubrir));
}
