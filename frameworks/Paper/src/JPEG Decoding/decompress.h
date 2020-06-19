//
//  decompress.h
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200617.
//

#ifndef PAPER_JPEG_DECOMPRESS_H
#define PAPER_JPEG_DECOMPRESS_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Forward declarations
typedef struct jpeg_huffman jpeg_huffman_t;

/**
 * Decompressor state
 */
typedef struct decompressor {
    /// Reference count; deallocated when this is decremented to 0
    size_t refCount;

    /// Samples per line
    size_t samplesPerLine;
    /// Total lines
    size_t lines;
    /// Sample precision (bits)
    unsigned int precision;
    /// Number of image components
    size_t numComponents;

    /// Current line
    size_t currentLine;
    /// Current sample
    size_t currentSample;

    /// Stride (bytes per row)
    size_t stride;

    /// Huffman decompression tables (up to 4)
    jpeg_huffman_t *tables[4];
    /// Which table is used for each plane when decoding
    uint8_t tableForComponent[4];

    /// Output bit plane
    uint16_t *outBuf;
    /// Number of bytes in the output buffer
    size_t outBufSz;

    /// Address of JPEG data input buffer
    const void *inBuf;
    /// Number of bytes in that buffer
    size_t inBufSz;

    // Pointer to currently being read byte
    uint8_t *readPtr;
    // Bit input buffer
    uint64_t bitBuf;
    // Number of valid bits in buffer
    size_t bitCount;
    // Number of bytes read to refill the bit buffer
    size_t numBitBufReads;

    // Reached EoF
    bool reachedEoF;
    // Finished decoding
    bool isDone;

    // Prediction algorithm to use
    uint8_t predictionAlgorithm;
    // Default value for predictor
    uint16_t predictorDefault;
} decompressor_t;

/**
 * Allocates a new decompressor state object with the given image size.
 */
decompressor_t *JPEGDecompressorNew(size_t cols, size_t rows, uint8_t bits, size_t components);

/**
 * Deallocates a previously allocated JPEG decompressor. Internal state (such as Huffman tables) are
 * released automatically, but bit planes are not.
 */
decompressor_t * JPEGDecompressorRelease(decompressor_t *dec);



/**
 * Sets the location and size of the input buffer the decompressor reads from.
 */
int JPEGDecompressorSetInput(decompressor_t *dec, const void *buffer, size_t length);

/**
 * Installs a Huffman table into the given slot.
 */
int JPEGDecompressorAddTable(decompressor_t *dec, size_t slot, jpeg_huffman_t *table);

/**
 * Sets the output bit plane; it will contain the resulting image with each component interleaved.
 */
int JPEGDecompressorSetOutput(decompressor_t *dec, void *plane, size_t length);

/**
 * Sets the table index to use for decoding a particular plane.
 */
int JPEGDecompressorSetTableForPlane(decompressor_t *dec, size_t plane, size_t table);


/**
 * Indicate whether the decompressor has written data for every sample.
 */
bool JPEGDecompressorIsDone(decompressor_t *dec);


/**
 * Decompresses image data from the given offset until either the end of the data is reached, or a marker
 * is discovered.
 */
size_t JPEGDecompressorGo(decompressor_t *dec, size_t offset, bool *outFoundMarker);

#endif /* PAPER_JPEG_DECOMPRESS_H */
