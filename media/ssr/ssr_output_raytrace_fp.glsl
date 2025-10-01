#version 410

uniform sampler2D scene_colour_texture;
// TODO: change rough name
uniform sampler2D normal_depth_rough_texture;
uniform mat4 raytrace_i_projection_matrix;
uniform mat4 raytrace_projection_matrix;

// uniform float far_clip_plane;
// uniform float near_clip_plane;

layout(location = 0) in vec2 in_uv;
layout(location = 0) out vec4 out_fragment_color;


const float DISTANCE_MAX_VS = 100.0;
const float THICKNESS_THRESHOLD_VS = 0.1;
const float THICKNESS_RADIUS_VS = 0.05;
const uint STEPS_MAX = 32;

struct normal_depth_sample {
    vec3 normal_vs;
    float depth_ndc01;
};
normal_depth_sample normal_depth_from_sampler(vec2 uv) {
    vec4 nd = texture(normal_depth_rough_texture, uv);
    vec3 normal_vs = normalize(vec3(nd.xy, sqrt(1.0 - dot(nd.xy, nd.xy))));
    float depth_ndc01 = nd.z;
    normal_depth_sample result;
    result.normal_vs = normal_vs;
    result.depth_ndc01 = depth_ndc01;
    return result;
}


vec4 position_cs_from_vs(vec3 position_vs) {
    return raytrace_projection_matrix * vec4(position_vs, 1.0);
}
vec3 position_ndc_from_cs(vec4 position_cs) {
    return position_cs.xyz / position_cs.w;
}
vec3 position_uv_from_ndc(vec3 position_ndc) {
    return vec3(position_ndc.x * 0.5 + 0.5, 0.5 - position_ndc.y * 0.5, position_ndc.z * 0.5 + 0.5);
}

vec3 position_ndc_from_uv(vec3 uv) {
    return vec3(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, uv.z * 2.0 - 1.0);
}
vec3 position_vs_from_ndc(vec3 position_ndc) {
    vec4 pos_vs = raytrace_i_projection_matrix * vec4(position_ndc, 1.0);
    return pos_vs.xyz / pos_vs.w;
}

// source: https://stackoverflow.com/a/46118945
float depth_vs_from_ndc01(float depth_ndc01) {
    float A     = raytrace_projection_matrix[2][2];
    float B     = raytrace_projection_matrix[3][2];
    float z_ndc = 2.0 * depth_ndc01 - 1.0;
    float z_vs = B / (A + z_ndc);
    return -z_vs;
}


// source: https://zznewclear13.github.io/posts/screen-space-reflection-en/
bool ray_thick_hit(float depth_difference_vs, float sample_depth_vs, float thickness_radius_vs, float thickness_threshold_vs) {
    return abs((depth_difference_vs - thickness_radius_vs) / sample_depth_vs) < thickness_threshold_vs;
}

vec4 intersection_raymarch_uv(vec3 origin_vs, vec3 direction_vs, float max_distance_vs) {
    vec3 end_vs = origin_vs + direction_vs * max_distance_vs;
    vec4 origin_cs = position_cs_from_vs(origin_vs);
    vec4 end_cs = position_cs_from_vs(end_vs);

    float k0 = 1.0 / origin_cs.w;
    float k1 = 1.0 / end_cs.w;
    vec3 q0 = origin_cs.xyz;
    vec3 q1 = end_cs.xyz;
    vec2 p0 = (origin_cs.xy * k0);
    vec2 p1 = (end_cs.xy * k1);

    float w = 0.0;
    float dw = 1.0 / float(STEPS_MAX);

    for (uint i = 0; i < STEPS_MAX; ++i) {
        w += dw;

        float k = mix(k0, k1, w);
        vec3 q = mix(q0, q1, w);
        vec2 p = mix(p0, p1, w);

        float ray_depth_ndc = q.z * k;
        vec2 sample_uv = position_uv_from_ndc(vec3(p, ray_depth_ndc)).xy;
        normal_depth_sample nd = normal_depth_from_sampler(sample_uv);
        float sample_depth_ndc01 = nd.depth_ndc01;

        float sample_depth_vs = depth_vs_from_ndc01(sample_depth_ndc01);
        float ray_depth_vs = depth_vs_from_ndc01(ray_depth_ndc * 0.5 + 0.5);

        float depth_difference_vs = ray_depth_vs - sample_depth_vs;
        if (
            depth_difference_vs > 0.0
            && ray_thick_hit(depth_difference_vs, sample_depth_vs, THICKNESS_RADIUS_VS, THICKNESS_THRESHOLD_VS)
        ) {
            return vec4(sample_uv, sample_depth_ndc01, ray_depth_vs);
        }
    }

    return vec4(0.0);
}


vec3 luminance_from_rgb(vec3 color) {
    return vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
}


void main() {
    vec4 scene_color = texture(scene_colour_texture, in_uv);
    vec3 normal_vs;
    float depth_ndc01;
    normal_depth_sample nd = normal_depth_from_sampler(in_uv);
    normal_vs = nd.normal_vs;
    depth_ndc01 = nd.depth_ndc01;
    if (depth_ndc01 > 0.999) {
        out_fragment_color = scene_color;
        return;
    }

    vec3 position_ndc = position_ndc_from_uv(vec3(in_uv, depth_ndc01));
    vec3 position_vs = position_vs_from_ndc(position_ndc);
    vec3 view_direction_vs = normalize(position_vs);
    vec3 reflection_direction_vs = normalize(reflect(view_direction_vs, normal_vs));
    
    vec4 hit_uv = intersection_raymarch_uv(position_vs, reflection_direction_vs, DISTANCE_MAX_VS);
    if (hit_uv.w == 0.0) {
        out_fragment_color = vec4(0.0);
        return;
    }
    
    vec4 hit_color = texture(scene_colour_texture, hit_uv.xy);
    vec3 hit_luminance = luminance_from_rgb(hit_color.rgb);
    vec3 scene_luminance = luminance_from_rgb(scene_color.rgb);
    float luminance_factor = clamp(
        dot(hit_luminance, hit_luminance) / (dot(scene_luminance, scene_luminance) + 0.001),
        0.0,
        1.0
    );
    // float depth_difference_factor =  1.0 - smoothstep(0.0, DEPTH_THRESHOLD_VS, abs(depth_difference_vs));
    out_fragment_color = mix(
        scene_color,
        hit_color,
        1.0
    );
    out_fragment_color = vec4(hit_uv.w / (-100.0));
}