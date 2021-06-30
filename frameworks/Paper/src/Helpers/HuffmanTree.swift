//
//  HuffmanTree.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200616.
//

import Foundation

/**
 * A binary tree that's specifically geared towards use in Huffman coding schemes.
 *
 * Codes up to 16 bits are supported, with each code having an associated value of a the generic type. The
 * maximum length of codes is configurable.
 */
internal class HuffmanTree<T>: CustomStringConvertible {
    /// Maximum code length
    private var maxCodeLength: Int = 16
    /// Root node of the code key
    private var root = TreeNode<T>()

    // MARK: - Initialization
    /**
     * Creates an empty tree with the specified maximum code length.
     */
    internal init(maxLength: Int) {
        self.maxCodeLength = maxLength
    }

    /**
     * Creates a new empty tree.
     */
    convenience internal init() {
        self.init(maxLength: 16)
    }

    // MARK: - Add/Remove Codes
    /**
     * Adds a key of the given length to the tree.
     */
    internal func add(code inCode: UInt16, bits: Int, _ value: T?) {
        var next: TreeNode<T> = self.root

        // we need to reverse the input code
        var code = inCode.bitSwapped
        code = (code >> (16 - bits))

        // go down the tree adding nodes as needed
        for i in 1...bits {
            // get the least significant bit
            let bit = ((code & 0x01) == 0x01) ? true : false
            code = (code >> 1)

            // are we going to insert a leaf here?
            if i == bits {
                let leaf = TreeNode<T>(withValue: value)
                next.addChild(child: leaf, bit)
            }
            // continue to traverse down the tree
            else {
                // there's an existing child; go down that path
                if let child = next.getChild(bit: bit) {
                    next = child
                }
                // there isn't; go ahead and create it
                else {
                    let node = TreeNode<T>()
                    next.addChild(child: node, bit)
                    next = node
                }
            }
        }
    }

    // MARK: - Decoding
    /**
     * Reads bits from the provided data until a code is recognized, or the maximum code length was
     * reached.
     */
    internal func readCode(from stream: Bitstream) throws -> TreeNode<T> {
        var bitsRead = 0
        var codeRead: UInt16 = 0

        var next: TreeNode<T>? = self.root

        // read the code bit by bit and traverse the tree
        while let node = next {
            // if we've reached a leaf, return it
            if node.isLeaf {
                return node
            }

            // read a bit and get the child node
            guard let bit = stream.readNext() else {
                throw TreeErrors.bitReadFailed
            }

            bitsRead += 1
            codeRead <<= 1

            if bit != 0 {
                codeRead |= 1
                next = node.getChild(bit: true)
            } else {
                next = node.getChild(bit: false)
            }
        }

        // if we get here, we failed to find a matching code
        throw TreeErrors.unknownCode(codeRead, bitsRead)
    }

    // MARK: - Tree nodes
    /**
     * Represents a single node of the Huffman tree.
     *
     * Nodes can either be leaves (meaningful value, no children) or branch (no value, one or two children)
     * types. Each node is a leaf until children are added to it.
     */
    internal class TreeNode<T>: CustomStringConvertible {
        /// Node value
        private(set) internal var value: T?
        /// Child nodes
        private var children: [Bool: TreeNode<T>] = [:]

        /// Is this a leaf node?
        internal var isLeaf: Bool {
            return self.children.isEmpty
        }

        /**
         * Creates a new node with the given associated value.
         */
        fileprivate init(withValue value: T?) {
            self.value = value
        }
        /**
         * Creates a new node that doesn't have an associated value.
         */
        fileprivate convenience init() {
            self.init(withValue: nil)
        }

        /**
         * Adds a child for the given bit state.
         */
        fileprivate func addChild(child: TreeNode<T>, _ bit: Bool) {
            self.children[bit] = child
        }

        /**
         * Returns the child for the given bit state, if we have one.
         */
        fileprivate func getChild(bit: Bool) -> TreeNode<T>? {
            return self.children[bit]
        }

        /// Pretty string format
        var description: String {
            if self.isLeaf {
                if let v = self.value as? CustomStringConvertible {
                    return String(format: "<leaf: %@>", String(describing: v))
                } else {
                    return "<leaf>"
                }
            } else {
                return String(format: "<branch: %@>", self.children)
            }
        }
    }

    // MARK: - Helpers
    /// Pretty string format
    var description: String {
        return String(format: "<Huffman tree: root = %@>",
                      String(describing: self.root))
    }

    // MARK: - Errors
    enum TreeErrors: Error {
        /// Couldn't read another bit from the input stream
        case bitReadFailed
        /// After reading the maximum number of bits, no codes were recognized
        case unknownCode(_ code: UInt16, _ bitsRead: Int)
    }
}
