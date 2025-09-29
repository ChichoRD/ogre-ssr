#version 410

const vec2 quad_positions_ndc[4] = vec2[](
    vec2(-1.0, -1.0),
    vec2(-1.0,  1.0),
    vec2( 1.0, -1.0),
    vec2( 1.0,  1.0)
);
layout(location = 0) out vec2 out_uv;

void main() {
    vec2 position_ndc = quad_positions_ndc[gl_VertexID];
    gl_Position = vec4(position_ndc, 0.0, 1.0);

    vec2 position_sign_ndc = sign(position_ndc);
    out_uv = (vec2(position_sign_ndc.x, position_sign_ndc.y) + 1.0) * 0.5;
}