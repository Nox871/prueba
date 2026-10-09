// SPDX-FileCopyrightText: The Threadbare Authors
// SPDX-License-Identifier: MPL-2.0
shader_type canvas_item;
// El haz: luz que atraviesa la niebla y cae sobre Lino.
uniform float brillo : hint_range(0.0, 1.0) = 0.0;
// Dónde cae (0-1) y qué tan ancho es arriba y abajo (en ancho de pantalla).
uniform vec2 pie = vec2(0.5, 0.8);
uniform float ancho_arriba = 0.03;
uniform float ancho_abajo = 0.1;
uniform vec4 color_luz : source_color = vec4(1.0, 0.97, 0.9, 1.0);
void fragment() {
	float bajada = clamp(UV.y / pie.y, 0.0, 1.0);
	float ancho = mix(ancho_arriba, ancho_abajo, bajada);
	// Bordes blandos: es luz en la niebla, no un cono recortado.
	float haz = smoothstep(1.0, 0.15, abs(UV.x - pie.x) / ancho);
	haz *= smoothstep(pie.y + 0.03, pie.y - 0.02, UV.y) * mix(0.3, 0.6, bajada);
	vec2 charco = (UV - pie) / vec2(ancho_abajo * 1.25, 0.04);
	float suelo = smoothstep(1.0, 0.3, length(charco)) * 0.75;
	COLOR = vec4(color_luz.rgb, max(haz, suelo) * brillo * 0.6);
}
