// SPDX-FileCopyrightText: The Threadbare Authors
// SPDX-License-Identifier: MPL-2.0
shader_type canvas_item;
// La tela del final: urdimbre y trama de hilos oscuros, en píxeles grandes.
uniform vec2 pantalla = vec2(1280.0, 720.0);
uniform float hebra = 6.0;
uniform vec4 color_urdimbre : source_color = vec4(0.17, 0.12, 0.11, 1.0);
uniform vec4 color_trama : source_color = vec4(0.13, 0.10, 0.10, 1.0);
float azar(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec2 px = floor(UV * pantalla / 2.0) * 2.0;
	vec2 celda = floor(px / hebra);
	vec2 dentro = fract(px / hebra);
	// En cada cruce queda arriba un hilo distinto: urdimbre o trama.
	bool urdimbre = mod(celda.x + celda.y, 2.0) < 1.0;
	float curva = urdimbre ? sin(dentro.y * 3.1416) : sin(dentro.x * 3.1416);
	vec3 base = urdimbre ? color_urdimbre.rgb : color_trama.rgb;
	base *= 0.7 + 0.3 * curva + (azar(celda) - 0.5) * 0.08;
	COLOR = vec4(base, 1.0);
}
