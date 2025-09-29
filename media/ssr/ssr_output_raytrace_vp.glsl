#version 410

const vec2 quad_positions_cs[4] = vec2[](
    vec2(-1.0, -1.0),
    vec2(-1.0,  1.0),
    vec2( 1.0, -1.0),
    vec2( 1.0,  1.0)
);
layout(location = 0) out vec2 out_texcoord;

void main() {
    vec2 position_cs = quad_positions_cs[gl_VertexID];
    gl_Position = vec4(position_cs, 0.0, 1.0);

    vec2 position_sign_cs = sign(position_cs);
    out_texcoord = (vec2(position_sign_cs.x, position_sign_cs.y) + 1.0) * 0.5;
}