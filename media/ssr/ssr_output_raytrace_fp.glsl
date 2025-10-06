#version 410

uniform sampler2D scene_colour_texture;
uniform sampler2D normal_depth_rough_texture;
uniform mat4 raytrace_i_projection_matrix;
uniform mat4 raytrace_projection_matrix;

uniform float near_clip_plane;
uniform float far_clip_plane;

layout(location = 0) in vec2 in_uv;
layout(location = 0) out vec4 out_fragment_color;


const uint UINT_MAX = 0xffffffffu;
const float INFINITY = 1.0 / 0.0;
const float EPSILON = 0.0001;
const float FAR_MAX_NDC = 1.0 - EPSILON;

const float DISTANCE_MAX_VS = 16.0;
const float THICKNESS_RADIUS_VS = 0.5;

const float ROUGHNESS_POWER             =  0.0;
const float FRESNEL_POWER               =  0.0;
const float LUMINANCE_POWER             =  0.0;
const float FRONT_RAY_DISCARD_POWER     =  0.0;
const float REFLECTION_POWER_BIAS       =  1.0;

const uint STEPS_MAX = 16;
const uint STEPS_BSEARCH_MAX = 8;

const bool FRUSTUM_CLIP_ENABLE = true;
const bool BSEARCH_ENABLE = true;


