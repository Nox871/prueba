// SPDX-FileCopyrightText: The Threadbare Authors
// SPDX-License-Identifier: MPL-2.0
shader_type canvas_item;
// Elián como sombra dentro de la niebla: una silueta que se pierde hacia
// abajo, con los ojos encendidos. "detalle" deja entrever su figura.
uniform float sombra : hint_range(0.0, 1.0) = 0.0;
uniform float ojos : hint_range(0.0, 1.0) = 0.0;
uniform float detalle : hint_range(0.0, 1.0) = 0.0;
// Cuánto se ve la mano que sale de la niebla, aunque el resto siga oculto.
uniform float mano : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_sombra : source_color = vec4(0.2, 0.21, 0.27, 1.0);
// Alto de la figura entera y dónde está este dibujo dentro de ella.
uniform float alto = 256.0;
uniform float desplazamiento = 0.0;
// El cuerpo deja libre el sitio de la cabeza, que se dibuja aparte (riendo).
uniform bool recortar_cabeza = false;
uniform sampler2D cabeza : filter_nearest;
uniform vec4 region_cabeza = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 esquina_cabeza = vec2(0.0);
uniform vec2 medida_cabeza = vec2(61.0, 80.0);
varying vec2 lugar;
void vertex() {
	lugar = VERTEX;
}
void fragment() {
	vec4 figura = texture(TEXTURE, UV);
	float presencia = figura.a;
	if (recortar_cabeza) {
		vec2 q = (lugar - esquina_cabeza) / medida_cabeza;
		if (q.x >= 0.0 && q.x <= 1.0 && q.y >= 0.0 && q.y <= 1.0) {
			presencia *= 1.0 - texture(cabeza, region_cabeza.xy + q * region_cabeza.zw).a;
		}
	}
	float luz = dot(figura.rgb, vec3(0.299, 0.587, 0.114));
	float ojo = smoothstep(0.72, 0.85, luz) * presencia;
	// Hacia abajo se deshace en la niebla: no se ve dónde termina.
	float altura = (lugar.y + desplazamiento) / alto + 0.5;
	float cuerpo = smoothstep(0.9, 0.42, altura);
	vec3 color = mix(color_sombra.rgb, mix(color_sombra.rgb, figura.rgb, 0.55), detalle);
	color = mix(color, vec3(0.93, 0.95, 1.0), ojo * ojos);
	// La mano: solo la parte derecha del dibujo, deshecha hacia el brazo y
	// hacia abajo (donde están los libros), para que salga de la nada.
	float zona_mano = smoothstep(38.0, 78.0, lugar.x) * smoothstep(70.0, 44.0, lugar.y);
	// Y por arriba se corta justo sobre los dedos, para que no asomen las astas.
	zona_mano *= smoothstep(-34.0, -28.0, lugar.y);
	float visible = max(sombra * cuerpo, mano * zona_mano);
	COLOR = vec4(color, presencia * max(visible, ojo * ojos));
}
