//
//  PAPColorSpaceConverter.m
//  Paper (macOS)
//
//  Wrapper for Swift to make color space conversions more sane
//
//  Created by Tristan Seifert on 20200621.
//

#import "PAPColorSpaceConverter.h"

#import "Logging.h"

#import "colorspace.h"

NSString *PAPColorSpaceConverterErrorDomain = @"PAPColorSpaceConverterErrorDomain";



@interface PAPColorSpaceConverter ()

@property (nonatomic) NSDictionary *camToXyzInfo;

- (NSError *) errorForCode:(NSInteger) code;

@end



@implementation PAPColorSpaceConverter

/**
 * Initializes the color space converter; the conversion matrices will be loaded.
 */
- (instancetype) init {
    self = [super init];
    
    if (self) {
        NSBundle *b = [NSBundle bundleForClass:self.class];
        NSURL *url = [b URLForResource:@"CamToXYZInfo" withExtension:@"plist"];
        
        self.camToXyzInfo = [NSDictionary dictionaryWithContentsOfURL:url];
    }
    
    return self;
}

/**
 * Returns the shared color space converter.
 */
+ (instancetype) shared {
    static PAPColorSpaceConverter *inst = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [PAPColorSpaceConverter new];
    });
    
    return inst;
}

/**
 * Converts pixel data to the working color space, in place. The conversion matrix is read for the given model.
 */
- (void) convert:(NSMutableData *) pixels withModel:(NSString *) modelName
            size:(CGSize) size andError:(NSError **) error {
    long err;
    double camXyz[3][3];
    
    // read conversion info and make matrix
    NSDictionary *info = self.camToXyzInfo[modelName];
    if(!info) {
        *error = [self errorForCode:-1];
        return;
    }
    
    for (NSUInteger i = 0; i < 9; i++) {
        camXyz[i / 3][i % 3] = [info[@"matrix"][i] doubleValue] / 10000.f;
    }
    
    // get data pointers
    uint16_t *ptr = pixels.mutableBytes;
    DDAssert(ptr, @"Failed to get mutable pixel pointer from %@", pixels);
    
    // run conversion
    err = ConvertToWorking(ptr, size.width, size.height, (double *) camXyz);
    
    if(err != 0) {
        *error = [self errorForCode:err];
        return;
    }
}

// MARK: - Helpers
/**
 * Creates an error with the given code.
 */
- (NSError *) errorForCode:(NSInteger) code {
    NSError *err = [NSError errorWithDomain:PAPColorSpaceConverterErrorDomain
                                       code:code
                                   userInfo:nil];
    
    return err;
    
}

@end