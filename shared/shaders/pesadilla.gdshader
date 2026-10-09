// SPDX-FileCopyrightText: The Threadbare Authors
// SPDX-License-Identifier: MPL-2.0
shader_type canvas_item;
// Oscuridad de pesadilla que entra por los bordes de la pantalla: no es un
// marco parejo, sino manchas y lenguas irregulares que se mueven, avanzan y
// retroceden, y laten. Se usa sobre un ColorRect a pantalla completa.

uniform float intensidad : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_borde : source_color = vec4(0.015, 0.0, 0.03, 1.0);
// Qué tan adentro llega la oscuridad con la intensidad al máximo (0 = centro).
uniform float radio_minimo : hint_range(0.0, 1.0) = 0.3;
uniform float latidos_por_segundo = 1.1;
// Punto de la pantalla (0 a 1) alrededor del cual se cierra la oscuridad.
uniform vec2 centro = vec2(0.5);

float azar(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 celda = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = azar(celda);
	float b = azar(celda + vec2(1.0, 0.0));
	float c = azar(celda + vec2(0.0, 1.0));
	float d = azar(celda + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float ruido_fino(vec2 p) {
	float total = 0.0;
	float peso = 0.5;
	for (int i = 0; i < 4; i++) {
		total += ruido(p) * peso;
		p = p * 2.03 + vec2(17.0, 9.0);
		peso *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 centrado = UV - centro;
	float distancia = length(centrado) / 0.7071;
	float angulo = atan(centrado.y, centrado.x);

	// Latido doble, como un corazón, más un temblor irregular.
	float t = fract(TIME * latidos_por_segundo);
	float latido = exp(-pow((t - 0.1) / 0.07, 2.0)) + 0.6 * exp(-pow((t - 0.32) / 0.09, 2.0));
	float temblor = ruido(vec2(TIME * 3.1, 4.0)) - 0.5;
	float fuerza = clamp(intensidad * (0.85 + 0.2 * latido + 0.12 * temblor), 0.0, 1.0);

	// Lenguas de sombra: el borde entra más en unas direcciones que en otras, y
	// esas direcciones cambian con el tiempo.
	vec2 direccion = vec2(cos(angulo), sin(angulo));
	float lenguas = ruido_fino(direccion * 2.6 + vec2(TIME * 0.22, -TIME * 0.17));
	float jirones = ruido_fino(UV * 5.5 + vec2(-TIME * 0.35, TIME * 0.28));

	float inicio = mix(1.25, radio_minimo, fuerza);
	inicio -= (lenguas - 0.4) * 0.5 * fuerza;
	float sombra = smoothstep(inicio, inicio + 0.38, distancia + (jirones - 0.5) * 0.3);
	// Manchas sueltas que flotan cerca del borde.
	float manchas = smoothstep(0.62, 0.8, jirones) * smoothstep(inicio - 0.25, inicio + 0.1, distancia);
	sombra = clamp(sombra + manchas * 0.7, 0.0, 1.0);

	COLOR = vec4(color_borde.rgb, sombra * smoothstep(0.0, 0.25, fuerza));
}
