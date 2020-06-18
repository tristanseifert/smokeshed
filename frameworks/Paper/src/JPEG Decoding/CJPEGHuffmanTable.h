//
//  CJPEGHuffmanTable.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200617.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Thin wrapper around jpeg_huffman_t for the Swift world
 */
@interface CJPEGHuffmanTable : NSObject

- (void) addCode:(uint16_t) code length: (NSInteger) bits andValue:(uint8_t) value;

@end

NS_ASSUME_NONNULL_END
