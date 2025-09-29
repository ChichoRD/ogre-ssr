#version 410

uniform sampler2D scene_colour_texture;
uniform sampler2D normal_depth_rough_texture;
uniform mat4 i_projection_matrix;
uniform mat4 projection_matrix;
uniform float far_clip_plane;

layout(location = 0) in vec2 in_texcoord;

layout(location = 0) out vec4 out_fragment_color;

vec3 position_vs_from_depth_cs(vec2 texcoord, float depth_cs) {
    vec2 xy_cs = texcoord * 2.0 - 1.0;
    vec4 pos_cs = vec4(xy_cs, depth_cs, 1.0);
    vec4 pos_vs = i_projection_matrix * pos_cs;

    // pos_vs.xz *= -1.0;
    // pos_vs.y *= -1.0;
    return pos_vs.xyz / pos_vs.w;
}
vec3 position_cs_from(vec3 position_vs) {
    vec4 pos_cs = projection_matrix * vec4(position_vs, 1.0);
    return pos_cs.xyz / pos_cs.w;
}
vec2 texcoord_from_position_cs(vec3 position_cs) {
    return (position_cs.xy + 1.0) * 0.5;
}

const uint MAX_BSEARCH_STEPS = 32;
const float DEPTH_THRESHOLD_VS = 0.1;
vec2 texcoord_binary_search(vec3 hit_position_vs, vec3 step_vs, out float depth_difference_vs) {
    vec2 hit_texcoord_cs;
    for (int i = 0; i < MAX_BSEARCH_STEPS; ++i) {
        step_vs *= 0.5;
        hit_position_vs += step_vs * sign(depth_difference_vs);
        hit_texcoord_cs = texcoord_from_position_cs(position_cs_from(hit_position_vs));

        float sampled_depth_vs = position_vs_from_depth_cs(vec2(0, 0), texture(normal_depth_rough_texture, hit_texcoord_cs).z).z;
        depth_difference_vs = sampled_depth_vs - hit_position_vs.z;
        if (abs(depth_difference_vs) < DEPTH_THRESHOLD_VS) {
            break;
        }
    }
    return hit_texcoord_cs;
}

const float MAX_DISTANCE_VS = 100.0;
const uint MAX_RAYTRACE_STEPS = 100;
const float STEP_SIZE_VS = 0.05;
vec2 texcoord_raytrace(vec3 origin_vs, vec3 direction_vs, out float depth_difference_vs, out uint steps) {
    vec3 step_vs = direction_vs * STEP_SIZE_VS;
    vec3 hit_position_vs = origin_vs;
    vec2 hit_texcoord_cs;
    steps = 0;
    for (; steps < MAX_RAYTRACE_STEPS; ++steps) {
        hit_position_vs += step_vs;
        hit_texcoord_cs = texcoord_from_position_cs(position_cs_from(hit_position_vs));

        float sampled_depth_vs = position_vs_from_depth_cs(
            hit_texcoord_cs.xy,
            texture(normal_depth_rough_texture, hit_texcoord_cs).z
        ).z;
        depth_difference_vs = sampled_depth_vs - hit_position_vs.z;
        if (sampled_depth_vs + 1.0f > far_clip_plane) {
            continue;
        }
        if (abs(depth_difference_vs) < DEPTH_THRESHOLD_VS) {
            break;
        }
        if (depth_difference_vs < 0.0) {
            return texcoord_binary_search(hit_position_vs, step_vs, depth_difference_vs);
        }
    }
    return hit_texcoord_cs;
}

vec3 luminance_from(vec3 color) {
    return vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
}

void main() {
    vec4 scene_color = texture(scene_colour_texture, in_texcoord);
    vec4 ndr = texture(normal_depth_rough_texture, in_texcoord);

    vec3 normal_vs = normalize(vec3(ndr.xy, sqrt(1.0 - dot(ndr.xy, ndr.xy))));
    float depth_cs = ndr.z;
    // if (depth_cs > 0.9999) {
    //     out_fragment_color = scene_color;
    //     return;
    // }

    // float roughness = ndr.w;
    vec3 luminance = luminance_from(scene_color.rgb);
    float roughness = dot(luminance, luminance);

    vec3 position_vs = position_vs_from_depth_cs(in_texcoord, depth_cs);
    vec3 view_direction_vs = normalize(position_vs);
    vec3 reflect_direction_vs = normalize(reflect(view_direction_vs, normal_vs));

    uint steps;
    float depth_difference_vs;
    vec2 it_texcoord = texcoord_raytrace(position_vs, reflect_direction_vs, depth_difference_vs, steps);
    vec4 it_color = texture(scene_colour_texture, it_texcoord);
    out_fragment_color = mix(it_color, scene_color, 1.0 - smoothstep(0.0, DEPTH_THRESHOLD_VS, (depth_difference_vs)));
    // out_fragment_color = vec4(it_texcoord, 0.0, 1.0);
    // out_fragment_color = vec4(smoothstep(DEPTH_THRESHOLD_VS, 0.0, depth_difference_vs));
    // out_fragment_color = vec4(float(steps) / float(MAX_RAYTRACE_STEPS));
    // out_fragment_color = vec4(reflect_direction_vs.xyz, 1.0);
    // out_fragment_color = vec4(depth_cs);
    // out_fragment_color = ndr;
    out_fragment_color = vec4(normal_vs, 1.0);
    
    // Debug output
    // vec3 positon_cs = position_cs_from(position_vs);
    // vec2 test_texcoord = texcoord_from_position_cs(positon_cs);
    // out_fragment_color =
    //     (scene_color) * 0.0001
    //     + vec4(normal_vs, 1.0) * 0.0001
    //     + vec4(depth_cs * step(0.5, in_texcoord.x)) * 0.0001
    //     + vec4(ndr.a * step(0.5, 1.0 - in_texcoord.x)) * 1.0001
    //     + vec4(in_texcoord, 0.0, 1.0) * 0.0001
    //     + vec4(roughness, roughness, roughness, 1.0) * 0.0001
    //     + vec4(position_vs, 1.0) * 0.0001
    //     + vec4(test_texcoord, 0.0, 1.0) * 0.0001
    //     + vec4(position_vs.z - position_vs_from_depth_cs(vec2(0.0), depth_cs).z) * 0.0001;
}