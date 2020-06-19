//
//  CR2Unslicer.m
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

#import "CR2Unslicer.h"
#import "CJPEGDecompressor.h"
#import "CJPEGDecompressor+Private.h"
#import "Logging.h"

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
    decompressor_t *dec = self.input.dec;

    uint16_t slices[3] = {0, 0, 0};
    for(NSUInteger i = 0; i < 3; i++) {
        slices[i] = self.slicing[i].unsignedShortValue;
    }

    uint16_t *outPtr = self.output.mutableBytes;
    DDAssert(outPtr, @"Failed to get output pointer");

    // call into C code
    err = CR2Unslice(dec, outPtr,
                     slices, self.sensorSize.width,
                     self.sensorSize.height);
    DDAssert(outPtr, @"Failed to unslice: %d", err);
}

@end
