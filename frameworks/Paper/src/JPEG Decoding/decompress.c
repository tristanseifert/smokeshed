//
//  decompress.c
//  Paper (macOS)
//
//  Provides optimized C routines for decompressing JPEG data.
//
//  Created by Tristan Seifert on 20200617.
//

#include "decompress.h"
#include "huffman.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

static uint8_t BitstreamNextByte(decompressor_t *dec, bool *foundMarker);
static void BitstreamSeek(decompressor_t *dec, size_t offset);
static uint64_t BitstreamPeek(decompressor_t *dec, size_t count, bool *foundMarker);
static int BitstreamConsume(decompressor_t *dec, size_t count);
static uint64_t BitstreamGet(decompressor_t *dec, size_t count, bool *foundMarker);

static uint16_t Predict1(decompressor_t *dec, int plane, int delta, size_t bufferOffset);

static uint8_t ReadCode(decompressor_t *dec, jpeg_huffman_t *table, bool *found, bool *foundMarker);


// MARK: - Constants
/**
 * Mask for delta values bit lengths 0-15
 */
static const uint16_t kDeltaMask[17] = {
    0x0000,
    0x0001, 0x0003, 0x0007, 0x000F,
    0x001F, 0x003F, 0x007F, 0x00FF,
    0x01FF, 0x03FF, 0x07FF, 0x0FFF,
    0x1FFF, 0x3FFF, 0x7FFF, 0xFFFF
};


// MARK: - Bitstream reading
/**
 * Reads the next byte out of the buffer.
 */
static uint8_t BitstreamNextByte(decompressor_t *dec, bool *foundMarker) {
    // are we at the end of the buffer?
    if ((((void*) dec->readPtr) - dec->inBuf) >= dec->inBufSz) {
        return 0x00;
    }

    // is the byte 0xFF?
    if (*dec->readPtr == 0xFF) {
        // is the next byte 0x00?
        if(dec->readPtr[1] == 0x00) {
            dec->readPtr += 2;
            dec->numBitBufReads += 2;
            return 0xFF;
        }
        // unknown marker
        else {
            *foundMarker = true;
            return 0;
        }
    }

    // read normally
    uint8_t temp = *dec->readPtr;
    dec->readPtr++;
    dec->numBitBufReads++;

    return temp;
}

/**
 * Seeks the bitstream to the given byte boundary in the input buffer.
 */
static void BitstreamSeek(decompressor_t *dec, size_t offset) {
    assert(offset <= dec->inBufSz);

    // set the read ptr
    dec->readPtr = ((uint8_t *) dec->inBuf) + offset;
    dec->bitBuf = 0;
    dec->bitCount = 0;
    dec->numBitBufReads = 0;
}

/**
 * Peeks at the next n bits.
 */
static uint64_t BitstreamPeek(decompressor_t *dec, size_t count, bool *foundMarker) {
    // validate state
    assert(dec);
    assert(count >= 1 && count <= 57);

    // read more bits if needed
    while(dec->bitCount < count) {
        uint8_t next = BitstreamNextByte(dec, foundMarker);
        if(*foundMarker) return 0;

        dec->bitBuf |= ((uint64_t) next) << (56 - dec->bitCount);
        dec->bitCount += 8;
    }

    // get the desired bits
    return (dec->bitBuf >> (64 - count));
}

/**
 * Consumes the given number of bits.
 */
static int BitstreamConsume(decompressor_t *dec, size_t count) {
    dec->bitBuf <<= count;
    dec->bitCount -= count;

    return 0;
}

/**
 * Gets a bit string of the given length.
 *
 * If reading should be aborted, all 1's is returned. The maximum count is 16 bits.
 */
static uint64_t BitstreamGet(decompressor_t *dec, size_t count, bool *foundMarker) {
    assert(count <= 16);

    uint64_t result = BitstreamPeek(dec, count, foundMarker);
    BitstreamConsume(dec, count);
    return result;
}

// MARK: - Setup
/**
 * Allocates a new decompressor state object with the given image size.
 */
decompressor_t *JPEGDecompressorNew(size_t cols, size_t rows, uint8_t bits, size_t components) {
    // allocate it
    decompressor_t *out = malloc(sizeof(decompressor_t));
    if(!out) return NULL;

    memset(out, 0, sizeof(decompressor_t));

    // set up initial values
    out->refCount = 1;

    out->samplesPerLine = cols;
    out->lines = rows;
    out->stride = cols * sizeof(uint16_t);

    out->precision = bits;
    out->predictorDefault = (1 << (bits - 1));

    out->numComponents = components;

    // done
    return out;
}

/**
 * Deallocates a previously allocated JPEG decompressor. Internal state (such as Huffman tables) are
 * released automatically, but bit planes are not.
 *
 * @return Pointer to decompressor, or NULL if it was deallocated
 */
decompressor_t * JPEGDecompressorRelease(decompressor_t *dec) {
    if(--dec->refCount == 0) {
        // release tables
        for (int i = 0; i < 4; i++) {
            if (dec->tables[i]) {
                JPEGHuffmanRelease(dec->tables[i]);
            }
        }

        // lastly, deallocate the decompressor
        free(dec);
        return NULL;
    }

    return dec;
}

/**
 * Sets the location and size of the input buffer the decompressor reads from.
 */
int JPEGDecompressorSetInput(decompressor_t *dec, const void *buffer, size_t length) {
    assert(dec);

    dec->inBuf = buffer;
    dec->inBufSz = length;

    // ensure the bitstream is reset
    BitstreamSeek(dec, 0);

    return 0;
}

