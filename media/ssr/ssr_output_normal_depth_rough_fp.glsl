#version 410

layout(location = 0) in vec3 in_normal_vs;
layout(location = 1) in float in_depth_ndc01;
// layout(location = 2) in float in_depth_vs;

out vec4 out_fragment_color;

void main() {
    out_fragment_color = vec4(in_normal_vs.xy, in_depth_ndc01, 0.0);
}