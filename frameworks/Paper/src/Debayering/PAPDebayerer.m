//
//  PAPDebayerer.m
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200621.
//

#import "PAPDebayerer.h"

#import "Logging.h"

#import "debayer.h"

@implementation PAPDebayerer

/**
 * Debayers the given 1 component input buffer into the provided 3 component RGB output buffer.
 */
+ (void) debayer:(NSData *) input withOutput:(NSMutableData *) output
       imageSize:(CGSize) size andAlgorithm:(NSUInteger) algo vShift:(NSUInteger) vShift {
    int err;
    
    // get pointers
    const uint16_t *inPtr = input.bytes;
    DDAssert(inPtr, @"Failed to get input plane pointer");
    
    uint16_t *outPtr = output.mutableBytes;
    DDAssert(outPtr, @"Failed to get output plane pointer");
    
    err = Debayer(kBayerAlgorithmBilinear, inPtr, outPtr, size.width, size.height, vShift);
    DDAssert(err == 0, @"Failed to debayer: %d", err);
}

@end
