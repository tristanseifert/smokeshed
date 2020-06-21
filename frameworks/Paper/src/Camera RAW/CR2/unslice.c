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
#include <math.h>

/// Bayer color component for the given line and column (assuming RG/GB)
#define BAYER_COLOR(l, c) ((((l)&1)<<1) | (c&1))

/**
 * Unslicification
 */
int CR2Unslice(jpeg_decompressor_t *jpeg,
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

/**
 * Calculates whether the Bayer color array is shifted vertically.
 *
 * When taking sensor borders into account, the first visible line may actually be the second row
 * of the Bayer array (G2/B) so we need to account for that.
 *
 * This works by calculating the sums for each of the R/G1-G2/B values; the absolute difference
 * between G1-G2 must be smaller than that between R-B; otherwise, assume the color matrix must be
 * shifted down one line.
 *
 * @param inPlane Image data plane (1 component)
 * @param borders Position of borders in image, starting with top and going clockwise.
 * @param rowWidth Number of pixels (including border area) per line
 * @return Vertical shift for bayer matrix, either 0 or 1.
 */
int CR2CalculateBayerShift(uint16_t *inPlane, size_t rowWidth, size_t *borders) {
    double sums[4] = {0, 0, 0, 0};
    size_t line, l, rowOff;
    size_t col, c;
    
    // iterate each line
    for (line = borders[0], l = 0; line <= borders[2]; line++, l++) {
        rowOff = (line * rowWidth);
        
        // iterate each column in the line
        for (col = borders[3], c = 0; col <= borders[1]; col++, c++) {
            sums[BAYER_COLOR(l, c)] += inPlane[rowOff + col];
        }
    }
    
    // detect whether difference between greens is larger than red/blue
    if (fabs(sums[0] - sums[3]) < fabs(sums[1] - sums[2])) {
        return 1;
    }
    // first line is R/G1; no shift needed
    else {
        return 0;
    }
}
