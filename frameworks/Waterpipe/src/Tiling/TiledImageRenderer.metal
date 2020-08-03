//
//  TiledImageRenderer.metal
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200802.
//

#include <metal_stdlib>
using namespace metal;

/*
 * Uniforms passed to the rendering shader
 */
typedef struct {
    // Projection matrix (converting pixel position to screen space)
    float4x4 proj;
    // Viewport size
    float2 viewport;
    // Size of tiles (all tiles are square)
    uint tileSize;
} TiledImageRenderUniformIn;

/*
 * Input (from the vertex buffer) into the texture map vertex buffer.
 */
typedef struct {
    // Position in pixel space
    float4 position [[ attribute(0) ]];
    // Texture coordinate (x,y) and visible texture size (z,w)
    float4 textureInfo [[ attribute(1) ]];
    // Texture slice to sample
    uint slice [[ attribute(2) ]];
} TiledImageRenderVertexIn;
/*
 * Output from the vertex shader to the fragment shader.
 */
typedef struct {
    // vertex position in screen space
    float4 renderedCoordinate [[ position ]];
    // texture coordinates to sample from
    float2 textureCoordinate;
    // texture slice to sample
    uint slice;
} TiledImageRenderVertexOut;


/*
 * Vertex shader for drawing a tiled image. Each tile of the image is drawn as a quad, which will
 * invoke this shader.
 */
vertex TiledImageRenderVertexOut tiledImageRenderVtx(const TiledImageRenderVertexIn vertexIn [[ stage_in ]],
                                                     const device TiledImageRenderUniformIn &uniforms [[ buffer(1) ]]) {
    // convert pixel space position
    float4 pos = vector_float4(0, 0, 0, 1);
    pos.xy = vertexIn.position.xy / (uniforms.viewport / 2);
    pos.x -= 1;
    pos.y -= 1;
    
    // output to fragment shader
    TiledImageRenderVertexOut outVertex;
    outVertex.renderedCoordinate = pos * uniforms.proj;
    outVertex.textureCoordinate = vertexIn.textureInfo.xy;
    outVertex.slice = vertexIn.slice;

    return outVertex;
}

/*
 * Samples from the texture slice of the tiled image.
 *
 * Texture 0 should be bound to an array texture.
 */
fragment half4 tiledImageRenderFrag(TiledImageRenderVertexOut fromVtx [[ stage_in  ]],
                                    texture2d_array<float, access::sample> texture [[ texture(0) ]]) {
    // create a sampler (with linear interpolation) over the texture and sample it
    constexpr sampler s(address::clamp_to_edge, filter::bicubic);
    auto pixel = texture.sample(s, fromVtx.textureCoordinate, fromVtx.slice);
    return half4(pixel);
//    return half4(fromVtx.textureCoordinate.x, fromVtx.textureCoordinate.y, pixel.z, 1);
    // return half4(float(fromVtx.slice % 12) / 12, float(fromVtx.slice / 12) / 12, pixel.z, 1);
}

