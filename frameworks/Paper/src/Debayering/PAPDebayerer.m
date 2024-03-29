//
//  PAPDebayerer.m
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200621.
//

#import "PAPDebayerer.h"

#import "debayer.h"

@implementation PAPDebayerer

/**
 * Debayers the given 1 component input buffer into the provided 3 component RGB output buffer.
 */
+ (void) debayer:(NSData *) input withOutput:(NSMutableData *) output
       imageSize:(CGSize) size andAlgorithm:(NSUInteger) algo vShift:(NSUInteger) vShift
         wbShift:(NSArray<NSNumber *> *) inWb
      blackLevel:(NSArray<NSNumber *> *) inBlack {
    int err;
    
    // convert black level array
    NSAssert(inBlack.count <= 4, @"Invalid black level array: %@", inBlack);
    uint16_t black[4] = {0, 0, 0, 0};
    
    for (NSUInteger i = 0; i < inBlack.count; i++) {
        black[i] = inBlack[i].unsignedShortValue;
    }
    
    // convert wb shift array
    NSAssert(inWb.count <= 4, @"Invalid wb shift array: %@", inWb);
    double wb[4] = {1, 1, 1, 1};
    
    for (NSUInteger i = 0; i < inWb.count; i++) {
        wb[i] = inWb[i].doubleValue;
    }
    
    // get pointers
    const uint16_t *inPtr = input.bytes;
    NSAssert(inPtr, @"Failed to get input plane pointer");
    
    uint16_t *outPtr = output.mutableBytes;
    NSAssert(outPtr, @"Failed to get output plane pointer");
    
    NSAssert((algo == kBayerAlgorithmBilinear) || (algo == kBayerAlgorithmLMMSE),
             @"Invalid debayer algorithm: %lu", (unsigned long)algo);
    
    err = Debayer((debayer_algorithm_t) algo, inPtr, outPtr, size.width,
                  size.height, vShift, wb, black);
    NSAssert(err == 0, @"Failed to debayer: %d", err);
}

@end
