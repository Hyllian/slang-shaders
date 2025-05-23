#version 450

// See pixel_aa.slang for copyright and other information.

// clang-format off
#include "../../../misc/shaders/input_transform/parameters.inc"
#include "parameters.inc"

#include "shared.inc"
#include "../../../misc/shaders/input_transform/input_transform.inc"
// clang-format on

layout(push_constant) uniform Push {
    vec4 SourceSize;
    vec4 OutputSize;
    uint Rotation;
    // Own settings
    float PIX_AA_SHARP;
    float PIX_AA_SUBPX;
    float PIX_AA_SUBPX_ORIENTATION;
    // From input transform library, scaling section
    float FORCE_ASPECT_RATIO;
    float ASPECT_H;
    float ASPECT_V;
    float FORCE_INTEGER_SCALING_H;
    float FORCE_INTEGER_SCALING_V;
    float OVERSCALE;
    // From input transform library, cropping section
    float OS_CROP_TOP;
    float OS_CROP_BOTTOM;
    float OS_CROP_LEFT;
    float OS_CROP_RIGHT;
    // From input transform library, moving section
    float SHIFT_H;
    float SHIFT_V;
    float CENTER_AFTER_CROPPING;
}
param;

layout(std140, set = 0, binding = 0) uniform UBO { mat4 MVP; }
global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec4 input_corners;
layout(location = 1) out vec2 tx_coord;
layout(location = 2) out vec2 tx_per_px;
layout(location = 3) out vec2 sub_tx_offset;
layout(location = 4) out vec2 trans_lb;
layout(location = 5) out vec2 trans_ub;
layout(location = 6) out float trans_slope;

void main() {
    gl_Position = global.MVP * Position;

    const vec4 crop =
        vec4(param.OS_CROP_TOP, param.OS_CROP_LEFT, param.OS_CROP_BOTTOM, param.OS_CROP_RIGHT);
    const vec2 scale_i2o = get_scale_i2o(
        param.SourceSize.xy, param.OutputSize.xy, crop, param.Rotation, param.CENTER_AFTER_CROPPING,
        param.FORCE_ASPECT_RATIO, vec2(param.ASPECT_H, param.ASPECT_V),
        vec2(param.FORCE_INTEGER_SCALING_H, param.FORCE_INTEGER_SCALING_V), param.OVERSCALE);
    const vec2 shift = vec2(param.SHIFT_H, param.SHIFT_V);
    const vec2 input_center =
        get_input_center(param.SourceSize.xy, param.OutputSize.xy, scale_i2o, crop, shift,
                         param.Rotation, param.CENTER_AFTER_CROPPING);
    tx_coord = transform(TexCoord, vec2(0.5), param.OutputSize.xy / scale_i2o, input_center);
    tx_per_px = 1.0 / scale_i2o;
    input_corners = get_input_corners(param.SourceSize.xy, crop, param.Rotation);

    calculate_pixel_aa_params(tx_per_px, param.PIX_AA_SHARP, uint(param.PIX_AA_SUBPX_ORIENTATION),
                              param.Rotation, trans_lb, trans_ub, trans_slope, sub_tx_offset);
}

#pragma stage fragment
layout(location = 0) in vec4 input_corners;
layout(location = 1) in vec2 tx_coord;
layout(location = 2) in vec2 tx_per_px;
layout(location = 3) in vec2 sub_tx_offset;
layout(location = 4) in vec2 trans_lb;
layout(location = 5) in vec2 trans_ub;
layout(location = 6) in float trans_slope;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

// Returns y in [0, 1]
// l: lower center point of transition
// u: upper center point of transition
// s: transition width
vec2 trapezoid(vec2 x, vec2 l, vec2 u, vec2 s) {
    return clamp((s + u - l - abs(2.0 * x - u - l)) / (2.0 * s), 0.0, 1.0);
}

void main() {
    FragColor.rgb =
        param.PIX_AA_SUBPX < 0.5
            ? pixel_aa(Source, tx_coord, param.SourceSize.zw, trans_lb, trans_ub, trans_slope)
            : pixel_aa_subpx(Source, tx_coord, sub_tx_offset, param.SourceSize.zw, trans_lb,
                             trans_ub, trans_slope);

    // Blend with background.
    const vec2 w = trapezoid(tx_coord, input_corners.xy, input_corners.zw, tx_per_px);
    FragColor.rgb *= w.x * w.y;

    // Gamma correct output.
    FragColor.rgb = pow(FragColor.rgb, vec3(1.0 / 2.2));
}
