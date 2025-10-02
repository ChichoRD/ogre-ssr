#version 410

// Ogre::VES_POSITION               vertex              0       gl_Vertex
// Ogre::VES_BLEND_WEIGHTS	        blendWeights        1       n/a
// Ogre::VES_NORMAL	                normal              2       gl_Normal
// Ogre::VES_COLOUR	                colour              3       gl_Color
// Ogre::VES_COLOUR2	            secondary_colour    4       gl_SecondaryColor
// Ogre::VES_BLEND_INDICES	        blendIndices        7       n/a
// Ogre::VES_TEXTURE_COORDINATES	uv0 - uv7           8-15	gl_MultiTexCoord0 - gl_MultiTexCoord7
// Ogre::VES_TANGENT	            tangent             14	    n/a
// Ogre::VES_BINORMAL	            binormal            15	    n/a

uniform mat4 world_view_matrix;
uniform mat4 it_world_view_matrix;
uniform mat4 projection_matrix;

uniform vec3 specular;
uniform float shininess;

layout(location = 0) in vec3 in_position_os;
layout(location = 2) in vec3 in_normal_os;

layout(location = 0) out vec3 out_normal_vs;
layout(location = 1) out float out_depth_ndc01;
layout(location = 2) out float out_roughness;

float luminance_from_rgb(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    vec3 position_os = in_position_os;

    vec4 pos_vs = world_view_matrix * vec4(position_os.xyz, 1.0);
    vec4 pos_cs = projection_matrix * vec4(pos_vs.xyz, 1.0);
    gl_Position = pos_cs;

    out_normal_vs = normalize((it_world_view_matrix * vec4(in_normal_os, 0.0)).xyz);
    out_depth_ndc01 = pos_cs.z / pos_cs.w;
    out_roughness = pow(1.0 - luminance_from_rgb(specular), shininess);
}