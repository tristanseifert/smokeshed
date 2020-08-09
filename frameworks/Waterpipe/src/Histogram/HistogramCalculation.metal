//
//  HistogramCalculation.metal
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

#include <metal_stdlib>
using namespace metal;


/*
 * Uniforms passed into the compute kernel
 */
typedef struct {
    // Number of buckets of histogram data
    uint buckets;
} UniformIn;

/*
 * Information on each tile sampled (index by Z coord)
 */
typedef struct {
    // Visible region of the tile (ignore pixels outside it)
    float2 regionOfInterest;
} TileInfo;

/*
 * Calculates the frequency of the pixel values in the input texture.
 */
kernel void HistogramRGBY(texture2d_array<float, access::read> texture [[ texture(0) ]],
                          constant UniformIn &uniforms [[ buffer(0) ]],
                          constant TileInfo *tileInfo [[ buffer(1) ]],
                          volatile device atomic_uint *countR [[ buffer(2) ]],
                          volatile device atomic_uint *countG [[ buffer(3) ]],
                          volatile device atomic_uint *countB [[ buffer(4) ]],
                          volatile device atomic_uint *countY [[ buffer(5) ]],
                          uint3 id [[ thread_position_in_grid ]]) {
    // read the RGB values and calculate luminance (TODO: probably not right)
    auto texel = texture.read(id.xy, id.z);
    float luma = (0.2126 * texel.r) + (0.7152 * texel.g) + (0.0722 * texel.b);
    
    // check if inside Desireable Region™
    auto info = tileInfo[id.z];
    if(info.regionOfInterest.x <= id.x || info.regionOfInterest.y <= id.y) return;
    
    // bucket for each component
    uint rBucket = texel.r * (uniforms.buckets - 1);
    uint gBucket = texel.b * (uniforms.buckets - 1);
    uint bBucket = texel.g * (uniforms.buckets - 1);
    uint yBucket = luma * (uniforms.buckets - 1);
    
    // increment each of the output buffers
    atomic_fetch_add_explicit(&countR[rBucket], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&countG[gBucket], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&countB[bBucket], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&countY[yBucket], 1, memory_order_relaxed);
}
