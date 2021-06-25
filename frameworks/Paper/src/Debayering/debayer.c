//
//  debayer.c
//  Paper (macOS)
//
//  Algorithms for extracting color information from single component raw image
//  files.
//
//  Created by Tristan Seifert on 20200620.
//

#include "debayer.h"

#include <stdint.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <time.h>
#include <math.h>

static inline size_t GetColor(size_t line, size_t col);

static void CopyAndApplyWB(const uint16_t *inPlane, uint16_t *outPlane,
                           size_t width, size_t height, size_t vShift,
                           const double *wb, const uint16_t *black);

// Debayering algorithms
static int InterpolateBilinear(const uint16_t *inPlane, uint16_t *outPlane, size_t width, size_t height, size_t vShift);
static int InterpolateLMMSE(const uint16_t *inPlane, uint16_t *outPlane, size_t width, size_t height, size_t vShift);

// MARK: Helpers
/**
 * Gets the bayer color for the given column and line.
 *
 * Color indices are distributed as follows:
 * - 0: Red
 * - 1-2: Green 0/1
 * - 3: Blue
 *
 * @return Color index, 0-3.
 */
static inline size_t GetColor(size_t line, size_t col) {
    return ((((line) & 1) << 1) | (col & 1));
}

// MARK: Debayering
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
            const double *wb, const uint16_t *black) {
    assert(inPlane);
    assert(outPlane);
    assert(wb);
    assert(black);
    
    // apply WB compensation and copy colors
    CopyAndApplyWB(inPlane, outPlane, width, height, vShift, wb, black);
    
    // invoke the appropriate algorithm
    switch(algo) {
        case kBayerAlgorithmBilinear:
            return InterpolateBilinear(inPlane, outPlane, width, height, vShift);

        case kBayerAlgorithmLMMSE:
            return InterpolateLMMSE(inPlane, outPlane, width, height, vShift);
    }
    
    
    // yeet
    return 0;
}

// MARK: White Balance
/**
 * Copies pixels from the single component input plane to the proper place in the output plane, while
 * applying white balance compensation and black levels.
 *
 * @param inPlane Input plane
 * @param outPlane Output plane
 * @param width Image width
 * @param height Image height
 * @param vShift Vertical shift for the debayering pattern
 * @param wb White balance multipliers for each of the 4 bayer elements
 * @param black Black level for each CFA index
 */
static void CopyAndApplyWB(const uint16_t *inPlane, uint16_t *outPlane,
                           size_t width, size_t height, size_t vShift,
                           const double *wb, const uint16_t *black) {
    size_t line, col;
    uint8_t color;
    size_t inRowOff, outRowOff;
    uint16_t inPixel;
    
    for(line = 0; line < height; line++) {
        inRowOff = (line * width);
        outRowOff = (line * width * 4);
        
        for(col = 0; col < width; col++) {
            // get input pixel value
            color = GetColor(line, col);
            inPixel = inPlane[inRowOff + col];
            
            // apply black level compensation
            if(inPixel > black[color]) {
                inPixel -= black[color];
            } else {
                inPixel = 0;
            }
            
            // multiply it by the white balance coefficient
            inPixel *= wb[color];
            
            // write to output
            outPlane[outRowOff + (col * 4) + color] = inPixel;
        }
    }
}

// MARK: Algorithms
#define PIXEL_INDEX(l,c,color) ((l)*width*4 + (c)*4 + color)
#define IMAGE_PIXEL(l,c,color) (outPlane[PIXEL_INDEX(l,c,color)])

#define RED_VALUE    0
#define GREEN1_VALUE 1
#define GREEN2_VALUE 2
#define BLUE_VALUE   3

/**
 * A super basic bilinear interpolation algorithm.
 */
