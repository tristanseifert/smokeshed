//
//  PAPLibRawReader.mm
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200815.
//

#import "PAPLibRawReader.h"
#import "TSRawImageDataHelpers.h"
#import "interpolation_shared.h"
#import "lmmse_interpolate.h"
#import "ahd_interpolate_mod.h"

#import "Logging.h"
#import <libraw.h>

#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <Cocoa/Cocoa.h>

NSErrorDomain const PAPLibRawErrorDomain = @"PAPLibRawErrorDomain";

@interface PAPLibRawReader ()

@property (nonatomic) LibRaw *raw;

/// Decoded thumbnail images (as CGImageRefs)
@property (nonatomic) NSMutableArray<NSValue *> *cgThumbs;
/// Output image buffer
@property (nonatomic) NSMutableData *imageBuffer;

/// Histogram used for color space conversion
@property (nonatomic) int *histogram;
/// Gamma table used in color space conversion
@property (nonatomic) uint16_t *gamma;

- (void) updateOutThumbs;

- (BOOL) foundationErrorFrom:(int) error to:(NSError  * _Nullable  __autoreleasing *) error;

@end

@implementation PAPLibRawReader

// MARK: - Initialization
/**
 * Initializes a raw reader for the given url.
 *
 * @note If the URL has an associated security scope, it must already be accessible when calling this method.
 */
- (instancetype _Nullable) initFromUrl:(NSURL *) url outError:(NSError  * _Nullable  __autoreleasing *) error {
    int err;
    
    self = [super init];
    if (self) {
        self.cgThumbs = [NSMutableArray new];
        
        // try to read file
        self.raw = new LibRaw();
        err = self.raw->open_file(url.fileSystemRepresentation);
        
        if([self foundationErrorFrom:err to:error]) {
            return nil;
        }
        
        // default config
        self.subtractBlackLevel = YES;
        self.adjustMax = YES;
        self.scaleColors = YES;
    }
    return self;
}

/**
 * Deallocates resources.
 */
- (void) dealloc {
    // release thumbnails
    for (NSValue *val in self.cgThumbs) {
        CGImageRef image;
        [val getValue:&image];
        
        if(image) {
            CGImageRelease(image);
        }
    }
    
    // color conversion
    if(self.gamma) {
        free(self.gamma);
    } if(self.histogram) {
        free(self.histogram);
    }
    
    // ensure we don't leak the libraw instance
    delete self.raw;
}

// MARK: - Thumbs
/**
 * Loads thumbnails from the raw image.
 */
- (BOOL) unpackThumbsWithError:(NSError * _Nullable __autoreleasing *) error {
    DDAssert(self.raw != nil, @"LibRaw not initialized");
    
    // unpack thumbnail data
    int err = self.raw->unpack_thumb();
    if([self foundationErrorFrom:err to:error]) {
        return NO;
    }
    
    // decode it pls
    CGImageRef ref = [self decodeThumb:&self.raw->imgdata.thumbnail];
    if(ref) {
        [self.cgThumbs addObject:[NSValue valueWithBytes:&ref objCType:@encode(CGImageRef)]];
    }
    [self updateOutThumbs];
    
    DDLogVerbose(@"Thumbs: %@", self.thumbs);
    
    // done
    return YES;
}
/**
 * Decodes a given thumbnail to an image representation.
 */
- (CGImageRef) decodeThumb:(libraw_thumbnail_t *) thumb {
    // only JPEG is supported
    if(thumb->tformat != LIBRAW_THUMBNAIL_JPEG) return nil;
    
    // create data provider and image
    CGDataProviderRef prov = CGDataProviderCreateWithData(nil, thumb->thumb, thumb->tlength, nil);
    if(!prov) return nil;
    
    CGImageRef image = CGImageCreateWithJPEGDataProvider(prov, nil, NO, kCGRenderingIntentPerceptual);
    
    // clean up
    CGDataProviderRelease(prov);
    return image;
}

/**
 * Updates the output thumbs.
 */
