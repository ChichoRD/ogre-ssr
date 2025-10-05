#version 410

uniform vec3 specular;
uniform float shininess;

layout(location = 0) in vec3 in_normal_vs;
layout(location = 1) in vec4 in_position_cs;

out vec4 out_fragment_color;


float luminance_from_rgb(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    float roughness = pow(1.0 - luminance_from_rgb(specular), shininess);
    float depth_ndc01 = in_position_cs.z / in_position_cs.w;
    out_fragment_color = vec4(normalize(in_normal_vs).xy, depth_ndc01, roughness);
}