static int InterpolateBilinear(const uint16_t *inPlane, uint16_t *outPlane, size_t width, size_t height, size_t vShift) {
    size_t line, column;
    
    // TODO: handle vShift
    // TODO: not be ugly fuckin code
    
    /* G1 interpolation, use G1 and G2 values */
      outPlane[ PIXEL_INDEX(0,0,GREEN1_VALUE) ] = ( IMAGE_PIXEL(1,0,GREEN2_VALUE) + IMAGE_PIXEL(0,1,GREEN1_VALUE) )/2; // top left corner (R)
      for(line=2; line<height; line+=2) // at R positions, center of a +
      for(column=2; column<width; column+=2)
            outPlane[ PIXEL_INDEX(line,column,GREEN1_VALUE) ] = ( IMAGE_PIXEL(line,column-1,GREEN1_VALUE) + IMAGE_PIXEL(line,column+1,GREEN1_VALUE)
              + IMAGE_PIXEL(line-1,column,GREEN2_VALUE) + IMAGE_PIXEL(line+1,column,GREEN2_VALUE) )/4;
      for(line=2; line<height; line+=2)  // first column at R positions
          outPlane[ PIXEL_INDEX(line,0,GREEN1_VALUE) ] = ( IMAGE_PIXEL(line-1,0,GREEN2_VALUE) + IMAGE_PIXEL(line+1,0,GREEN2_VALUE) + IMAGE_PIXEL(line,1,GREEN1_VALUE) )/3;
    for(column=2; column<width; column+=2)  // first line at R positions
        outPlane[ PIXEL_INDEX(0,column,GREEN1_VALUE) ] = ( IMAGE_PIXEL(0,column-1,GREEN1_VALUE) + IMAGE_PIXEL(0,column+1,GREEN1_VALUE) + IMAGE_PIXEL(1,column,GREEN2_VALUE) )/3;
          
      outPlane[ PIXEL_INDEX(height-1,width-1,GREEN1_VALUE) ] = ( IMAGE_PIXEL(height-2,width-1,GREEN1_VALUE)
        + IMAGE_PIXEL(height-1,width-2,GREEN2_VALUE) )/2;    // bottom right corner (B)
    
      for(line=1; line<height-1; line+=2) // at B positions, center of a +
      for(column=1; column<width-1; column+=2)
            outPlane[ PIXEL_INDEX(line,column,GREEN1_VALUE) ] = ( IMAGE_PIXEL(line-1,column,GREEN1_VALUE) + IMAGE_PIXEL(line+1,column,GREEN1_VALUE)
              + IMAGE_PIXEL(line,column-1,GREEN2_VALUE) + IMAGE_PIXEL(line,column+1,GREEN2_VALUE) )/4;
    
    for(column=1; column<width-1; column+=2)  // last line at B positions
       outPlane[ PIXEL_INDEX(height-1,column,GREEN1_VALUE) ] = ( IMAGE_PIXEL(height-2,column,GREEN1_VALUE)
       + IMAGE_PIXEL(height-1,column-1,GREEN2_VALUE) + IMAGE_PIXEL(height-1,column+1,GREEN2_VALUE) )/3;
      for(line=1; line<height-1; line+=2)  // last column at B positions
          outPlane[ PIXEL_INDEX(line,width-1,GREEN1_VALUE) ] = ( IMAGE_PIXEL(line-1,width-1,GREEN1_VALUE)
          + IMAGE_PIXEL(line+1,width-1,GREEN1_VALUE) + IMAGE_PIXEL(line,width-2,GREEN2_VALUE) )/3;
    
    // copy G2 into G1
    for(line=1; line<height; line+=2) {
        for(column=0; column<width; column+=2) {
            outPlane[ PIXEL_INDEX(line,column,GREEN1_VALUE) ] = IMAGE_PIXEL(line,column,GREEN2_VALUE);
        }
    }
    // copy G1 into G2
    for(line=0; line<height; line+=2) {
        for(column=1; column<width; column+=2) {
            outPlane[ PIXEL_INDEX(line,column,GREEN2_VALUE) ] = IMAGE_PIXEL(line,column,GREEN1_VALUE);
        }
    }

      /* R interpolation */
      for(line=1; line<height-1; line+=2) // at B positions, center of an X
      for(column=1; column<width-1; column+=2)
            outPlane[ PIXEL_INDEX(line,column,RED_VALUE) ] = ( IMAGE_PIXEL(line-1,column-1,RED_VALUE) + IMAGE_PIXEL(line-1,column+1,RED_VALUE)
              + IMAGE_PIXEL(line+1,column-1,RED_VALUE) + IMAGE_PIXEL(line+1,column+1,RED_VALUE) ) / 4 ;
    for(column=1; column<width-1; column+=2)  // last line at B positions
          outPlane[ PIXEL_INDEX(height-1,column,RED_VALUE) ] = ( IMAGE_PIXEL(height-2,column-1,RED_VALUE) + IMAGE_PIXEL(height-2,column+1,RED_VALUE) )/ 2;
      for(line=1; line<height-1; line+=2)  // last column at B positions
          outPlane[ PIXEL_INDEX(line,width-1,RED_VALUE) ] = ( IMAGE_PIXEL(line-1,width-2,RED_VALUE) + IMAGE_PIXEL(line+1,width-2,RED_VALUE) ) / 2;
      outPlane[ PIXEL_INDEX(height-1,width-1,RED_VALUE) ] = IMAGE_PIXEL(height-2,width-2,RED_VALUE); // bottom right corner (B)
          
      for(line=0; line<height; line+=2)  // last column at G positions
          outPlane[ PIXEL_INDEX(line,width-1,RED_VALUE) ] = IMAGE_PIXEL(line,width-2,RED_VALUE);
      for(line=1; line<height-1; line+=2) // at G positions, R values are on same column
      for(column=0; column<width; column+=2)
            outPlane[ PIXEL_INDEX(line,column,RED_VALUE) ] = ( IMAGE_PIXEL(line-1,column,RED_VALUE) + IMAGE_PIXEL(line+1,column,RED_VALUE) ) / 2;
      for(line=0; line<height; line+=2) // at G positions, R values are on same line
      for(column=1; column<width-1; column+=2)
            outPlane[ PIXEL_INDEX(line,column,RED_VALUE) ] = ( IMAGE_PIXEL(line,column-1,RED_VALUE) + IMAGE_PIXEL(line,column+1,RED_VALUE) ) / 2;
    for(column=0; column<width-1; column+=2)  // last line at G positions, R on top
          outPlane[ PIXEL_INDEX(height-1,column,RED_VALUE) ] = IMAGE_PIXEL(height-2,column,RED_VALUE);

      /* B interpolation */
      for(line=2; line<height-1; line+=2) // at R positions, center of an X
      for(column=2; column<width-1; column+=2)
            outPlane[ PIXEL_INDEX(line,column,BLUE_VALUE) ] = ( IMAGE_PIXEL(line-1,column-1,BLUE_VALUE) + IMAGE_PIXEL(line-1,column+1,BLUE_VALUE)
              + IMAGE_PIXEL(line+1,column-1,BLUE_VALUE) + IMAGE_PIXEL(line+1,column+1,BLUE_VALUE) )  /4;
      for(line=2; line<height-1; line+=2) // at G positions, B values are on same column
      for(column=1; column<width; column+=2)
            outPlane[ PIXEL_INDEX(line,column,BLUE_VALUE) ] = ( IMAGE_PIXEL(line-1,column,BLUE_VALUE) + IMAGE_PIXEL(line+1,column,BLUE_VALUE) ) /2;
      for(line=1; line<height; line+=2) // at G positions, B values are on same line
      for(column=2; column<width; column+=2)
            outPlane[ PIXEL_INDEX(line,column,BLUE_VALUE) ] = ( IMAGE_PIXEL(line,column-1,BLUE_VALUE) + IMAGE_PIXEL(line,column+1,BLUE_VALUE) ) /2;
    for(column=1; column<width; column+=2)  // first line at G positions, B on bottom
        outPlane[ PIXEL_INDEX(0,column,BLUE_VALUE) ] = IMAGE_PIXEL(1,column,BLUE_VALUE);
      for(line=1; line<height; line+=2)  // first column at G positions, B on right
        outPlane[ PIXEL_INDEX(line,0,BLUE_VALUE) ] = IMAGE_PIXEL(line,1,BLUE_VALUE);
      outPlane[ PIXEL_INDEX(0,0,BLUE_VALUE) ] = IMAGE_PIXEL(1,1,BLUE_VALUE); // top left corner
    for(column=2; column<width; column+=2)  // first line at R positions
        outPlane[ PIXEL_INDEX(0,column,BLUE_VALUE) ] = ( IMAGE_PIXEL(1,column-1,BLUE_VALUE) + IMAGE_PIXEL(1,column+1,BLUE_VALUE) ) /2;
      for(line=2; line<height-1; line+=2)  // first column at R positions
        outPlane[ PIXEL_INDEX(line,0,BLUE_VALUE) ] = ( IMAGE_PIXEL(line-1,1,BLUE_VALUE) + IMAGE_PIXEL(line+1,1,BLUE_VALUE) ) /2;

    // try to convert it into 3 component rgb
    //uint16_t temp[4];
    size_t rowOff;
    
    for(line = 0; line < height; line++) {
        rowOff = (line * width * 4);
        
        for(column = 0; column < width; column++) {
            // read blue pixel value
            uint16_t blue = outPlane[rowOff + (column * 4) + 3];
            
            // copy whatever green channel isn't zero
            if(outPlane[rowOff + (column * 4) + 1] == 0) {
                outPlane[rowOff + (column * 4) + 1] = outPlane[rowOff + (column * 4) + 2];
            }
            
            // write the blue pixel value in the correct component
            outPlane[rowOff + (column * 4) + 2] = blue;
            
            // clear alpha
            // outPlane[rowOff + (column * 4) + 3] = 0xFFFF;
        }
    }
    
    // done
    return 0;
}

