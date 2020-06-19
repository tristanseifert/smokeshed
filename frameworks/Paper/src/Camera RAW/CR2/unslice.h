//
//  unslice.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

#ifndef unslice_h
#define unslice_h

#include <stdint.h>

// forward declarations
typedef struct decompressor decompressor_t;

/**
 * Performs unslicing for the provided image.
 *
 * This is only intended to be used for regular RAW images, wherein the
 * horizontal and vertical sampling factors are 1.
 */
int CR2Unslice(decompressor_t *jpeg,
               uint16_t *outPlane, uint16_t *slices,
               size_t sensorWidth, size_t sensorHeight);

#endif /* unslice_h */
