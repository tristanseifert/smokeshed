//
//  colorspace.c
//  Paper (macOS)
//
//  Functions to convert debayered RGB data (data obtained by black level
//  compensation, white balance adjustments, and debayering) from the camera
//  specific color spaces to the working color space.
//
//  The ProPhoto RGB color space is used as working space.
//
//  Created by Tristan Seifert on 20200621.
//

#include "colorspace.h"

#include <stdio.h>

#include <Accelerate/Accelerate.h>

// MARK: Declarations
static void MakeConversionMatrix(const double *camXyz, double *outCam);

static void MatrixPseudoInverse3x3(const double *in, double *out);


static long MakePlanarF(uint16_t *pixels, size_t width, size_t height,
                       vImage_Buffer *buffers);
static long MakeChunky(uint16_t *outPixels, size_t width, size_t height,
                       vImage_Buffer *buffers);
static long MultiplyImage(vImage_Buffer *buffers, size_t width, size_t height,
                          const double *rgbCam);

// MARK: - Constants
/// Conversion matrix to go from RGB to XYX
const double RgbToXyzMatrix[3][3] = {
    { 0.412453, 0.357580, 0.180423 },
    { 0.212671, 0.715160, 0.072169 },
    { 0.019334, 0.119193, 0.950227 },
};
/// D65 illuminant
const double D65White[3] = {
    0.950456, 1, 1.088754
};
/// D50 illuminant
const double D50White[3] = {
    0.964220, 1.000000, 0.825210
};

/// Conversion matrix to go from camera RGB to ProPhoto RGB
static const double ProPhotoRgbMatrix[3][3] = {
    // Bruce Lindbloom matrix
//    {0.797675,  0.288040, 0.000000 },
//    {0.135192,  0.711874, 0.000000 },
//    {0.0313534, 0.000086, 0.825210 },
    // Bruce Lindbloom matrix adapted for D65
//    { 0.529304, 0.098366, 0.016882 },
//    { 0.330076, 0.873468, 0.117673 },
//    { 0.140602, 0.028168, 0.865572 },
    // dcraw matrix
    { 0.529317, 0.330092, 0.140588 },
    { 0.098368, 0.873465, 0.028169 },
    { 0.016879, 0.117663, 0.865457 },
};

// MARK: - Conversion
/**
 * Converts RGB pixel data to the working color space, in place. The pixel buffer will contain 32-bit floating
 * point image components when done, so it should be sized appropriately.
 *
 * @param pixels The 3-component pixel buffer
 * @param width Number of pixels per line
 * @param height Total number of lines
 * @param camXyz Camera-specific 3x3 conversion matrix
 */
long ConvertToWorking(uint16_t *pixels, size_t width, size_t height,
                 const double *camXyz) {
    long err = 0;
    
    vImage_Buffer buffers[3];
    memset(buffers, 0, sizeof(buffers));
    
    // calculate the output matrix to convert to working space
    double outCam[3][3];
    MakeConversionMatrix(camXyz, (double *) outCam);

    // create buffers for each component and copy data in
    err = MakePlanarF(pixels, width, height, buffers);
    if(err != 0) {
        fprintf(stderr, "MakePlanar() failed: %lu\n", err);
        goto cleanup;
    }
    
    // multiply by matrix
    err = MultiplyImage(buffers, width, height, (double *) outCam);
    if(err != 0) {
        fprintf(stderr, "MultiplyImage() failed: %lu\n", err);
        goto cleanup;
    }
    
    // copy buffers back into output planes
    err = MakeChunky(pixels, width, height, buffers);
    if(err != 0) {
        fprintf(stderr, "MakeChunky() failed: %lu\n", err);
        goto cleanup;
    }
    
cleanup:;
    // deallocate vImage buffers
    for (int i = 0; i < 3; i++) {
        if (buffers[i].data) {
            free(buffers[i].data);
        }
    }
    
    return err;
}

// MARK: Matrix helpers
/**
 * Derives the matrix necessary for converting pixel data from the sensor color space to our working color
 * space.
 *
 * @param camXyz Camera-specific XYZ conversion matrix
 * @param outCam Output color conversion matrix
 */
