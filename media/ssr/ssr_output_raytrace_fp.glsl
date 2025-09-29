#version 410

uniform sampler2D scene_colour_texture;
uniform sampler2D normal_depth_rough_texture;
uniform mat4 i_projection_matrix;
uniform mat4 projection_matrix;

uniform float far_clip_plane;
uniform vec4 texel_size;

layout(location = 0) in vec2 in_uv;
layout(location = 0) out vec4 out_fragment_color;

// Ray marching parameters
const uint MAX_STEPS_RAYMARCH = 64;
const uint MAX_STEPS_BSEARCH = 16;
const float STEP_SIZE_VS = 0.02;
const float MAX_DISTANCE_VS = 50.0;
const float DEPTH_THRESHOLD_VS = 0.001;
const float MIN_STEP_SIZE = 0.001;

// Ray marching state tracking
struct RayMarchState {
    vec3 current_pos_vs;
    vec3 previous_pos_vs;
    float current_depth_vs;
    float previous_depth_vs;
    float sampled_depth_vs;
    vec2 current_uv;
    bool hit_found;
    uint step_count;
};

// === Coordinate transformation utilities ===
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

bool is_uv_valid(vec2 uv) {
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

// === Ray marching utilities ===
float sample_depth_vs(vec2 uv) {
    if (!is_uv_valid(uv)) return -far_clip_plane; // Return far depth (most negative)
    return position_vs_from_depth_ndc(uv, texture(normal_depth_rough_texture, uv).w).z;
}

bool check_intersection(RayMarchState state) {
    // In Ogre view space: +z out of screen, -z into screen (depths are negative)
    // As we march away from camera, depth becomes MORE negative
    float ray_depth_change = state.current_depth_vs - state.previous_depth_vs;
    
    // Prevent self-intersection by ensuring we've moved a minimum distance
    if (abs(ray_depth_change) < MIN_STEP_SIZE) return false;
    
    // Check if the sampled surface depth falls between previous and current ray depths
    // Since depths are negative, "deeper" means more negative
    bool depth_crossed = (state.previous_depth_vs >= state.sampled_depth_vs && 
                         state.current_depth_vs <= state.sampled_depth_vs) ||
                        (state.previous_depth_vs <= state.sampled_depth_vs && 
                         state.current_depth_vs >= state.sampled_depth_vs);
    
    // Ensure we're moving into the scene (more negative z) and hit something closer to camera
    bool moving_into_scene = ray_depth_change < 0.0; // becoming more negative
    bool hit_surface_closer = state.sampled_depth_vs > state.current_depth_vs; // surface is less negative (closer)
    
    return depth_crossed && moving_into_scene && hit_surface_closer && 
           abs(state.current_depth_vs - state.sampled_depth_vs) < DEPTH_THRESHOLD_VS;
}

vec2 binary_search_intersection(vec3 start_pos_vs, vec3 end_pos_vs, out float final_sampled_depth_vs, out float final_depth_difference_vs) {
    vec3 current_pos_vs = end_pos_vs;
    vec3 step_vs = (end_pos_vs - start_pos_vs) * 0.5;
    vec2 final_uv;
    
    for (uint i = 0; i < MAX_STEPS_BSEARCH; ++i) {
        step_vs *= 0.5;
        vec3 test_pos_ndc = position_ndc_from_vs(current_pos_vs);
        final_uv = uv_from_position_ndc(test_pos_ndc);
        
        if (!is_uv_valid(final_uv)) {
            current_pos_vs -= step_vs;
            continue;
        }
        
        final_sampled_depth_vs = sample_depth_vs(final_uv);
        final_depth_difference_vs = current_pos_vs.z - final_sampled_depth_vs;
        
        // In Ogre view space with negative depths:
        // If depth_difference > 0: ray is behind surface (ray more negative than surface)
        // If depth_difference < 0: ray is in front of surface (ray less negative than surface)
        if (final_depth_difference_vs < 0.0) {
            // Ray is in front of surface, move backwards along ray (towards start)
            current_pos_vs -= step_vs;
        } else {
            // Ray is behind surface, move forward along ray (towards end)
            current_pos_vs += step_vs;
        }
    }
    
    return final_uv;
}

vec2 raymarch_improved(vec3 origin_vs, vec3 direction_vs, out float hit_sampled_depth_vs, out float depth_difference_vs, out uint steps) {
    RayMarchState state;
    state.current_pos_vs = origin_vs;
    state.previous_pos_vs = origin_vs;
    state.hit_found = false;
    state.step_count = 0;
    
    vec3 step_vs = normalize(direction_vs) * STEP_SIZE_VS;
    float total_distance = 0.0;
    
    // Initialize previous depth
    state.previous_depth_vs = origin_vs.z;
    
    // Skip the first small step to avoid immediate self-intersection
    vec3 initial_step = step_vs * 0.1;
    state.current_pos_vs += initial_step;
    
    for (steps = 1; steps < MAX_STEPS_RAYMARCH && total_distance < MAX_DISTANCE_VS; ++steps) {
        // Store previous state
        state.previous_pos_vs = state.current_pos_vs;
        state.previous_depth_vs = state.current_depth_vs;
        
        // Advance ray
        state.current_pos_vs += step_vs;
        total_distance += length(step_vs);
        
        // Calculate current state
        vec3 current_pos_ndc = position_ndc_from_vs(state.current_pos_vs);
        state.current_uv = uv_from_position_ndc(current_pos_ndc);
        
        // Check if we're still in valid screen space
        if (!is_uv_valid(state.current_uv)) {
            break;
        }
        
        state.current_depth_vs = state.current_pos_vs.z;
        state.sampled_depth_vs = sample_depth_vs(state.current_uv);
        
        // Skip if we're at far plane (background)
        if (state.sampled_depth_vs <= -far_clip_plane * 0.99) {
            continue;
        }
        
        // Check for intersection using improved method
        if (steps > 1 && check_intersection(state)) { // Skip check on first iteration
            // Refine intersection with binary search
            vec2 refined_uv = binary_search_intersection(
                state.previous_pos_vs, 
                state.current_pos_vs,
                hit_sampled_depth_vs, 
                depth_difference_vs
            );
            
            if (is_uv_valid(refined_uv)) {
                return refined_uv;
            }
        }
        
        // Adaptive step size based on depth gradient
        // In negative depth space, larger absolute differences mean steeper gradients
        float depth_gradient = abs(state.sampled_depth_vs - state.previous_depth_vs);
        if (depth_gradient > DEPTH_THRESHOLD_VS * 10.0) {
            step_vs *= 0.5; // Smaller steps near surfaces with steep depth changes
        } else if (depth_gradient < DEPTH_THRESHOLD_VS) {
            step_vs *= 1.2; // Larger steps in areas with gradual depth changes
        }
        
        // Clamp step size
        float step_length = length(step_vs);
        if (step_length < MIN_STEP_SIZE) {
            step_vs = normalize(step_vs) * MIN_STEP_SIZE;
        } else if (step_length > STEP_SIZE_VS * 2.0) {
            step_vs = normalize(step_vs) * STEP_SIZE_VS * 2.0;
        }
    }
    
    // No intersection found
    hit_sampled_depth_vs = -far_clip_plane;
    depth_difference_vs = 0.0;
    return state.current_uv;
}

// === Utility functions ===
vec3 luminance_from_rgb(vec3 color) {
    return vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
}

// === Main shader ===
void main() {
    vec4 scene_color = texture(scene_colour_texture, in_uv);
    vec4 ndr = texture(normal_depth_rough_texture, in_uv);

    vec3 normal_vs = normalize(ndr.xyz);
    float depth_ndc = ndr.w;
    
    // Skip background pixels
    if (depth_ndc > 0.999) {
        out_fragment_color = scene_color;
        return;
    }

    vec3 position_vs = position_vs_from_depth_ndc(in_uv, depth_ndc);
    vec3 view_direction_vs = normalize(position_vs);
    vec3 reflection_direction_vs = normalize(reflect(view_direction_vs, normal_vs));

    // Perform improved ray marching
    float hit_sampled_depth_vs;
    float depth_difference_vs;
    uint steps;
    vec2 hit_uv = raymarch_improved(
        position_vs, 
        reflection_direction_vs, 
        hit_sampled_depth_vs, 
        depth_difference_vs, 
        steps
    );
    
    // Check if ray marching found a valid intersection
    // Also check if we hit far plane (background)
    if (steps >= MAX_STEPS_RAYMARCH || !is_uv_valid(hit_uv) || 
        abs(depth_difference_vs) > DEPTH_THRESHOLD_VS || hit_sampled_depth_vs <= -far_clip_plane * 0.99) {
        out_fragment_color = scene_color;
        return;
    }
    
    // Sample the reflected color
    vec4 hit_color = texture(scene_colour_texture, hit_uv);
    
    // Calculate reflection factors
    vec3 hit_luminance = luminance_from_rgb(hit_color.rgb);
    vec3 scene_luminance = luminance_from_rgb(scene_color.rgb);
    float luminance_factor = clamp(
        dot(hit_luminance, hit_luminance) / (dot(scene_luminance, scene_luminance) + 0.001),
        0.0,
        1.0
    );
    
    float depth_confidence = 1.0 - smoothstep(0.0, DEPTH_THRESHOLD_VS, abs(depth_difference_vs));
    float edge_fade = smoothstep(0.0, 0.1, min(min(hit_uv.x, 1.0 - hit_uv.x), min(hit_uv.y, 1.0 - hit_uv.y)));
    float reflection_strength = /*luminance_factor*/ * depth_confidence * edge_fade;
    
    // Final color blend
    out_fragment_color = mix(scene_color, hit_color, reflection_strength * 0.5);
    
    // Debug visualizations (comment out for final version)
    // out_fragment_color = vec4(hit_uv, 0.0, 1.0); // Show hit UV coordinates
    // out_fragment_color = vec4(hit_uv - in_uv, 0.0, 1.0); // Show reflection offset
    // out_fragment_color = vec4(float(steps) / float(MAX_STEPS_RAYMARCH)); // Show step count
}