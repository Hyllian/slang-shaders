#version 450

/*
    Blur fill v1.5 by fishku
    Copyright (C) 2023
    Public domain license (CC0)

    This shader preset allows cropping the image on any side, and filling the
    cropped area with a blurred version of the input image borders.
    This is useful for certain games that do not render a full image to maintain
    the overall aspect ratio and to avoid burn-in.

    The preset also allows you to extend the original content to a larger
    screen. It's recommended to set the video scaling options as follows:
    - Turn integer scaling OFF
    - Set aspect ratio to FULL
    The shader will then take over and handle the proper scaling and aspect
    ratio of the input.

    The preset comes in three variants which differ only in the strength of the
    blur.
    Since the blur strength in the dual filter blur depends on the input
    resolution, and because there is currently no mechanism to set resolution
    based on user parameters, the three variants provide different sampling
    resolutions which affect the strength of the blur.
    Additionally to the resolution, a blur radius parameter controls the
    strength of the blur.

    Changelog:
    v1.5: Add anti-aliased interpolation for non-integer scaling.
    v1.4: Fix scaling bugs.
    v1.3: Reduce shimmering artifacts.
    v1.2: Fix scaling bugs.
    v1.1: Fix bug with glcore driver.
    v1.0: Initial release.
*/

#include "../../../blurs/shaders/dual_filter/parameters.slang"
#include "parameters.slang"

layout(push_constant) uniform Push {
    vec4 InputSize;
    vec4 TiledSize;
    vec4 FinalViewportSize;
    float OS_CROP_TOP;
    float OS_CROP_BOTTOM;
    float OS_CROP_LEFT;
    float OS_CROP_RIGHT;
    float CENTER_CROP;
    float SAMPLE_SIZE;
    float FORCE_ASPECT_RATIO;
    float ASPECT_H;
    float ASPECT_V;
    float FORCE_INTEGER_SCALING;
    float FILL_GAMMA;
    // From dual filter blur
    float BLUR_RADIUS;
    // From pixel AA
    float PIX_AA_SHARP;
    float PIX_AA_SUBPX;
    float PIX_AA_SUBPX_BGR;
}
param;

#include "scaling.slang"

layout(std140, set = 0, binding = 0) uniform UBO { mat4 MVP; }
global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Input;
layout(set = 0, binding = 3) uniform sampler2D Tiled;
layout(set = 0, binding = 4) uniform sampler2D Blurred;

#include "../../../interpolation/shaders/pixel_aa/shared.slang"

void main() {
    const vec2 scale_o2i = scale_o2i();
    const vec2 pixel_coord =
        (vTexCoord - 0.49999) * scale_o2i + get_input_center();

    const vec4 input_extrema = vec4(param.OS_CROP_LEFT, param.OS_CROP_TOP,
                                    param.InputSize.x - param.OS_CROP_RIGHT,
                                    param.InputSize.y - param.OS_CROP_BOTTOM);
    if (any(lessThan(pixel_coord, input_extrema.xy)) ||
        any(greaterThanEqual(pixel_coord, input_extrema.zw))) {
        if (param.BLUR_RADIUS > 0.0) {
            // Sample blur.
            FragColor = vec4(
                pow(texture(Blurred, vTexCoord).rgb, vec3(param.FILL_GAMMA)),
                1.0);
        } else {
            // Sample tiled pattern.
            // Do a sharp (nearest neighbor) resampling.
            FragColor =
                vec4(pow(texture(Tiled,
                                 (floor(vTexCoord * param.TiledSize.xy) + 0.5) *
                                     param.TiledSize.zw)
                             .rgb,
                         vec3(param.FILL_GAMMA)),
                     1.0);
        }
    } else {
        // Sample original.
        if (param.FORCE_INTEGER_SCALING > 0.5) {
            // Do a perfectly sharp (nearest neighbor) sampling.
            FragColor = vec4(
                texture(Input, (floor(pixel_coord) + 0.5) * param.InputSize.zw)
                    .rgb,
                1.0);
        } else {
            // Do a sharp anti-aliased interpolation.
            // Do not correct for gamma additionally because the input is
            // already in linear color space.
            if (param.PIX_AA_SUBPX < 0.5) {
                const vec2 tx_size = get_texel_size(pixel_coord) * scale_o2i *
                                     param.InputSize.zw;
                FragColor =
                    vec4(sample_aa(Input, pixel_coord, param.InputSize.zw,
                                   false, param.PIX_AA_SHARP, tx_size),
                         1.0);
            } else {
                for (int i = -1; i < 2; ++i) {
                    const vec2 subpix_coord =
                        pixel_coord +
                        vec2((param.PIX_AA_SUBPX_BGR < 0.5 ? i : -i) / 3.0,
                             0.0) *
                            param.FinalViewportSize.zw * param.InputSize.xy;
                    const vec2 tx_size = get_texel_size(subpix_coord) *
                                         scale_o2i * param.InputSize.zw /
                                         vec2(3.0, 1.0);
                    FragColor[i + 1] =
                        sample_aa(Input, subpix_coord, param.InputSize.zw,
                                  false, param.PIX_AA_SHARP, tx_size)[i + 1];
                }
                FragColor[3] = 1.0;
            }
        }
    }
}