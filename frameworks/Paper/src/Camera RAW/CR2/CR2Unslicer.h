//
//  CR2Unslicer.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CJPEGDecompressor;

@interface CR2Unslicer : NSObject

- (instancetype) initWithInput:(CJPEGDecompressor *) input andOutput:(NSMutableData *) outBuf slicingInfo:(NSArray<NSNumber *> *) slices sensorSize:(CGSize) size;

- (void) unslice;
- (NSUInteger) calculateBayerShiftWithBorders:(NSArray<NSNumber *> *) borders;
- (void) trimBorders:(NSArray<NSNumber *> *) borders;

@end

NS_ASSUME_NONNULL_END
