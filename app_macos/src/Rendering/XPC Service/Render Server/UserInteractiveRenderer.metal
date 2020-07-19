//
//  UserInteractiveRenderer.metal
//  Renderer
//
//  Created by Tristan Seifert on 20200719.
//

#include <metal_stdlib>
using namespace metal;

/**
 * Input (from the vertex buffer) into the texture map vertex buffer.
 */
typedef struct {
    /// Position in screen space
    float4 position [[ attribute(0) ]];
    /// Texture coordinate
    float2 texture [[ attribute(1) ]];
} TextureMapVertexIn;

/**
 * Uniforms (namely, the projection matrix) for the texture map call
 */
typedef struct {
    /// Projection matrix
    float4x4 proj;
} TextureMapUniformIn;

/**
 * Output of a very simple texture sampling vertex shader, and input into the corresponding fragment shader.
 */
typedef struct {
    /// vertex position in screen space
    float4 renderedCoordinate [[position]];
    /// texture coordinates to sample from
    float2 textureCoordinate;
} TextureMapVertexOut;

/**
 * When drawing four points, this vertex shader can be used to map a texture to the quad that results.
 */
vertex TextureMapVertexOut textureMapVtx(const TextureMapVertexIn vertexIn [[ stage_in ]],
                                         const device TextureMapUniformIn &uniforms [[ buffer(1) ]]) {
    // output to fragment shader
    TextureMapVertexOut outVertex;
    outVertex.renderedCoordinate = vertexIn.position * uniforms.proj;
    outVertex.textureCoordinate = vertexIn.texture;

    return outVertex;
}

/**
 * Given the output of the `textureMapVtx` shader, this fragment shader samples
 * the first color attachment to produce the output image.
 */
fragment half4 textureMapFrag(TextureMapVertexOut fromVtx [[ stage_in  ]],
                              texture2d<float, access::sample> texture [[ texture(0)  ]]) {
    // create a sampler (with linear interpolation) over the texture
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    // sample from the texture
    return half4(texture.sample(s, fromVtx.textureCoordinate));
}
