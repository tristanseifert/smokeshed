//
//  CJPEGHuffmanTable+Private.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

#import "CJPEGHuffmanTable.h"
#import "huffman.h"

NS_ASSUME_NONNULL_BEGIN

@interface CJPEGHuffmanTable ()

@property (nonatomic) jpeg_huffman_t *huff;

@end

NS_ASSUME_NONNULL_END
