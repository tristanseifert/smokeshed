//
//  huffman.c
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200617.
//

#include "huffman.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>

static void ReleaseChildren(jpeg_huffman_node_t *node);

// MARK: - Constants
/**
 * Table used to reverse the bits in an integer Very Fast™
 *
 * Source: https://graphics.stanford.edu/~seander/bithacks.html#ReverseByteWith64BitsDiv
 */
static const unsigned char BitReverseTable256[256] = {
#   define R2(n)     n,     n + 2*64,     n + 1*64,     n + 3*64
#   define R4(n) R2(n), R2(n + 2*16), R2(n + 1*16), R2(n + 3*16)
#   define R6(n) R4(n), R4(n + 2*4 ), R4(n + 1*4 ), R4(n + 3*4 )
    R6(0), R6(2), R6(1), R6(3)
};

// MARK: - Initialization
/**
 * Allocates a new Huffman table.
 */
jpeg_huffman_t *JPEGHuffmanNew(void) {
    // allocate it
    jpeg_huffman_t *out = malloc(sizeof(jpeg_huffman_t));
    if(!out) return NULL;

    memset((void*) out, 0, sizeof(jpeg_huffman_t));

    // done!
    return out;
}

/**
 * Releases a previously allocated Huffman table.
 */
void JPEGHuffmanRelease(jpeg_huffman_t *huff) {
    assert(huff);

    // release children
    for(int i = 0; i < 2; i++) {
        if(huff->root.children[i]) {
            ReleaseChildren(huff->root.children[i]);
        }
    }

    free(huff);
}

/**
 * Releases the memory held by all children of this node, recursively.
 */
static void ReleaseChildren(jpeg_huffman_node_t *node) {
    // release its children, if any
    for(int i = 0; i < 2; i++) {
        if(node->children[i]) {
            ReleaseChildren(node->children[i]);
        }
    }

    // finally, release the node itself
    free(node);
}

// MARK: - Tree manipulation
/**
 * Creates a new tree node.
 */
static jpeg_huffman_node_t *MakeNode() {
    jpeg_huffman_node_t *n = malloc(sizeof(jpeg_huffman_node_t));
    if(!n) return NULL;

    memset(n, 0, sizeof(jpeg_huffman_node_t));

    return n;

}

/**
 * Adds a codeword to the Huffman table.
 */
int JPEGHuffmanAdd(jpeg_huffman_t *huff, uint16_t inCode, size_t bits, uint8_t value) {
    // validate inputs
    assert(huff);
    assert(bits <= 16);

    // start at the root of the tree
    jpeg_huffman_node_t *next = &huff->root;

    // the code should be built in reverse
    uint16_t code =
        (BitReverseTable256[(inCode >> 0) & 0xff] << 8) |
        (BitReverseTable256[(inCode >> 8) & 0xff]);
    code >>= (16 - bits);

    // iterate over the code to add nodes
    for (int i = 1; i <= bits; i++) {
        // extract next bit of codeword
        uint8_t lsb = (code & 0x0001);
        code >>= 1;

        // adding a leaf node here?
        if (i == bits) {
            jpeg_huffman_node_t *new = MakeNode();
            new->value = value;
            next->children[lsb] = new;
        }
        // otherwise, continue down the tree
        else {
            // is there a child for the bit value?
            if (next->children[lsb]) {
                next = next->children[lsb];
            }
            // create one
            else {
                jpeg_huffman_node_t *new = MakeNode();
                next->children[lsb] = new;
                next = new;
            }
        }
    }

    // successfully added the child node?
    return 0;
}