// MARK: Tables & Planes
/**
 * Installs a Huffman table into the given slot.
 */
int JPEGDecompressorAddTable(decompressor_t *dec, size_t slot, jpeg_huffman_t *table) {
    assert(dec);
    assert(slot <= 3);

    dec->tables[slot] = table;

    return 0;
}

/**
 * Sets the address of the given output bit plane.
 */
int JPEGDecompressorAddPlane(decompressor_t *dec, size_t index, void *plane) {
    assert(dec);
    assert(index <= 3);

    dec->planes[index] = plane;

    return 0;
}

/**
 * Sets the table index to use for decoding a particular plane.
 */
int JPEGDecompressorSetTableForPlane(decompressor_t *dec, size_t plane, size_t table) {
    assert(dec);
    assert(plane <= 3);
    assert(table <= 3);

    dec->tableForComponent[plane] = table;

    return 0;

}

/**
 * Indicate whether the decompressor has written data for every sample.
 */
bool JPEGDecompressorIsDone(decompressor_t *dec) {
    assert(dec);

    return dec->isDone;
}

// MARK: - Decompression
/**
 * Decompresses image data from the given offset until either the end of the data is reached, or a marker
 * is discovered.
 */
size_t JPEGDecompressorGo(decompressor_t *dec, size_t offset, bool *outFoundMarker) {
    int delta = 0;
    bool foundMarker = false;

    uint8_t bits;
    uint64_t rawDiff;

    // check inputs
    assert(dec);
    assert(outFoundMarker);

    // seek bitstream
    BitstreamSeek(dec, offset);

    // read all lines
    for (; dec->currentLine < dec->lines; dec->currentLine++) {
        // read all samples in this line
        for(; dec->currentSample < dec->samplesPerLine; dec->currentSample++) {
            // calculate pixel offset
            size_t off = (dec->currentLine * dec->samplesPerLine) + dec->currentSample;

            // read data for each component
            for(int c = 0; c < dec->numComponents; c++) {
                bool foundCode = false;

                // read huffman encoded bit length of value
                jpeg_huffman_t *table = dec->tables[dec->tableForComponent[c]];

                bits = ReadCode(dec, table, &foundCode, &foundMarker);
                if (!foundCode) goto noCode;
                if (foundMarker) goto gotMarker;

                // read value
                if(bits) {
                    rawDiff = BitstreamGet(dec, bits, &foundMarker);
                    if (foundMarker) goto gotMarker;
                } else {
                    rawDiff = 0;
                }

                // copy positive values as is
                if ((rawDiff & (1 << (bits - 1))) != 0) {
                    delta = (rawDiff & kDeltaMask[bits]);
                }
                // for negative values, take the bitwise inverse
                else {
                    uint16_t inverse = ~rawDiff;
                    inverse &= kDeltaMask[bits];
                    delta = -((int) inverse);
                }

                // shove it into predictor
                uint16_t actual = Predict1(dec, c, delta, off);

                // write it into buffer
                dec->planes[c][off] = actual;
            }
        }

        // reset for next row
        dec->currentSample = 0;
    }

    // if we get here, decoding finished due to reading all pixels
    dec->isDone = true;
    return offset + dec->numBitBufReads;

    // failed to match a Huffman code
noCode:;
    fprintf(stderr, "Failed to find huffman code\n");
    *outFoundMarker = true;
    return offset + dec->numBitBufReads;

    // found a marker
gotMarker:;
    fprintf(stderr, "Found unhandled marker\n");

    *outFoundMarker = true;
    return offset + dec->numBitBufReads;
}

// MARK: Predictors
/**
 * Predicts the value of the current pixel in the given plane using prediction type 1 (difference from sample
 * directly to the left)
 */
static uint16_t Predict1(decompressor_t *dec, int plane, int delta, size_t bufferOffset) {
    uint16_t last = dec->predictorDefault;

    if (dec->currentSample > 0) {
        last = dec->planes[plane][bufferOffset - 1];
    }

    return (uint16_t) (((int) last) + delta);
}

// MARK: Huffman codes
/**
 * Tries to read a Huffman code from the current position in the stream.
 *
 * We peek at the contents of the read buffer bit by bit, until we've either matched a code, or read 16 total
 * bits (which indicates the code wasn't found)
 */
static uint8_t ReadCode(decompressor_t *dec, jpeg_huffman_t *table, bool *found, bool *foundMarker) {
    jpeg_huffman_node_t *next = &table->root;

    size_t bitsRead = 0;
    uint16_t code = 0;

    // iterate for as long as we've got a node
    while (next) {
        // abort if we've read 16 bits already
        if (bitsRead == 16) {
            goto failed;
        }

        // if this node is a leaf, return its value
        if (next->children[0] == NULL && next->children[1] == NULL) {
            *found = true;
            return next->value;
        }

        // read one more bit of code
        uint8_t bit = BitstreamGet(dec, 1, foundMarker);
        if (*foundMarker) goto failed;

        bitsRead += 1;
        code = (code << 1) | (bit & 0x01);

        // right node is for 1 bit
        if (bit != 0) {
            next = next->children[1];
        }
        // left node is for 0 bit
        else {
            next = next->children[0];
        }
    }

failed:;
    fprintf(stderr, "Failed to find value for code: %04x (%zu bits, x = %zu, y = %zu)\n", code, bitsRead, dec->currentSample, dec->currentLine);

    // failed to find a code
    *found = false;
    return 0;
}
