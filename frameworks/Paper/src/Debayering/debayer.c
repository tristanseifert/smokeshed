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
#include <stddef.h>

static inline size_t GetColor(size_t line, size_t col);

// Debayering algorithms
static int InterpolateBilinear(const uint16_t *inPlane, uint16_t *outPlane, size_t width, size_t height, size_t vShift);

// MARK: Constants
/// Maps a Bayer component to output image component index, assuming RGB layout.
static const uint8_t ColorOutputMap[] = { 0, 1, 1, 2 };

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
 */
int Debayer(debayer_algorithm_t algo, const uint16_t *inPlane,
            uint16_t *outPlane, size_t width, size_t height, size_t vShift) {
    size_t col, row;
    size_t inRowOff, outRowOff;
    uint8_t colorOff;
    uint16_t temp;
    
    // copy the color values we have to the output buffer
    for (row = 0; row < height; row++) {
        inRowOff = (row * width);
        outRowOff = (row * width * 4);
        
        for (col = 0; col < width; col++) {
//            colorOff = ColorOutputMap[GetColor(row + vShift, col)];
            colorOff = GetColor(row + vShift, col);
            
            temp = inPlane[inRowOff + col];
            outPlane[outRowOff + (col * 4) + colorOff] = temp;
        }
    }
    
    // invoke the appropriate algorithm
    switch(algo) {
        case kBayerAlgorithmBilinear:
            return InterpolateBilinear(inPlane, outPlane, width, height, vShift);
    }
    
    
    // yeet
    return 0;
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
    uint16_t temp[4];
    size_t inRowOff, outRowOff;
    
    for(line = 0; line < height; line++) {
        inRowOff = (line * width * 4);
        outRowOff = (line * width * 3);
        
        for(column = 0; column < width; column++) {
            // read 4 16-bit values
            for(int i = 0; i < 4; i++) {
                temp[i] = outPlane[inRowOff + (column * 4) + i];
            }
            
            // copy red and blue; these never change
            outPlane[outRowOff + (column * 3)] = temp[0];
            outPlane[outRowOff + (column * 3) + 2] = temp[3];
            
            // copy whatever green channel isn't zero
            if(temp[1]) {
                outPlane[outRowOff + (column * 3) + 1] = temp[1];
            } else {
                outPlane[outRowOff + (column * 3) + 1] = temp[2];
            }
        }
    }
    
    // done
    return 0;
}