- (void) updateOutThumbs {
    NSMutableArray<NSImage *> *array = [NSMutableArray new];
    
    for (NSValue *val in self.cgThumbs) {
        CGImageRef imageRef;
        [val getValue:&imageRef];
        
        NSImage *image = [[NSImage alloc] initWithCGImage:imageRef size:NSZeroSize];
        [array addObject:image];
    }
    
    self.thumbs = [array copy];
}

// MARK: - Raw data
/**
 * Decodes the raw image data.
 */
- (BOOL) unpackRawDataWithError:(NSError * _Nullable __autoreleasing *) error {
    DDAssert(self.raw != nil, @"LibRaw not initialized");
    
    // unpack raw image data
    int err = self.raw->unpack();
    if([self foundationErrorFrom:err to:error]) {
        return NO;
    }
    
    // populate image info
    self.size = CGSizeMake(self.raw->imgdata.sizes.width, self.raw->imgdata.sizes.height);
    
    return YES;
}

/**
 * Debayers raw data.
 */
- (NSMutableData * _Nullable) debayerRawData:(NSError * _Nullable __autoreleasing *) error {
    DDAssert(self.raw != nil, @"LibRaw not initialized");
    
    // allocate output buffer (or bail if already done)
    if(self.imageBuffer == nil) {
        NSUInteger length = (self.raw->imgdata.sizes.width * 4 * sizeof(uint16_t)) * self.raw->imgdata.sizes.height;
        self.imageBuffer = [NSMutableData dataWithLength:length];
    } else {
        return self.imageBuffer;
    }
    
    // copy bayer data
    auto outBuf = (uint16_t(*)[4]) self.imageBuffer.mutableBytes;
    
    unsigned short cblack[4] = {0,0,0,0};
    unsigned short dmax = 0;
    
    if(self.raw->imgdata.idata.filters || self.raw->imgdata.idata.colors == 1) { // bayer, one component
        TSRawCopyBayerData(&self.raw->imgdata, cblack, &dmax, outBuf);
    } else {
        DDLogError(@"Got an unsupported RAW format: filters = 0x%08x, colours = %i",
                   self.raw->imgdata.idata.filters, self.raw->imgdata.idata.colors);
        return nil;
    }
    
    // adjust black level
    if(self.subtractBlackLevel) {
        TSRawAdjustBlackLevel(&self.raw->imgdata, outBuf);
        TSRawSubtractBlack(&self.raw->imgdata,outBuf);
    }
        
    // white balance (color scaling) and pre-interpolation
    TSRawPreInterpolationApplyWB(&self.raw->imgdata, outBuf);
    TSRawPreInterpolation(&self.raw->imgdata, outBuf);
    
    
    // interpolate colour data
    ahd_interpolate_mod(&self.raw->imgdata, outBuf);
//        lmmse_interpolate(&self.raw->imgdata, outBuf);
    
    // convert color espacen
    if(!self.histogram) {
        static const size_t kHistogramSz = sizeof(int) * 4 * 0x2000;
        self.histogram = (int *) malloc(kHistogramSz);
        memset(self.histogram, 0, kHistogramSz);
    } if(!self.gamma) {
        static const size_t kGammaSz = sizeof(uint16_t) * 0x10000;
        self.gamma = (uint16_t *) malloc(kGammaSz);
        memset(self.gamma, 0, kGammaSz);
    }
    
    TSRawConvertToRGB(&self.raw->imgdata, outBuf, outBuf, self.histogram, self.gamma);

    
    return self.imageBuffer;
}

// MARK: - Helpers
/**
 * Writes an error object to the given pointer, based on the input libraw error code.
 *
 * @return Whether the passed in code indicates an error
 */
- (BOOL) foundationErrorFrom:(int) inErr to:(NSError  * _Nullable  __autoreleasing *) error {
    if(inErr != 0) {
        // system error
        if(inErr > 0) {
            if(error) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:inErr userInfo:nil];
            }
        }
        // LibRaw error
        else {
            if(error) {
                *error = [NSError errorWithDomain:PAPLibRawErrorDomain code:inErr userInfo:nil];
            }
        }
        
        return YES;
    }
    
    return NO;
}

@end
