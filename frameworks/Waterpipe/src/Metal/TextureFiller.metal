//
//  TextureFiller.metal
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200805.
//

#include <metal_stdlib>
using namespace metal;

/*
 * Uniforms passed into the compute kernel
 */
typedef struct {
    // Fill value
    float4 fill;
} UniformIn;


/*
 * Fills the texture with the value provided in the uniform buffer.
 */
kernel void fillTexture(texture2d<float, access::write> texture [[ texture(0) ]],
                        constant UniformIn &uniforms [[ buffer(0) ]],
                        uint2 id [[ thread_position_in_grid ]]) {
    texture.write(uniforms.fill, id);
}
