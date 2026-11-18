"""Owned byte buffers and alignment-independent BAM scalar loads."""

from std.memory import unsafe_memcpy
from std.ffi import external_call

comptime BytePtr = Pointer[UInt8, MutUntrackedOrigin]


@always_inline
def le32(p: BytePtr) -> UInt32:
    return (
        UInt32(p[unsafe_offset=0])
        | (UInt32(p[unsafe_offset=1]) << 8)
        | (UInt32(p[unsafe_offset=2]) << 16)
        | (UInt32(p[unsafe_offset=3]) << 24)
    )


@always_inline
def le64(p: BytePtr) -> UInt64:
    return UInt64(le32(p)) | (UInt64(le32(p.unsafe_offset(4))) << 32)


struct Buffer(Movable):
    """Own allocation; views expire on growth, move or destruction.

    Only bytes in [0, length) are initialized. reserve does not change length.
    append sources must not alias this allocation, which growth can relocate.
    """

    var data: BytePtr
    var length: Int
    var capacity: Int

    def __init__(out self, capacity: Int = 256):
        self.capacity = max(capacity, 1)
        var address = external_call["malloc", Int](self.capacity)
        if not address:
            external_call["abort", NoneType]()
        self.data = BytePtr(unsafe_from_address=address)
        self.length = 0

    def __deinit__(deinit self):
        external_call["free", NoneType](self.data)

    @always_inline
    def reserve(mut self, needed: Int) raises:
        if needed > self.capacity:
            self._grow(needed)

    @no_inline
    def _grow(mut self, needed: Int) raises:
        if needed < 0 or needed > Int.MAX // 2:
            raise Error("buffer capacity overflow")
        var capacity = max(needed, self.capacity * 2)
        # All three allocation operations use libc; never mix allocator owners.
        var address = external_call["realloc", Int](self.data, capacity)
        if not address:
            raise Error("cannot grow buffer")
        self.data = BytePtr(unsafe_from_address=address)
        self.capacity = capacity

    @always_inline
    def append(mut self, source: Pointer[UInt8, _], count: Int) raises:
        if count < 0 or count > Int.MAX - self.length:
            raise Error("buffer size overflow")
        self.reserve(self.length + count)
        if count:
            unsafe_memcpy(dest=self.data.unsafe_offset(self.length), src=source, count=count)
        self.length += count

    @always_inline
    def push(mut self, value: UInt8) raises:
        self.reserve(self.length + 1)
        self.data[unsafe_offset=self.length] = value
        self.length += 1
