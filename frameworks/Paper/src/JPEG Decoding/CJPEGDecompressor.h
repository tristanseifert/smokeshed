//
//  CJPEGDecompressor.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200617.
//

#import <Foundation/Foundation.h>

#import "CJPEGHuffmanTable.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Glue between the C-based JPEG decompression code and the Swift world™
 */
@interface CJPEGDecompressor : NSObject

/// JPEG input data
@property (nonatomic) NSData *input;
/// Whether decoder is finished
@property (nonatomic, readonly) BOOL isDone;



- (instancetype) initWithCols:(NSUInteger) cols rows:(NSUInteger) rows
                    precision:(NSUInteger) bits numPlanes:(NSInteger) planes;

- (void) writeTable:(CJPEGHuffmanTable *) table intoSlot:(NSUInteger) slot;

- (void) setTableIndex:(NSUInteger) index forPlane:(NSUInteger) plane;

- (NSInteger) decompressFrom:(NSInteger) inOffset
               didFindMarker:(out BOOL *) foundMarker;

- (NSMutableData *) getPlane:(NSInteger) index;

@end

NS_ASSUME_NONNULL_END
