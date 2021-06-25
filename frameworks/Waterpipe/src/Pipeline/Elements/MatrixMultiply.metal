//
//  MatrixMultiply.metal
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200810.
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
kernel void RPE_MatrixMultiply(texture2d_array<float, access::read> input [[ texture(0) ]],
                               texture2d_array<float, access::write> output [[ texture(1) ]],
                               constant UniformIn &uniforms [[ buffer(0) ]],
                               uint3 id [[ thread_position_in_grid ]]) {
    // read the pixel value
    auto texel = input.read(id.xy, id.z);
    // multiply by conversion matrix
    float3 converted = texel.xyz * uniforms.conversion;
    // write back to texture
        output.write(float4(converted.x, converted.y, converted.z, 1), id.xy, id.z);
}