static void MakeConversionMatrix(const double *camXyz, double *outCam) {
    size_t i, j;
    double num;
    
    // multiply the cam to xyz matrix by the xyz to prophoto matrix
    double temp[3][3];
    
    vDSP_mmulD(camXyz, 1, (double *) ProPhotoRgbMatrix, 1, (double *) temp, 1,
               3, 3, 3);
               
       // normalization step
       for (i=0; i < 3; i++) {
           // sum up the entire column
           num = 0;
           for (j = 0; j < 3; j++) {
               num += temp[i][j];
           }
           
           // divide each column value by that
           for (j = 0; j < 3; j++) {
               temp[i][j] /= num;
           }
       }
    
    // inverse that shit
    MatrixPseudoInverse3x3((double *) temp, outCam);
}

/**
 * Calculates the pseudo inverse of a matrix
 */
static void MatrixPseudoInverse3x3(const double *in, double *out) {
    double work[3][6], num;
    int i, j, k;

    for (i=0; i < 3; i++) {
      for (j=0; j < 6; j++)
        work[i][j] = j == i+3;
      for (j=0; j < 3; j++)
        for (k=0; k < 3; k++)
      work[i][j] += in[(k*3)+i] * in[(k*3)+j];
    }
    for (i=0; i < 3; i++) {
      num = work[i][i];
      for (j=0; j < 6; j++)
        work[i][j] /= num;
      for (k=0; k < 3; k++) {
        if (k==i) continue;
        num = work[k][i];
        for (j=0; j < 6; j++)
      work[k][j] -= work[i][j] * num;
      }
    }
    for (i=0; i < 3; i++)
      for (j=0; j < 3; j++)
        for (out[(i*3)+j]=k=0; k < 3; k++)
      out[(i*3)+j] += work[j][k+3] * in[(i*3)+k];
    
}

// MARK: vImage buffer helpers
/**
 * Allocates buffers for each image component, and performs the interleaved -> planar conversion. During
 * this process, each of the input components is converted from a 16-bit unsigned quantity to a floating
 * point component.
 */
static long MakePlanarF(uint16_t *pixels, size_t width, size_t height,
                        vImage_Buffer *buffers) {
    assert(buffers);
    
    size_t line, col, comp;
    uint16_t temp;
    float converted;
    vImage_Error vErr = kvImageNoError;
    
    // allocate the output buffers
    for (comp = 0; comp < 3; comp++) {
        vErr = vImageBuffer_Init(&buffers[comp], height, width, 32, 0);
        
        if (vErr != kvImageNoError) {
            return vErr;
        }
    }
    
    // unpack the chunky input buffer while converting to float
    uint16_t *readPtr = pixels;
    float *writePtrs[3] = {
        buffers[0].data, buffers[1].data, buffers[2].data,
    };
    
    for (line = 0; line < height; line++) {
        for (col = 0; col < width; col++) {
            // for each component
            for (comp = 0; comp < 3; comp++) {
                temp = *readPtr++;
                converted = ((double) temp) / 16384.0; // 14 bits
                *writePtrs[comp]++ = converted;
            }
        }
    }
    
    // clean up
cleanup:;
    return vErr;
}

/**
 * Converts the working planar buffers back into interleaved format.
 */
static long MakeChunky(uint16_t *outPixels, size_t width, size_t height,
                       vImage_Buffer *buffers) {
    assert(buffers);
   
    vImage_Error vErr;
    
    // create struct for output buffer
    vImage_Buffer out = {
        .width = width,
        .height = height,
        .rowBytes = (width * 3 * 4),
        .data = outPixels
    };
    
    // perform conversion
    vErr = vImageConvert_PlanarFtoRGBFFF(&buffers[0], &buffers[1], &buffers[2],
                                         &out, 0);
    
    return vErr;
}

/**
 * Multiplies each pixel in the image by the specified matrix.
 */
static long MultiplyImage(vImage_Buffer *buffers, size_t width, size_t height,
                          const double *inRgbCam) {
    assert(inRgbCam);
    
    vImage_Error vErr;
    
    // convert matrix to single precision float
    float rgbCam[9];
    for (size_t i = 0; i < 9; i++) {
        rgbCam[i] = (float) inRgbCam[i];
    }
    
    // perform multiplication
    const vImage_Buffer *bufArray[] = {
        &buffers[0], &buffers[1], &buffers[2]
    };
    
    vErr = vImageMatrixMultiply_PlanarF(bufArray, bufArray, 3, 3,
                                        (float *) rgbCam, NULL, NULL, 0);
    
    return vErr;
}
