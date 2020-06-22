//
//  colorspace.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200621.
//

#ifndef colorspace_h
#define colorspace_h

#include <stdint.h>
#include <stddef.h>

/**
 * Converts RGB pixel data to the working color space, in place. The pixel buffer will contain 32-bit floating
 * point image components when done, so it should be sized appropriately.
 *
 * @note The D65 white point is used as a reference.
 *
 * @param pixels The 3-component pixel buffer
 * @param width Number of pixels per line
 * @param height Total number of lines
 * @param camXyz Camera-specific 3x3 conversion matrix
 */
long ConvertToWorking(uint16_t *pixels, size_t width, size_t height,
                      const double *camXyz);

#endif /* colorspace_h */
