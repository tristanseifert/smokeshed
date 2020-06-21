//
//  debayer.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200620.
//

#ifndef debayer_h
#define debayer_h

#include <stdint.h>
#include <stddef.h>

/**
 * Debayering algorithms
 */
typedef enum debayer_algorithm {
    /// Basic bilinear interpolation
    kBayerAlgorithmBilinear = 1,
} debayer_algorithm_t;

/**
 * Performs debayering on the given 1 component input image, writing outputs into the 3 component output
 * image plane.
 *
 * @note This only supports RG/GB filter layouts right now.
 *
 * @param algo Debayering algorithm to use
 * @param inPlane Input plane
 * @param outPlane Output plane
 * @param width Image width
 * @param height Image height
 * @param vShift Vertical shift for the debayering pattern
 * @param wb White balance multipliers for each of the 4 bayer elements 
 * @param black Black level for each CFA index
 */
int Debayer(debayer_algorithm_t algo, const uint16_t *inPlane,
            uint16_t *outPlane, size_t width, size_t height, size_t vShift,
            const double *wb, const uint16_t *black);

#endif /* debayer_h */
