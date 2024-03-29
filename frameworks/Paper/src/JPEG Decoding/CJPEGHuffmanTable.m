//
//  CJPEGHuffmanTable.m
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200617.
//

#import "CJPEGHuffmanTable.h"
#import "CJPEGHuffmanTable+Private.h"

#import "huffman.h"

@implementation CJPEGHuffmanTable

- (instancetype) init {
    self = [super init];
    if (self) {
        self.huff = JPEGHuffmanNew();
        NSAssert(self.huff, @"Failed to allocate Huffman table");
    }
    return self;
}

- (void) dealloc {
    JPEGHuffmanRelease(self.huff);
}

- (void) addCode:(uint16_t) code length: (NSInteger) bits
        andValue:(uint8_t) value {
    int err;
    err = JPEGHuffmanAdd(self.huff, code, bits, value);
    NSAssert(err == 0, @"Failed to add code: %d", err);
}

@end
