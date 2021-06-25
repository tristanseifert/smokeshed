//
//  ColorConverter.metal
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200722.
//

#include <metal_stdlib>
using namespace metal;

/*
 * Uniforms passed into the compute kernel
 */
typedef struct {
    // Color space conversion matrix
    float3x3 conversion;
} UniformIn;


/*
 * Color space conversion kernel (this just applies a matrix to every pixel)
 */
kernel void convertToWorking(texture2d<float, access::read_write> texture [[ texture(0) ]],
                             constant UniformIn &uniforms [[ buffer(0) ]],
                             uint2 id [[ thread_position_in_grid ]]) {
    // read the pixel value
    float4 inColor = texture.read(id);
    // multiply by conversion matrix
    float3 converted = inColor.xyz * uniforms.conversion;
    // write back to texture
    texture.write(float4(converted.x, converted.y, converted.z, 1.0), id);
}
