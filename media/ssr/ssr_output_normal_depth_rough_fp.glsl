#version 410

layout(location = 0) in vec3 in_normal_vs;
layout(location = 1) in float in_depth_ndc;
layout(location = 2) in float in_roughness;
layout(location = 3) in vec4 in_position_vs; // Debug

out vec4 out_fragment_color;

void main() {
    // FIXME: z is inverted in view space, +z goes behind the camera, -z is what we see in front of us
    // FIXME: x is also inverted in view space, +x is left, -x is right
    out_fragment_color = vec4(in_normal_vs.xy, in_depth_ndc, in_position_vs.z);
}