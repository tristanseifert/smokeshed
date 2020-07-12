//
//  CJPEGDecompressor.m
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200617.
//

#import "CJPEGDecompressor.h"
#import "CJPEGDecompressor+Private.h"
#import "CJPEGHuffmanTable+Private.h"

#import "Logging.h"

#import "decompress.h"
#import "huffman.h"

@implementation CJPEGDecompressor

/**
 * Creates a new decompressor.
 */
- (instancetype) initWithCols:(NSUInteger) cols rows:(NSUInteger) rows precision:(NSUInteger) bits numPlanes:(NSInteger) planes {
    int err;

    self = [super init];
    if (self) {
        self.tables = [NSMutableDictionary new];

        // create decompressor
        self.dec = JPEGDecompressorNew(cols, rows, bits, planes);
        DDAssert(self.dec != nil, @"JPEGDecompressorNew() failed");

        // allocate bit plane
        NSUInteger planeBytes = cols * rows * 2 * planes;
        self.output = [NSMutableData dataWithLength:planeBytes];

        err = JPEGDecompressorSetOutput(self.dec, self.output.mutableBytes, self.output.length);
        DDAssert(err == 0, @"Failed to add plane: %d", err);
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
 * Sets the predictor to use when decoding the image.
 */
- (void) setPredictor:(NSInteger) predictor {
    _predictor = predictor;

    int err = JPEGDecompressorSetPredictionAlgo(self.dec, predictor);
    DDAssert(err == 0, @"Failed to set predictor: %d", err);
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