/**
 * LSMME demosaicing algorithm
 * L. Zhang and X. Wu,
 * Color demosaicking via directional linear minimum mean square-error estimation, IEEE Trans. on Image Processing, vol. 14,
 * pp. 2167-2178, Dec. 2005.
 */
/**
 * Set to 1 to evaluate the time taken for various subcomponents of the LMMSE interpolation.
 */
#define LMMSE_DEBUG_TIME_PROFILE    1

/**
 * Set to 0 to disable the median filter. It takes up a _massive_ amount of processing time (more than thrice than every other part of the
 * algorithm) but has a very negligible impact on the final image.
 */
#define LMMSE_USE_MEDIAN_FILTER    0

#define PIX_SORT(a,b) { if ((a)>(b)) {temp=(a);(a)=(b);(b)=temp;} }
#define FC(row, col, filters)  (filters >> ((((row) << 1 & 14) + ((col) & 1)) << 1) & 3)
#define MIN(a,b) ((a) < (b) ? (a) : (b))
#define MAX(a,b) ((a) > (b) ? (a) : (b))
#define LIM(x,min,max) MAX(min,MIN(x,max))
#define ULIM(x,y,z) ((y) < (z) ? LIM(x,y,z) : LIM(x,z,y))
#define CLIP(x) LIM((int)(x),0,65535)
//#define FC(row,col,filters) GetColor(row,col)

