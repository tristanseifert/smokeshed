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
typedef struct jpeg_decompressor jpeg_decompressor_t;

/**
 * Performs unslicing for the provided image.
 *
 * This is only intended to be used for regular RAW images, wherein the
 * horizontal and vertical sampling factors are 1.
 */
int CR2Unslice(jpeg_decompressor_t *jpeg,
               uint16_t *outPlane, uint16_t *slices,
               size_t sensorWidth, size_t sensorHeight);

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
 * @param rowWidth Number of pixels (including border area) per line
 * @param borders Position of borders in image, starting with top and going clockwise.
 * @return Vertical shift for bayer matrix, either 0 or 1.
 */
int CR2CalculateBayerShift(uint16_t *inPlane, size_t rowWidth, size_t *borders);

/**
 * Trims the raw image in place to remove borders.
 *
 * @param inPlane Image data plane (1 component)
 * @param rowWidth Number of pixels (including border area) per line
 * @param borders Position of borders in image, starting with top and going clockwise.
 * @return Total number of bytes required for trimmed image
 */
size_t CR2Trim(uint16_t *inPlane, size_t rowWidth, size_t *borders);

#endif /* unslice_h */
