#version 410

uniform sampler2D scene_colour_texture;
uniform sampler2D normal_depth_rough_texture;
uniform mat4 i_projection_matrix;
uniform mat4 projection_matrix;

uniform float far_clip_plane;
uniform vec4 texel_size;

layout(location = 0) in vec2 in_uv;
layout(location = 0) out vec4 out_fragment_color;

vec3 position_vs_from_depth_ndc(vec2 uv, float depth_ndc) {
    vec2 xy_ndc = uv * 2.0 - vec2(1.0);
    vec4 pos_ndc = vec4(xy_ndc, depth_ndc, 1.0);
    vec4 pos_vs = i_projection_matrix * pos_ndc;
    pos_vs.z *= -1.0;
    return pos_vs.xyz / pos_vs.w;
}
vec3 position_ndc_from_vs(vec3 position_vs) {
    vec4 pos_ndc = projection_matrix * vec4(position_vs, 1.0);
    pos_ndc.yz *= -1.0;
    return pos_ndc.xyz / pos_ndc.w;
}
vec2 uv_from_position_ndc(vec3 position_ndc) {
    return vec2(position_ndc.x * 0.5 + 0.5, 0.5 - position_ndc.y * 0.5);
}

const uint MAX_STEPS_BSEARCH = 32;
const float DEPTH_THRESHOLD_VS = 0.005;
vec2 uv_binary_search(vec3 hit_position_vs, vec3 step_vs, out float hit_sampled_depth_vs, out float depth_difference_vs) {
    vec2 hit_uv;
    vec3 original_step_vs = step_vs;
    for (uint i = 0; i < MAX_STEPS_BSEARCH; ++i) {
        step_vs *= 0.5;
        hit_uv = uv_from_position_ndc(position_ndc_from_vs(hit_position_vs));

        hit_sampled_depth_vs = position_vs_from_depth_ndc(
            hit_uv.xy,
            texture(normal_depth_rough_texture, hit_uv).w
        ).z;
        depth_difference_vs = hit_position_vs.z - hit_sampled_depth_vs;
        hit_position_vs += step_vs * sign(depth_difference_vs);
    }
    return uv_from_position_ndc(position_ndc_from_vs(hit_position_vs + original_step_vs));
}

// source: https://andrewphamdotblog.wordpress.com/2019/07/31/screen-space-reflections/
const float MAX_DISTANCE_VS = 100.0;
const uint MAX_STEPS_RAYMARCH = 64;
const float STEP_SIZE_VS = 0.05;
vec2 uv_raymarch(vec3 origin_vs, vec3 direction_vs, vec3 origin_normal_vs, out float hit_sampled_depth_vs, out float depth_difference_vs, out uint steps) {
    vec3 step_vs = direction_vs * STEP_SIZE_VS;
    vec3 hit_position_vs = origin_vs;
    vec2 hit_uv;
    steps = 0;
    for (; steps < MAX_STEPS_RAYMARCH; ++steps) {
        hit_position_vs += step_vs;
        hit_uv = uv_from_position_ndc(position_ndc_from_vs(hit_position_vs));
        hit_sampled_depth_vs = position_vs_from_depth_ndc(
            hit_uv.xy,
            texture(normal_depth_rough_texture, hit_uv).w
        ).z;

        depth_difference_vs = hit_position_vs.z - hit_sampled_depth_vs;
            if (depth_difference_vs < 0.0) {
                vec3 normal_vs = normalize(texture(normal_depth_rough_texture, hit_uv).xyz);
                if (dot(normal_vs, origin_normal_vs) < 0.95) {
                    return uv_binary_search(hit_position_vs, step_vs, hit_sampled_depth_vs, depth_difference_vs);
                }
            }

    }
    return hit_uv;
}

vec3 luminance_from_rgb(vec3 color) {
    return vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
}

void main() {
    vec4 scene_color = texture(scene_colour_texture, in_uv);
    vec4 ndr = texture(normal_depth_rough_texture, in_uv);

    vec3 normal_vs = normalize(ndr.xyz);
    float depth_ndc = ndr.w;
    if (depth_ndc > 0.999) {
        out_fragment_color = scene_color;
        return;
    }

    vec3 position_vs = position_vs_from_depth_ndc(in_uv, depth_ndc);
    vec3 view_direction_vs = normalize(position_vs);
    vec3 reflection_direction_vs = normalize(reflect(view_direction_vs, normal_vs));

    float hit_sampled_depth_vs;
    float depth_difference_vs;
    uint steps;
    vec2 hit_uv = uv_raymarch(position_vs, reflection_direction_vs, normal_vs, hit_sampled_depth_vs, depth_difference_vs, steps);
    if (steps == MAX_STEPS_RAYMARCH) {
        out_fragment_color = scene_color;
        return;
    }
    
    vec4 hit_color = texture(scene_colour_texture, hit_uv);
    vec3 hit_luminance = luminance_from_rgb(hit_color.rgb);
    vec3 scene_luminance = luminance_from_rgb(scene_color.rgb);
    float luminance_factor = clamp(
        dot(hit_luminance, hit_luminance) / (dot(scene_luminance, scene_luminance) + 0.001),
        0.0,
        1.0
    );
    float depth_difference_factor =  1.0 - smoothstep(0.0, DEPTH_THRESHOLD_VS, abs(depth_difference_vs));
    out_fragment_color = mix(
        scene_color,
        hit_color,
        luminance_factor * depth_difference_factor
    );
    // out_fragment_color =
    //     position_ndc_from_vs(vec3(0.0, 0.0, hit_sampled_depth_vs)).zzzz * step(0.5, 1.0 - in_uv.x)
    //     + vec4(depth_ndc * step(0.5, in_uv.x)); 
    // out_fragment_color = vec4(-depth_ndc + position_ndc_from_vs(vec3(0.0, 0.0, hit_sampled_depth_vs)).z);
    out_fragment_color = vec4(hit_uv, 0.0, 1.0);
    // out_fragment_color = texture(scene_colour_texture, uv_from_position_ndc(position_ndc_from_vs()));
    // out_fragment_color = vec4(hit_uv - in_uv, 0.0, 1.0);
    // out_fragment_color = vec4(float(steps) / float(MAX_STEPS_RAYMARCH));
}