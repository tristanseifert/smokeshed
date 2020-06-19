//
//  unslice.c
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

#include "unslice.h"
#include "decompress.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>

/**
 * Unslicification
 */
int CR2Unslice(decompressor_t *jpeg,
               uint16_t *outPlane, uint16_t *slices,
               size_t sensorWidth, size_t sensorHeight) {
    uint16_t temp;
    size_t sliceWidth, sliceHeight, lastSliceCol,
           unslicedRowSize, endCol, destOff;

    // offset into JPEG decoder output buffer
    size_t j = 0;

    // validate args
    assert(jpeg);
    assert(outPlane);
    assert(slices);

    // calculate width of each slice
    sliceWidth = (slices[1]) / jpeg->numComponents;

    lastSliceCol = jpeg->samplesPerLine;
    sliceHeight = jpeg->lines;
    unslicedRowSize = jpeg->samplesPerLine * jpeg->numComponents;

    // unslice
    for(size_t slice = 0; slice <= slices[0]; slice++) {
        // calculate slice start and end columns
        size_t startCol = (slice * sliceWidth);

        if (slice < slices[0]) {
            endCol = (slice+1) * sliceWidth;
        } else {
            endCol = lastSliceCol;
        }

        // copy the entire slice
        for (size_t line = 0; line < sliceHeight; line++) {
            // each column inside the slice…
            for (size_t col = startCol; col < endCol; col++) {
                destOff = (line * unslicedRowSize) + (col * jpeg->numComponents);

                // …and finally, each component within
                for (size_t comp = 0; comp < jpeg->numComponents; comp++) {
                    // bounds checking
                    if(j >= jpeg->outBufSz) {
                        return -1;
                    }

                    // read slice value
                    temp = jpeg->outBuf[j++];

                    // place it into the output
                    outPlane[destOff + comp] = temp;
                }
            }
        }
    }

    return 0;
}
