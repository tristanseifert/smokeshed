//
//  CJPEGDecompressor.m
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200617.
//

#import "CJPEGDecompressor.h"
#import "Logging.h"

#import "decompress.h"
#import "huffman.h"

// should probably be in a shared header
@interface CJPEGHuffmanTable ()

@property (nonatomic) jpeg_huffman_t *huff;

@end



@interface CJPEGDecompressor ()

@property (nonatomic) decompressor_t *dec;

@property (nonatomic) NSMutableArray<NSMutableData *> *planes;
@property (nonatomic) NSMutableDictionary<NSNumber *, CJPEGHuffmanTable *> *tables;

@end

@implementation CJPEGDecompressor

/**
 * Creates a new decompressor.
 */
- (instancetype) initWithCols:(NSUInteger) cols rows:(NSUInteger) rows precision:(NSUInteger) bits numPlanes:(NSInteger) planes {
    int err;

    self = [super init];
    if (self) {
        self.planes = [NSMutableArray new];
        self.tables = [NSMutableDictionary new];

        // create decompressor
        self.dec = JPEGDecompressorNew(cols, rows, bits, planes);
        DDAssert(self.dec != nil, @"JPEGDecompressorNew() failed");

        // allocate bit planes
        NSUInteger planeBytes = cols * rows * 2;

        for (NSUInteger i = 0; i < planes; i++) {
            NSMutableData *d = [NSMutableData dataWithLength:planeBytes];
            DDAssert(d, @"Couldn't allocate plane buffer");

            [self.planes addObject:d];
            err = JPEGDecompressorAddPlane(self.dec, i, d.mutableBytes);
            DDAssert(err == 0, @"Failed to add plane: %d", err);
        }
    }
    return self;
}

- (void) dealloc {
    JPEGDecompressorRelease(self.dec);
}

/**
 * Sets the input buffer for the decoder.
 */
- (void) setInput:(NSData *) input {
    _input = input;

    int err = JPEGDecompressorSetInput(self.dec, input.bytes,
                                       input.length);
    DDAssert(err == 0, @"Failed to set input: %d", err);
}

/**
 * Writes a Huffman compression table into the correct slot.
 */
- (void) writeTable:(CJPEGHuffmanTable *) table
           intoSlot:(NSUInteger) slot {
    int err;

    self.tables[@(slot)] = table;
    err = JPEGDecompressorAddTable(self.dec, slot, table.huff);
    DDAssert(err == 0, @"Failed to add table: %d", err);
}

/**
 * Sets the Huffman table slot to use for decoding the plane.
 */
- (void) setTableIndex:(NSUInteger) index forPlane:(NSUInteger) plane {
    int err;

    err = JPEGDecompressorSetTableForPlane(self.dec, plane, index);
    DDAssert(err == 0, @"Failed to set table index: %d", err);
}

/**
 * Returns the plane at the given index.
 */
- (NSMutableData *) getPlane:(NSInteger) index {
    return self.planes[index];
}

/**
 * Whether the decompressor read all bytes or not
 */
- (BOOL) isDone {
    return JPEGDecompressorIsDone(self.dec);
}

/**
 * Starts decoding, setting the flag if we encountered a marker.
 *
 *  @return Byte offset immediately after the last byte processed. This is either EoF or a marker.
 */
- (NSInteger) decompressFrom:(NSInteger) inOffset
                didFindMarker:(BOOL *) foundMarker {
    size_t offset;
    bool found = false;

    offset = JPEGDecompressorGo(self.dec, inOffset, &found);

    if(foundMarker) {
        *foundMarker = (BOOL) found;
    }

    return offset;
}

@end
