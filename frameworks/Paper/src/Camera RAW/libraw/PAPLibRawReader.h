//
//  PAPLibRawReader.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200815.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PAPLibRawErrorDomain;

/**
 * Implements a generic camera raw reader that uses libraw.
 */
@interface PAPLibRawReader : NSObject

#ifdef TARGET_OS_MAC
@property (nonatomic) NSArray<NSImage *> *thumbs;
#endif

/// Should black level subtraction be performed when decoding?
@property (nonatomic) BOOL subtractBlackLevel;
/// Whether the maximum value of the image is scaled
@property (nonatomic) BOOL adjustMax;
/// Whether colors are scaled
@property (nonatomic) BOOL scaleColors;

- (instancetype _Nullable) initFromUrl:(NSURL *) url outError:(NSError * _Nullable __autoreleasing *) error;

- (BOOL) unpackThumbsWithError:(NSError * _Nullable __autoreleasing *) error;

- (BOOL) unpackRawDataWithError:(NSError * _Nullable __autoreleasing *) error;
- (NSData * _Nullable) debayerRawData:(NSError * _Nullable __autoreleasing *) error;

@end

NS_ASSUME_NONNULL_END
