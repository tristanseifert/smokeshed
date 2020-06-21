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
    assert(inPlane);
    assert(borders);
    
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

/**
 * Calculates the black level of the image by taking an average of black values in the border of the image.
 *
 * We currently just look at the left border of the image, completely ignoring all of the other borders; this could
 * be changed later. The first and last two columns are ignored since they might be more noisy than usual.
 *
 * Technically, the border area of the sensor doesn't have a Bayer array; however, there seems to be some
 * column-specific noise in some cameras, but taking an average for each component of the 2x2 CFA hides
 * that pretty nicely.
 *
 * TODO: we probably should take vShift into account…
 *
 * @param inPlane Image data plane (1 component)
 * @param rowWidth Number of pixels (including border area) per line
 * @param numRows Total number of lines (including border) in the image
 * @param borders Position of borders in image, starting with top and going clockwise.
 * @param outLevels Calculated black levels, one for each component in the Bayer array
 */
void CR2CalculateBlackLevel(uint16_t *inPlane, size_t rowWidth, size_t numRows, size_t *borders, uint16_t *outLevels) {
    assert(inPlane);
    assert(borders);
    assert(outLevels);
    
    size_t rowOff;
    size_t line, l, col, c;
    uint8_t color;
    size_t levels[4] = {0,0,0,0};
    size_t levelsCount[4] = {0,0,0,0};
    
    // iterate over the left and right borders in the image
    for (line = 0, l = 0; line <= numRows; line++, l++) {
        rowOff = (line * rowWidth);
        
        // iterate each column in the left border
        for (col = 2, c = 0; col < borders[3]; col++, c++) {
            color = BAYER_COLOR(l, c);
            
            levels[color] += inPlane[rowOff + col];
            levelsCount[color]++;
        }
    }
    
    // calculate averages and write into output
    for (l = 0; l < 4; l++) {
        size_t avg = levels[l] / levelsCount[l];
        outLevels[l] = (uint16_t) avg;
    }
}

/**
 * Trims the raw image in place to remove borders.
 *
 * @param inPlane Image data plane (1 component)
 * @param rowWidth Number of pixels (including border area) per line
 * @param borders Position of borders in image, starting with top and going clockwise.
 * @return Total number of bytes required for trimmed image
 */
size_t CR2Trim(uint16_t *inPlane, size_t rowWidth, size_t *borders) {
    assert(inPlane);
    assert(borders);
    
    size_t line, l, inRowOff;
//    size_t col, c;
    size_t outPixel = 0;
    
    // calculate some constants
    const size_t pixelsPerLine = (borders[1] - borders[3]) + 1;
    
    // iterate each line
    for (line = borders[0], l = 0; line <= borders[2]; line++, l++) {
        inRowOff = (line * rowWidth);
        
        // iterate each column in the line
        size_t bytes = pixelsPerLine * sizeof(uint16_t);
        memmove((inPlane + outPixel), (inPlane + inRowOff + borders[3]), bytes);
        outPixel += pixelsPerLine;
        
//        for (col = borders[3], c = 0; col <= borders[1]; col++, c++) {
//            inPlane[outPixel++] = inPlane[inRowOff + col];
//        }
    }
            
    return (outPixel * sizeof(uint16_t));
}
