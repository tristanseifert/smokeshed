//
//  ImageRenderView.metal
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200718.
//

#include <metal_stdlib>
using namespace metal;


/**
 * Output of a very simple texture sampling vertex shader, and input into the
 * corresponding fragment shader.
 */
typedef struct {
    /// vertex position in screen space
    float4 renderedCoordinate [[position]];
    /// texture coordinates to sample from
    float2 textureCoordinate;
} TextureMappingVertex;

/**
 * When drawing four points, this vertex shader can be used to map a texture to
 * the quad that results.
 */
vertex TextureMappingVertex textureMapVtx(unsigned int vertex_id [[ vertex_id  ]]) {
        float4x4 renderedCoordinates = float4x4(
            // (x, y, depth, W)
            float4( -1.0, -1.0, 0.0, 1.0 ),
            float4(  1.0, -1.0, 0.0, 1.0 ),
            float4( -1.0,  1.0, 0.0, 1.0 ),
            float4(  1.0,  1.0, 0.0, 1.0 )
        );

        float4x2 textureCoordinates = float4x2(
            // (x, y)
            float2( 0.0, 1.0 ),
            float2( 1.0, 1.0 ),
            float2( 0.0, 0.0 ),
            float2( 1.0, 0.0 )
        );

        // output to fragment shader
        TextureMappingVertex outVertex;
        outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
        outVertex.textureCoordinate = textureCoordinates[vertex_id];

        return outVertex;
}

/**
 * Given the output of the `textureMapVtx` shader, this fragment shader samples
 * the first color attachment to produce the output image.
 */
fragment half4 textureMapFrag(TextureMappingVertex mappingVertex [[ stage_in  ]],
                              texture2d<float, access::sample> texture [[ texture(0)  ]]) {
    // create a sampler (with linear interpolation) over the texture
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    // sample from the texture
    return half4(texture.sample(s, mappingVertex.textureCoordinate));
}

