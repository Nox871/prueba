// SPDX-FileCopyrightText: The Threadbare Authors
// SPDX-License-Identifier: MPL-2.0
shader_type canvas_item;

// Niebla estirada en filamentos que el viento arrastra hacia la izquierda.
uniform vec4 fog_color : source_color = vec4(0.45, 0.48, 0.52, 0.35);
uniform float speed : hint_range(0.0, 1.0) = 0.12; 
uniform float detail_steps : hint_range(1.0, 6.0) = 4.0;
uniform float thread_shredding : hint_range(0.1, 3.0) = 1.8;
uniform float density : hint_range(0.1, 5.0) = 0.5;

uniform vec2 wind_direction = vec2(-1.0, -0.05); 
uniform float stretch_factor : hint_range(1.0, 10.0) = 5.0; 

varying vec2 world_position;

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

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 stretch = vec2(stretch_factor, 1.0);
	vec2 base_uv = (world_position * 0.002 * density) / stretch;
	
	vec2 wind_1 = wind_direction * (TIME * speed);
	vec2 wind_2 = wind_direction * (TIME * speed * 0.7) + vec2(0.2, 0.5);
	
	float layer1 = fbm(base_uv + wind_1);
	float layer2 = fbm(base_uv * 1.3 + wind_2);
	
	// El contraste alto deja pasillos transparentes entre las rocas.
	float final_shredded_fog = smoothstep(0.55, 0.75, layer1 * layer2 * 1.6);
	
	final_shredded_fog = pow(final_shredded_fog, thread_shredding);
	
	float alpha_mask = final_shredded_fog * fog_color.a;
	
	COLOR = vec4(fog_color.rgb, alpha_mask);
}
