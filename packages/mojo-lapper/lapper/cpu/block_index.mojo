"""The 32-interval forward-query index used by rust-lapper and Goose Lapper.

Adapted from rust-lapper (MIT), Copyright (c) 2019 Seth M. Stadick.
Traversal adapted from Goose Lapper (MIT), Copyright (c) 2026 Seth Stadick.
"""

from std.memory import pack_bits
from std.sys import simd_width_of

comptime BLOCK_SIZE = 32
comptime _WIDTH = min(BLOCK_SIZE, simd_width_of[UInt32]())


struct BlockIndex(Movable):
    """CPU-owned end summaries; the primary start/stop arrays stay in Lapper."""

    var max_tree: List[UInt32]
    var min_ends: List[UInt32]
    var prefix_max_ends: List[UInt32]
    var leaves: Int

    def __init__(out self):
        self.max_tree = List[UInt32]()
        self.min_ends = List[UInt32]()
        self.prefix_max_ends = List[UInt32]()
        self.leaves = 0

    def build(mut self, stops: Span[UInt32, _]):
        """Summarize stops in start order, padding tree leaves with zero."""
        var blocks = (len(stops) + BLOCK_SIZE - 1) // BLOCK_SIZE
        self.leaves = 1
        while self.leaves < blocks:
            self.leaves *= 2
        self.max_tree = List[UInt32](length=2 * self.leaves, fill=0)
        self.min_ends = List[UInt32](unsafe_uninit_length=blocks)
        self.prefix_max_ends = List[UInt32](unsafe_uninit_length=blocks)
        var source = stops.unsafe_ptr()
        var tree = self.max_tree.unsafe_ptr()
        var mins = self.min_ends.unsafe_ptr()
        var prefixes = self.prefix_max_ends.unsafe_ptr()
        var prefix = UInt32(0)
        for block in range(blocks):
            var begin = block * BLOCK_SIZE
            var smallest: UInt32
            var largest: UInt32
            if begin + BLOCK_SIZE <= len(stops):
                # Only load complete blocks: pointer-backed Lappers need not
                # have any initialized padding beyond their declared length.
                var values = source.unsafe_load[width=BLOCK_SIZE, alignment=1](
                    begin
                )
                smallest = values.reduce_min()
                largest = values.reduce_max()
            else:
                # block < blocks proves begin < len(stops); the final block
                # is nonempty, and every scalar load stays within the span.
                smallest = source[unsafe_offset=begin]
                largest = smallest
                for i in range(begin + 1, len(stops)):
                    smallest = min(smallest, source[unsafe_offset=i])
                    largest = max(largest, source[unsafe_offset=i])
            # blocks <= leaves, and each metadata slot is initialized once.
            tree[unsafe_offset=self.leaves + block] = largest
            mins.unsafe_offset(block).unsafe_write(smallest)
            prefix = max(prefix, largest)
            prefixes.unsafe_offset(block).unsafe_write(prefix)
        for node in range(self.leaves - 1, 0, -1):
            # 1 <= node < leaves puts both children within the initialized tree.
            tree[unsafe_offset=node] = max(
                tree[unsafe_offset=2 * node], tree[unsafe_offset=2 * node + 1]
            )

    @no_inline
    def next_above(self, block: Int, start: UInt32) -> Int:
        """Find the next block with an end > start, or a past-end leaf.

        Requires a built index and 0 <= block < len(min_ends).
        Climb to a live subtree on the right, then descend to its first live
        leaf. This skips dead runs even when their maximum ends increase.
        """
        var tree = self.max_tree.unsafe_ptr()
        var node = self.leaves + block
        while True:
            # 1 <= node < 2 * leaves. An even node's right sibling is
            # still in the tree, whose final index is odd (2 * leaves - 1).
            if node & 1 == 0 and tree[unsafe_offset=node + 1] > start:
                node += 1
                break
            node >>= 1
            if node <= 1:
                return self.leaves
        while node < self.leaves:
            # An internal node has both children in [2, 2 * leaves).
            node *= 2
            node += Int(tree[unsafe_offset=node] <= start)
        return node - self.leaves


@always_inline
def overlap_mask(
    starts: Span[UInt32, _], stops: Span[UInt32, _], start: UInt32, stop: UInt32
) -> UInt32:
    """Return ascending-lane matches without overreads.

    Requires equal-length start/stop spans with at most 32 intervals.
    """
    var mask = UInt32(0)
    var i = 0
    while i + _WIDTH <= len(starts):
        var s = starts.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](i)
        var e = stops.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](i)
        mask |= UInt32(pack_bits(s.lt(stop) & e.gt(start))) << UInt32(i)
        i += _WIDTH
    while i < len(starts):
        # Both spans have equal length; the scalar tail never loads past i.
        if (
            starts.unsafe_ptr()[unsafe_offset=i] < stop
            and stops.unsafe_ptr()[unsafe_offset=i] > start
        ):
            mask |= UInt32(1) << UInt32(i)
        i += 1
    return mask


@always_inline
def stop_mask(stops: Span[UInt32, _], start: UInt32) -> UInt32:
    """Mask a full interior block whose starts are all below the query stop.

    Requires exactly 32 initialized stops. The caller proves the start condition
    from the next block's first start, so no start loads/comparisons are needed.
    """
    var mask = UInt32(0)
    comptime for i in range(0, BLOCK_SIZE, _WIDTH):
        var ends = stops.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](i)
        mask |= UInt32(pack_bits(ends.gt(start))) << UInt32(i)
    return mask
