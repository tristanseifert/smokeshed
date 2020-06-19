//
//  CJPEGDecompressor+Private.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

#import "CJPEGDecompressor.h"

#import "decompress.h"

NS_ASSUME_NONNULL_BEGIN

@interface CJPEGDecompressor ()

@property (nonatomic) decompressor_t *dec;

@property (nonatomic) NSMutableData *output;
@property (nonatomic) NSMutableDictionary<NSNumber *, CJPEGHuffmanTable *> *tables;

@end

NS_ASSUME_NONNULL_END
