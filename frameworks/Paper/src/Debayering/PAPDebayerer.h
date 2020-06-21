//
//  PAPDebayerer.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200621.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PAPDebayerer : NSObject

+ (void) debayer:(NSData *) input withOutput:(NSMutableData *) output
       imageSize:(CGSize) size andAlgorithm:(NSUInteger) algo vShift:(NSUInteger) vShift;

@end

NS_ASSUME_NONNULL_END
