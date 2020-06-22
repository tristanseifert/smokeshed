//
//  PAPColorSpaceConverter.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200621.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString const *PAPColorSpaceConverterErrorDomain;

@interface PAPColorSpaceConverter : NSObject

+ (instancetype) shared;

- (void) convert:(NSMutableData *) pixels withModel:(NSString *) modelName
            size:(CGSize) size andError:(NSError **) error;

@end

NS_ASSUME_NONNULL_END
