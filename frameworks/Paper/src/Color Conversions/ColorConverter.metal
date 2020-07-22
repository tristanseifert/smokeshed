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
    float3x3 proj;
} UniformIn;


/*
 * Color space conversion kernel (this just applies a matrix to every pixel)
 */
kernel void convertToWorking(device float4 &data [[ buffer(0) ]],
                             constant UniformIn &uniforms [[ buffer(1) ]],
                             uint2 id [[thread_position_in_grid]]) {
    
}