static int InterpolateLMMSE(const uint16_t *inPlane, uint16_t *outPlane, size_t width, size_t height, size_t vShift) {
    int row, col, c, w1, w2, w3, w4, ii, ba, rr1, cc1, rr, cc;
    float h0, h1, h2, h3, h4, hs;
    float p1, p2, p3, p4, p5, p6, p7, p8, p9;
    float Y, v0, mu, vx, vn, xh, vh, xv, vv;
    float (*rix)[6], (*qix)[6];
    char  *buffer;
    
#if USE_MEDIAN_FILTER
    int d, pass;
    float temp;
#endif
    
#if LMMSE_DEBUG_TIME_PROFILE
    clock_t t1, t2;
    t2 = clock();
    
    fprintf(stderr, "Begin lmmse_interpolate: %f s\n", ((double) t2) / CLOCKS_PER_SEC);
#endif
    
    // read out a bunch of data (TODO: lol)
    unsigned int filters = 0x94949494;
    
    // allocate work with boundary
    ba = 10;
    rr1 = height + (2 * ba);
    cc1 = width + (2 * ba);
    
    buffer = (char *) calloc(rr1*cc1*6*sizeof(float), 1);
    
    // merror(buffer,"lmmse_interpolate()");
    qix = (float (*)[6])buffer;
    
    // indices
    w1 = cc1;
    w2 = 2*w1;
    w3 = 3*w1;
    w4 = 4*w1;
    
    // define low pass filter (sigma=2, L=4)
    h0 = 1.0;
    h1 = exp( -1.0/8.0);
    h2 = exp( -4.0/8.0);
    h3 = exp( -9.0/8.0);
    h4 = exp(-16.0/8.0);
    hs = h0 + 2.0*(h1 + h2 + h3 + h4);
    h0 /= hs;
    h1 /= hs;
    h2 /= hs;
    h3 /= hs;
    h4 /= hs;
    
    // copy CFA values
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for(rr = 0; rr < rr1; rr++) {
        for(cc = 0, row = (rr - ba); cc < cc1; cc++) {
            col = cc - ba;
            rix = qix + rr*cc1 + cc;
            
            if((row >= 0) & (row < height) & (col >= 0) & (col < width)) {
//                rix[0][4] = (double)image[row*width+col][FC(row,col,filters)]/65535.0;
//                rix[0][4] = ((double) inPlane[(row * width) + col]) / 65535.0;
                rix[0][4] = ((double) outPlane[(row * width * 4) + (col * 4) + FC(row,col,filters)]) / 65535.0;
            } else {
                rix[0][4] = 0;
            }
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tcopy CFA values: %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
    
    // G-R(B)
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for(rr = 2; rr < (rr1 - 2); rr++) {
        // G-R(B) at R(B) location
        for(cc = 2+(FC(rr,2,filters)&1); cc < (cc1 - 2); cc += 2) {
            rix = qix + rr*cc1 + cc;
            
            // v0 = 0.25R + 0.25B, Y = 0.25R + 0.5B + 0.25B
            v0 = 0.0625*(rix[-w1-1][4]+rix[-w1+1][4]+rix[w1-1][4]+rix[w1+1][4]) +
            0.25*rix[0][4];
            
            // horizontal
            rix[0][0] = -0.25*(rix[ -2][4] + rix[ 2][4])
            + 0.5*(rix[ -1][4] + rix[0][4] + rix[ 1][4]);
            Y = v0 + 0.5*rix[0][0];
            
            if(rix[0][4] > 1.75*Y) {
                rix[0][0] = ULIM(rix[0][0],rix[ -1][4],rix[ 1][4]);
            } else {
                rix[0][0] = LIM(rix[0][0],0.0,1.0);
            }
            
            rix[0][0] -= rix[0][4];
            // vertical
            rix[0][1] = -0.25*(rix[-w2][4] + rix[w2][4])
            + 0.5*(rix[-w1][4] + rix[0][4] + rix[w1][4]);
            Y = v0 + 0.5*rix[0][1];
            
            if(rix[0][4] > 1.75*Y) {
                rix[0][1] = ULIM(rix[0][1],rix[-w1][4],rix[w1][4]);
            } else {
                rix[0][1] = LIM(rix[0][1],0.0,1.0);
            }
            
            rix[0][1] -= rix[0][4];
        }
        
        // G-R(B) at G location
        for(cc = 2+(FC(rr,3,filters)&1); cc < (cc1 - 2); cc += 2) {
            rix = qix + rr*cc1 + cc;
            rix[0][0] = 0.25*(rix[ -2][4] + rix[ 2][4])
            - 0.5*(rix[ -1][4] + rix[0][4] + rix[ 1][4]);
            rix[0][1] = 0.25*(rix[-w2][4] + rix[w2][4])
            - 0.5*(rix[-w1][4] + rix[0][4] + rix[w1][4]);
            rix[0][0] = LIM(rix[0][0],-1.0,0.0) + rix[0][4];
            rix[0][1] = LIM(rix[0][1],-1.0,0.0) + rix[0][4];
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tG-R(B): %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
    
    // apply low pass filter on differential colors
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for(rr = 4; rr < (rr1 - 4); rr++) {
        for (cc = 4; cc < (cc1 - 4); cc++) {
            rix = qix + rr*cc1 + cc;
            rix[0][2] = h0*rix[0][0] +
            h1*(rix[ -1][0] + rix[ 1][0]) + h2*(rix[ -2][0] + rix[ 2][0]) +
            h3*(rix[ -3][0] + rix[ 3][0]) + h4*(rix[ -4][0] + rix[ 4][0]);
            rix[0][3] = h0*rix[0][1] +
            h1*(rix[-w1][1] + rix[w1][1]) + h2*(rix[-w2][1] + rix[w2][1]) +
            h3*(rix[-w3][1] + rix[w3][1]) + h4*(rix[-w4][1] + rix[w4][1]);
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tLow pass filter on differential colors: %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
    
    // interpolate G-R(B) at R(B)
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for (rr = 4; rr < (rr1 - 4); rr++) {
        for (cc = 4+(FC(rr,4,filters)&1); cc < (cc1 - 4); cc += 2) {
            rix = qix + rr*cc1 + cc;
            // horizontal
            mu = (rix[-4][2] + rix[-3][2] + rix[-2][2] + rix[-1][2] + rix[0][2]+
                  rix[ 1][2] + rix[ 2][2] + rix[ 3][2] + rix[ 4][2]) / 9.0;
            p1 = rix[-4][2] - mu;
            p2 = rix[-3][2] - mu;
            p3 = rix[-2][2] - mu;
            p4 = rix[-1][2] - mu;
            p5 = rix[ 0][2] - mu;
            p6 = rix[ 1][2] - mu;
            p7 = rix[ 2][2] - mu;
            p8 = rix[ 3][2] - mu;
            p9 = rix[ 4][2] - mu;
            vx = 1e-7+p1*p1+p2*p2+p3*p3+p4*p4+p5*p5+p6*p6+p7*p7+p8*p8+p9*p9;
            p1 = rix[-4][0] - rix[-4][2];
            p2 = rix[-3][0] - rix[-3][2];
            p3 = rix[-2][0] - rix[-2][2];
            p4 = rix[-1][0] - rix[-1][2];
            p5 = rix[ 0][0] - rix[ 0][2];
            p6 = rix[ 1][0] - rix[ 1][2];
            p7 = rix[ 2][0] - rix[ 2][2];
            p8 = rix[ 3][0] - rix[ 3][2];
            p9 = rix[ 4][0] - rix[ 4][2];
            vn = 1e-7+p1*p1+p2*p2+p3*p3+p4*p4+p5*p5+p6*p6+p7*p7+p8*p8+p9*p9;
            xh = (rix[0][0]*vx + rix[0][2]*vn)/(vx + vn);
            vh = vx*vn/(vx + vn);
            
            // vertical
            mu = (rix[-w4][3] + rix[-w3][3] + rix[-w2][3] + rix[-w1][3] + rix[0][3]+
                  rix[ w1][3] + rix[ w2][3] + rix[ w3][3] + rix[ w4][3]) / 9.0;
            p1 = rix[-w4][3] - mu;
            p2 = rix[-w3][3] - mu;
            p3 = rix[-w2][3] - mu;
            p4 = rix[-w1][3] - mu;
            p5 = rix[  0][3] - mu;
            p6 = rix[ w1][3] - mu;
            p7 = rix[ w2][3] - mu;
            p8 = rix[ w3][3] - mu;
            p9 = rix[ w4][3] - mu;
            vx = 1e-7+p1*p1+p2*p2+p3*p3+p4*p4+p5*p5+p6*p6+p7*p7+p8*p8+p9*p9;
            p1 = rix[-w4][1] - rix[-w4][3];
            p2 = rix[-w3][1] - rix[-w3][3];
            p3 = rix[-w2][1] - rix[-w2][3];
            p4 = rix[-w1][1] - rix[-w1][3];
            p5 = rix[  0][1] - rix[  0][3];
            p6 = rix[ w1][1] - rix[ w1][3];
            p7 = rix[ w2][1] - rix[ w2][3];
            p8 = rix[ w3][1] - rix[ w3][3];
            p9 = rix[ w4][1] - rix[ w4][3];
            vn = 1e-7+p1*p1+p2*p2+p3*p3+p4*p4+p5*p5+p6*p6+p7*p7+p8*p8+p9*p9;
            xv = (rix[0][1]*vx + rix[0][3]*vn)/(vx + vn);
            vv = vx*vn/(vx + vn);
            // interpolated G-R(B)
            rix[0][4] = (xh*vv + xv*vh)/(vh + vv);
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tInterpolate G-R(B) at R(B): %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
    
    // copy CFA values
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for(rr = 0; rr < rr1; rr++) {
        for(cc = 0, row = (rr-ba); cc < cc1; cc++) {
            col=cc-ba;
            rix = qix + rr*cc1 + cc;
            c = FC(rr,cc,filters);
            
            if ((row >= 0) & (row < height) & (col >= 0) & (col < width)) {
//                rix[0][c] = (double)image[row*width+col][c]/65535.0;
//                rix[0][c] = (double) inPlane[(row * width) + col] / 65535.0;
                rix[0][c] = ((double) outPlane[(row * width * 4) + (col * 4) + c]) / 65535.0;
            } else {
                rix[0][c] = 0;
            }
            
            if(c != 1) {
                rix[0][1] = rix[0][c] + rix[0][4];
            }
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tCopy CFA values: %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
    
    // bilinear interpolation for R/B
    // interpolate R/B at G location
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for(rr = 1; rr < (rr1 - 1); rr++) {
        for(cc=1+(FC(rr,2,filters)&1), c=FC(rr,cc+1,filters); cc < cc1-1; cc+=2) {
            rix = qix + rr*cc1 + cc;
            rix[0][c] = rix[0][1]
            + 0.5*(rix[ -1][c] - rix[ -1][1] + rix[ 1][c] - rix[ 1][1]);
            c = 2 - c;
            rix[0][c] = rix[0][1]
            + 0.5*(rix[-w1][c] - rix[-w1][1] + rix[w1][c] - rix[w1][1]);
            c = 2 - c;
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tInterpolate R/B at G location: %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
    
    // interpolate R/B at B/R location
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for(rr = 1; rr < (rr1 -1 ); rr++) {
        for(cc=1+(FC(rr,1,filters)&1), c=2-FC(rr,cc,filters); cc < cc1-1; cc+=2) {
            rix = qix + rr*cc1 + cc;
            rix[0][c] = rix[0][1]
            + 0.25*(rix[-w1][c] - rix[-w1][1] + rix[ -1][c] - rix[ -1][1]+
                    rix[  1][c] - rix[  1][1] + rix[ w1][c] - rix[ w1][1]);
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tInterpolate R/B at B/R location: %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
    
#if LMMSE_USE_MEDIAN_FILTER
#if LMMSE_DEBUG_TIME_PROFILE
    // median filter
    t1 = clock();
#endif
    
    for(pass = 1; pass <= 3; pass++) {
        for(c = 0; c < 3; c += 2) {
            // Compute median(R-G) and median(B-G)
            d = c + 3;
            for(ii = 0; ii < (rr1 * cc1); ii++) {
                qix[ii][d] = qix[ii][c] - qix[ii][1];
            }
            
            // Apply 3x3 median fileter
            for(rr = 1; rr < (rr1 - 1); rr++) {
                for(cc = 1; cc < (cc1 - 1); cc++) {
                    rix = qix + rr*cc1 + cc;
                    // Assign 3x3 differential color values
                    p1 = rix[-w1-1][d]; p2 = rix[-w1][d]; p3 = rix[-w1+1][d];
                    p4 = rix[   -1][d]; p5 = rix[  0][d]; p6 = rix[    1][d];
                    p7 = rix[ w1-1][d]; p8 = rix[ w1][d]; p9 = rix[ w1+1][d];
                    
                    // Sort for median of 9 values
                    PIX_SORT(p2,p3); PIX_SORT(p5,p6); PIX_SORT(p8,p9);
                    PIX_SORT(p1,p2); PIX_SORT(p4,p5); PIX_SORT(p7,p8);
                    PIX_SORT(p2,p3); PIX_SORT(p5,p6); PIX_SORT(p8,p9);
                    PIX_SORT(p1,p4); PIX_SORT(p6,p9); PIX_SORT(p5,p8);
                    PIX_SORT(p4,p7); PIX_SORT(p2,p5); PIX_SORT(p3,p6);
                    PIX_SORT(p5,p8); PIX_SORT(p5,p3); PIX_SORT(p7,p5);
                    PIX_SORT(p5,p3);
                    
                    rix[0][4] = p5;
                }
            }
            
            for(ii = 0; ii < (rr1 * cc1); ii++) {
                qix[ii][d] = qix[ii][4];
            }
        }
        
        // red/blue at GREEN pixel locations
        for(rr = 0; rr < rr1; rr++) {
            for(cc=(FC(rr,1,filters)&1), c=FC(rr,cc+1,filters); cc < cc1; cc+=2) {
                rix = qix + rr*cc1 + cc;
                rix[0][0] = rix[0][1] + rix[0][3];
                rix[0][2] = rix[0][1] + rix[0][5];
            }
        }
        
        // red/blue and green at BLUE/RED pixel locations
        for(rr = 0; rr < rr1; rr++) {
            for(cc=(FC(rr,0,filters)&1), c=2-FC(rr,cc,filters), d=c+3; cc < cc1; cc+=2) {
                rix = qix + rr*cc1 + cc;
                rix[0][c] = rix[0][1] + rix[0][d];
                rix[0][1] = 0.5*(rix[0][0] - rix[0][3] + rix[0][2] - rix[0][5]); }
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tMedian filter: %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
#endif
#endif
    
    // copy result back to image matrix
#if LMMSE_DEBUG_TIME_PROFILE
    t1 = clock();
#endif
    
    for(row = 0; row < height; row++) {
        for(col = 0, rr= (row + ba); col < width; col++) {
            cc = col + ba;
            rix = qix + rr*cc1 + cc;
            c = FC(row, col, filters);
            
            for(ii = 0; ii < 3; ii++) {
                if(ii != c) {
                    outPlane[row*width*4 + col*4 + ii] = CLIP((int) (65535.0 * rix[0][ii] + 0.5));
                }
            }
        }
    }
    
#if LMMSE_DEBUG_TIME_PROFILE
    fprintf(stderr, "\tCopy result to image matrix: %f s\n", ((double)(clock() - t1)) / CLOCKS_PER_SEC);
    fprintf(stderr, "Total time for lmmse_interpolate: %f s\n", ((double)(clock() - t2)) / CLOCKS_PER_SEC);
#endif
    
    // Done
    free(buffer);
    return 0;
}
