//
//  CR2Unslicer.m
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

#import "CR2Unslicer.h"
#import "CJPEGDecompressor.h"
#import "CJPEGDecompressor+Private.h"

#import "unslice.h"

@interface CR2Unslicer ()

// JPEG decompressor from which we'll read data
@property (nonatomic) CJPEGDecompressor *input;
// Output bit plane (interleaved)
@property (nonatomic) NSMutableData *output;

// Slice information
@property (nonatomic) NSArray<NSNumber *> *slicing;
// Sensor size
@property (nonatomic) CGSize sensorSize;

@end

@implementation CR2Unslicer

/**
 * Creates a new unslicer.
 */
- (instancetype) initWithInput:(CJPEGDecompressor *) input andOutput:(NSMutableData *) outBuf slicingInfo:(NSArray<NSNumber *> *) slices sensorSize:(CGSize) size {
    self = [super init];
    if (self) {
        self.input = input;
        self.output = outBuf;

        self.slicing = slices;
        self.sensorSize = size;
    }
    return self;
}

/**
 * Performs unslicing.
 */
- (void) unslice {
    int err;

    // get input pointers and slice info
    jpeg_decompressor_t *dec = self.input.dec;

    uint16_t slices[3] = {0, 0, 0};
    for(NSUInteger i = 0; i < 3; i++) {
        slices[i] = self.slicing[i].unsignedShortValue;
    }

    uint16_t *outPtr = self.output.mutableBytes;
    NSAssert(outPtr, @"Failed to get output pointer");

    // call into C code
    err = CR2Unslice(dec, outPtr, slices, self.sensorSize.width,
                     self.sensorSize.height);
    NSAssert(outPtr, @"Failed to unslice: %d", err);
}

/**
 * Calculates the bayer vertical shift.
 *
 * @param inBorders Array of border indices, starting with top and going cw.
 */
- (NSUInteger) calculateBayerShiftWithBorders:(NSArray<NSNumber *> *) inBorders {
    // validate inputs
    NSAssert(inBorders.count == 4, @"Invalid border array length: %lu", inBorders.count);
    
    // build inputs
    size_t borders[] = {
        inBorders[0].unsignedIntegerValue, inBorders[1].unsignedIntegerValue,
        inBorders[2].unsignedIntegerValue, inBorders[3].unsignedIntegerValue,
    };

    uint16_t *outPtr = self.output.mutableBytes;
    NSAssert(outPtr, @"Failed to get output pointer");
    
    return CR2CalculateBayerShift(outPtr, self.sensorSize.width, borders);
}

/**
 * Determine black level for each of the 4 bayer components
 */
- (NSArray<NSNumber *> *) calculateBlackLevelWithBorders:(NSArray<NSNumber *> *) inBorders {
    uint16_t outLevels[4];
    
    // convert borders
    NSAssert(inBorders.count == 4, @"Invalid border array length: %lu", inBorders.count);
    
    size_t borders[] = {
        inBorders[0].unsignedIntegerValue, inBorders[1].unsignedIntegerValue,
        inBorders[2].unsignedIntegerValue, inBorders[3].unsignedIntegerValue,
    };

    // get pointers
    uint16_t *plane = self.output.mutableBytes;
    NSAssert(plane, @"Failed to get output pointer");
    
    // do it
    CR2CalculateBlackLevel(plane, self.sensorSize.width,
                           self.sensorSize.height, borders, outLevels);
    
    // convert output
    NSMutableArray *arr = [NSMutableArray new];
    
    for (NSUInteger i = 0; i < 4; i++) {
        [arr addObject:@(outLevels[i])];
    }
    
    return [arr copy];
}

/**
 * Trims the image borders away.
 */
- (void) trimBorders:(NSArray<NSNumber *> *) inBorders {
    // validate inputs
    NSAssert(inBorders.count == 4, @"Invalid border array length: %lu", inBorders.count);
    
    // build inputs
    size_t borders[] = {
        inBorders[0].unsignedIntegerValue, inBorders[1].unsignedIntegerValue,
        inBorders[2].unsignedIntegerValue, inBorders[3].unsignedIntegerValue,
    };

    uint16_t *outPtr = self.output.mutableBytes;
    NSAssert(outPtr, @"Failed to get output pointer");
    
    // do it and resize the buffer
    size_t new = CR2Trim(outPtr, self.sensorSize.width, borders);
    NSAssert(new > 0, @"Failed to trim image");
    
    [self.output setLength:new];
}

@end