struct normal_depth_rough_sample {
    vec3 normal_vs;
    float depth_ndc01;
    float roughness;
};
normal_depth_rough_sample normal_depth_rough_from_sampler(vec2 uv) {
    vec4 nd = texture(normal_depth_rough_texture, uv);
    vec3 normal_vs = normalize(vec3(nd.xy, sqrt(1.0 - dot(nd.xy, nd.xy))));
    float depth_ndc01 = nd.z;
    float roughness = nd.w;
    normal_depth_rough_sample result;
    result.normal_vs = normal_vs;
    result.depth_ndc01 = depth_ndc01;
    result.roughness = roughness;
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
// BUG: precission issues compared to full inv matrix multiplication
float depth_vs_from_ndc01(float depth_ndc01) {
    float A     = raytrace_projection_matrix[2][2];
    float B     = raytrace_projection_matrix[3][2];
    float z_ndc = 2.0 * depth_ndc01 - 1.0;
    float z_vs = B / (A + z_ndc);
    return -z_vs;
}


// source: https://zznewclear13.github.io/posts/screen-space-reflection-en/#frustum-clipping
vec3 segment_end_clip_vs_from(vec3 origin_vs, vec3 end_vs, vec2 near_far_clip_distances, vec2 near_plane_half_size) {
    origin_vs.z *= -1.0;
    end_vs.z *= -1.0;

    vec3 dir = end_vs - origin_vs;
    vec3 signDir = sign(dir);

    float nfSlab = signDir.z * (near_far_clip_distances.y - near_far_clip_distances.x) * 0.5f + (near_far_clip_distances.y + near_far_clip_distances.x) * 0.5f;
    float lenZ = (nfSlab - origin_vs.z) / dir.z;
    if (dir.z == 0.0f) lenZ = INFINITY;

    vec2 ss = sign(dir.xy - near_plane_half_size * dir.z) * near_plane_half_size;
    vec2 denom = ss * dir.z - dir.xy;
    vec2 lenXY = (origin_vs.xy - ss * origin_vs.z) / denom;
    if (lenXY.x < 0.0f || denom.x == 0.0f) lenXY.x = INFINITY;
    if (lenXY.y < 0.0f || denom.y == 0.0f) lenXY.y = INFINITY;

    float len = min(min(1.0f, lenZ), min(lenXY.x, lenXY.y));
    vec3 clippedVS = origin_vs + dir * len;

    clippedVS.z *= -1.0;
    return clippedVS;
}
vec3 segment_end_clip_vs(vec3 origin_vs, vec3 end_vs) {
    return segment_end_clip_vs_from(
        origin_vs,
        end_vs,
        vec2(near_clip_plane, far_clip_plane),
        vec2(1.0, 1.0) / vec2(raytrace_projection_matrix[0][0], raytrace_projection_matrix[1][1])
    );
}


vec4 intersection_binary_search_uv(vec4 origin_cs, vec4 end_cs, vec4 origin_front_cs, vec4 end_front_cs, float w, float prev_w) {
    vec2 hit_sample_uv = vec2(0.0);
    float hit_sample_depth_ndc01 = 0.0;
    float hit = 0.0;
    for (uint i = 0; i < STEPS_BSEARCH_MAX; ++i) {
        float mid_w = (w + prev_w) * 0.5;

        vec4 position_cs = mix(origin_cs, end_cs, mid_w);
        vec4 position_front_cs = mix(origin_front_cs, end_front_cs, mid_w);

        float ray_depth_ndc = position_cs.z / position_cs.w;
        float ray_front_depth_ndc = position_front_cs.z / position_front_cs.w;

        vec2 sample_uv = position_uv_from_ndc(vec3(position_cs.xy / position_cs.w, ray_depth_ndc)).xy;
        normal_depth_rough_sample nd = normal_depth_rough_from_sampler(sample_uv);
        float sample_depth_ndc01 = nd.depth_ndc01;
        float sample_depth_ndc = sample_depth_ndc01 * 2.0 - 1.0;

        if (ray_depth_ndc >= sample_depth_ndc) {
            w = mid_w;
            if (ray_front_depth_ndc <= sample_depth_ndc) {
                hit_sample_uv = sample_uv;
                hit_sample_depth_ndc01 = sample_depth_ndc01;
                hit = 1.0;
            } else {
                w = (w + prev_w) * 0.5;
            }
        } else {
            prev_w = mid_w;
        }
    }
    return vec4(hit_sample_uv, hit_sample_depth_ndc01, hit);
}

vec4 intersection_binary_minimization_uv(vec4 origin_cs, vec4 end_cs, vec4 origin_front_cs, vec4 end_front_cs, float min_depth_difference_ndc, float w, float prev_w) {
    vec2 hit_sample_uv = vec2(0.0);
    float hit_sample_depth_ndc01 = 0.0;
    float hit = 0.0;

    for (uint i = 0; i < STEPS_BSEARCH_MAX; ++i) {
        float mid_w = (w + prev_w) * 0.5;

        vec4 position_cs = mix(origin_cs, end_cs, mid_w);
        vec4 position_front_cs = mix(origin_front_cs, end_front_cs, mid_w);

        float ray_depth_ndc = position_cs.z / position_cs.w;
        float ray_front_depth_ndc = position_front_cs.z / position_front_cs.w;

        vec2 sample_uv = position_uv_from_ndc(vec3(position_cs.xy / position_cs.w, ray_depth_ndc)).xy;
        normal_depth_rough_sample nd = normal_depth_rough_from_sampler(sample_uv);
        float sample_depth_ndc01 = nd.depth_ndc01;
        float sample_depth_ndc = sample_depth_ndc01 * 2.0 - 1.0;
        float depth_difference_ndc = ray_depth_ndc - sample_depth_ndc;

        if (depth_difference_ndc >= 0.0 && (depth_difference_ndc) < min_depth_difference_ndc) {
            w = mid_w;
            if (ray_front_depth_ndc <= sample_depth_ndc) {
                hit_sample_depth_ndc01 = sample_depth_ndc01;
                hit_sample_uv = sample_uv;
                hit = 1.0;
                min_depth_difference_ndc = depth_difference_ndc;
            } else {
                w = (w + prev_w) * 0.5;
            }
        } else {
            prev_w = mid_w;
        }
    }
    return vec4(hit_sample_uv, hit_sample_depth_ndc01, hit);
}

vec4 intersection_raymarch_uv(vec3 origin_vs, vec3 direction_vs, float max_distance_vs, out uint steps) {
    vec3 end_vs = origin_vs + direction_vs * max_distance_vs;
    if (FRUSTUM_CLIP_ENABLE) {
        end_vs = segment_end_clip_vs(origin_vs, end_vs);
    }
    vec4 origin_cs = position_cs_from_vs(origin_vs);
    vec4 end_cs = position_cs_from_vs(end_vs);
    vec4 origin_front_cs = position_cs_from_vs(origin_vs + vec3(0.0, 0.0, THICKNESS_RADIUS_VS));
    vec4 end_front_cs = position_cs_from_vs(end_vs + vec3(0.0, 0.0, THICKNESS_RADIUS_VS));

    float w = 0.0;
    float dw = 1.0 / float(STEPS_MAX);
    float potential_w = 0.0;
    float min_depth_difference_ndc = INFINITY;

    vec2 sample_uv;
    float sample_depth_ndc01;
    for (uint i = 0; i < STEPS_MAX; ++i) {
        steps = i;
        w += dw;

        vec4 position_cs = mix(origin_cs, end_cs, w);
        vec4 position_front_cs = mix(origin_front_cs, end_front_cs, w);

        float ray_depth_ndc = position_cs.z / position_cs.w;
        float ray_front_depth_ndc = position_front_cs.z / position_front_cs.w;

        sample_uv = position_uv_from_ndc(vec3(position_cs.xy / position_cs.w, ray_depth_ndc)).xy;
        normal_depth_rough_sample nd = normal_depth_rough_from_sampler(sample_uv);
        sample_depth_ndc01 = nd.depth_ndc01;
        float sample_depth_ndc = sample_depth_ndc01 * 2.0 - 1.0;
        float depth_difference_ndc = ray_depth_ndc - sample_depth_ndc;

        if (depth_difference_ndc >= 0.0) {
            if (ray_front_depth_ndc <= sample_depth_ndc) {
                vec4 hit_uv = vec4(sample_uv, sample_depth_ndc01, 1.0);
                if (BSEARCH_ENABLE) {
                    vec4 bsearch_hit_uv = intersection_binary_search_uv(
                        origin_cs, end_cs, origin_front_cs, end_front_cs, w, w - dw
                    );
                    return mix(hit_uv, bsearch_hit_uv, bsearch_hit_uv.w);
                } else {
                    return hit_uv;
                }
            } else if (depth_difference_ndc < min_depth_difference_ndc) {
                min_depth_difference_ndc = depth_difference_ndc;
                potential_w = w;
            }
        }
    }

    vec4 hit_uv = vec4(sample_uv, sample_depth_ndc01, 0.0);
    if (BSEARCH_ENABLE && potential_w > 0.0) {
        vec4 bsearch_hit_uv = intersection_binary_minimization_uv(
            origin_cs, end_cs, origin_front_cs, end_front_cs, min_depth_difference_ndc, potential_w, potential_w - dw
        );
        return mix(hit_uv, bsearch_hit_uv, bsearch_hit_uv.w);
    } else {
        return hit_uv;
    }
}


vec4 test_coordinates(vec3 uv) {
    const float BORDER_SIZE = 0.01;
    vec2 quadrant_uv = (uv.xy - vec2(0.5)) * 2.0;
    vec2 border_xy = step(abs(quadrant_uv), vec2(BORDER_SIZE));
    float border = max(border_xy.x, border_xy.y) * 0.5;

    vec3 position_ndc = position_ndc_from_uv(uv);
    vec3 position_vs = position_vs_from_ndc(position_ndc);

    vec4 position_cs_reprojected = position_cs_from_vs(position_vs);
    vec3 position_ndc_reprojected = position_ndc_from_cs(position_cs_reprojected);
    vec3 uv_reprojected = position_uv_from_ndc(position_ndc_reprojected);
    float depth_reprojected_vs = depth_vs_from_ndc01(uv_reprojected.z);
    vec3 position_vs_reprojected = position_vs_from_ndc(position_ndc_reprojected);

    float uv_eq = step(dot(uv - uv_reprojected, uv - uv_reprojected), EPSILON);
    float ndc_eq = step(dot(position_ndc - position_ndc_reprojected, position_ndc - position_ndc_reprojected), EPSILON);
    float depth_eq = step(abs(depth_reprojected_vs - position_vs.z), EPSILON);
    float vs_eq = step(dot(position_vs - position_vs_reprojected, position_vs - position_vs_reprojected), EPSILON);

    float top_left =        step(quadrant_uv.x, -BORDER_SIZE)   * step(quadrant_uv.y, -BORDER_SIZE);
    float top_right =       step(BORDER_SIZE, quadrant_uv.x)    * step(quadrant_uv.y, -BORDER_SIZE);
    float bottom_left =     step(quadrant_uv.x, -BORDER_SIZE)   * step(BORDER_SIZE, quadrant_uv.y);
    float bottom_right =    step(BORDER_SIZE, quadrant_uv.x)    * step(BORDER_SIZE, quadrant_uv.y);

    float tests = 0.0; 
    tests += uv_eq * top_left;
    tests += ndc_eq * top_right;
    tests += depth_eq * bottom_left;
    tests += vs_eq * bottom_right;
    return vec4(border + tests);
}


float luminance_from_rgb(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// source: https://www.shadertoy.com/view/XlGcRh
uvec2 pcg2d(uvec2 v) {
    v = v * 1664525u + 1013904223u;

    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;

    v = v ^ (v>>16u);

    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;

    v = v ^ (v>>16u);

    return v;
}
// http://www.jcgt.org/published/0009/03/02/
uvec3 pcg3d(uvec3 v) {

    v = v * 1664525u + 1013904223u;

    v.x += v.y*v.z;
    v.y += v.z*v.x;
    v.z += v.x*v.y;

    v ^= v >> 16u;

    v.x += v.y*v.z;
    v.y += v.z*v.x;
    v.z += v.x*v.y;

    return v;
}

void main() {
    vec4 scene_color = texture(scene_colour_texture, in_uv);
    vec3 normal_vs;
    float depth_ndc01;
    normal_depth_rough_sample ndr = normal_depth_rough_from_sampler(in_uv);
    normal_vs = ndr.normal_vs;
    depth_ndc01 = ndr.depth_ndc01;
    if (depth_ndc01 > FAR_MAX_NDC) {
        out_fragment_color = scene_color;
        return;
    }

    vec3 position_ndc = position_ndc_from_uv(vec3(in_uv, depth_ndc01));
    vec3 position_vs = position_vs_from_ndc(position_ndc);
    vec3 view_direction_vs = normalize(position_vs);
    vec3 reflection_direction_vs = normalize(reflect(view_direction_vs, normal_vs));

    float roughness_factor = pow(1.0 - ndr.roughness, ROUGHNESS_POWER);

    // vec2 s = in_uv.xy * float(UINT_MAX);
    // uvec4 u = uvec4(s, uint(s.x) ^ uint(s.y), uint(s.x) + uint(s.y));
    // vec3 jitter = (vec3(pcg3d(u.xyz)) / float(UINT_MAX)) * 2.0 - 1.0;
    // vec3 ray_direction_vs = reflection_direction_vs + normal_vs * jitter * (1.0 - roughness_factor) * 0.1;
    vec3 ray_direction_vs = reflection_direction_vs;

    uint steps;
    vec4 hit_uv = intersection_raymarch_uv(position_vs, ray_direction_vs, DISTANCE_MAX_VS, steps);
    vec4 hit_color = texture(scene_colour_texture, hit_uv.xy);

    float fresnel_factor = pow(1.0 - max(dot(-view_direction_vs, normal_vs), 0.0), FRESNEL_POWER);

    float hit_luminance = luminance_from_rgb(hit_color.rgb);
    float scene_luminance = luminance_from_rgb(scene_color.rgb);
    float luminance_factor = pow(hit_luminance / (scene_luminance + 1.0), LUMINANCE_POWER);

    float front_ray_factor = pow(1.0 - max(dot(reflection_direction_vs, vec3(0.0, 0.0, 1.0)), 0.0), FRONT_RAY_DISCARD_POWER);
    vec4 reflection_color = mix(
        scene_color,
        hit_color,
        front_ray_factor * pow(
            fresnel_factor
                * luminance_factor
                * roughness_factor,
            1.0 / REFLECTION_POWER_BIAS
        )
    );

    if (hit_uv.w == 0.0) {
        out_fragment_color = hit_uv.z > FAR_MAX_NDC ? reflection_color : scene_color;
    } else {
        out_fragment_color = reflection_color;
    }
}