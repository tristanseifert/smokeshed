//
//  huffman.h
//  Smokeshed
//
//  Created by Tristan Seifert on 20200617.
//

#ifndef JPEG_HUFFMAN_H
#define JPEG_HUFFMAN_H

#include <stdint.h>
#include <stdbool.h>

/**
 * Single node in a Huffman tree
 */
typedef struct jpeg_huffman_node {
    /// Node value
    uint8_t value;

    /// Children: index by bit value
    struct jpeg_huffman_node *children[2];
} jpeg_huffman_node_t;

/**
 * Huffman decoding table; this is a thin wrapper around a tree of code words.
 */
typedef struct jpeg_huffman {
    /// Reference count
    size_t refCount;
    /// Root node
    jpeg_huffman_node_t root;
    /// Symbol table: 0xFFFF means invalid
    uint16_t table[0x10000];
} jpeg_huffman_t;



/**
 * Allocates a new Huffman table.
 */
jpeg_huffman_t *JPEGHuffmanNew(void);

/**
 * Releases a previously allocated Huffman table.
 */
jpeg_huffman_t *JPEGHuffmanRelease(jpeg_huffman_t *huff);

/**
 * Increments the reference count of the table.
 */
jpeg_huffman_t *JPEGHuffmanRetain(jpeg_huffman_t *huff);

/**
 * Adds a codeword to the Huffman table.
 */
int JPEGHuffmanAdd(jpeg_huffman_t *huff, uint16_t code, size_t bits, uint8_t value);

/**
 * Gets the associated value for the Huffman code in the provided word. It's expected the most
 * significant bit of the code is matched to the MSB of the word.
 */
bool JPEGHuffmanFind(jpeg_huffman_t *huff, uint16_t code, size_t *bitsRead, uint8_t *value);

#endif /* JPEG_HUFFMAN_H */
