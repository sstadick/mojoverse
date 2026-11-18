"""Checked BGZF streaming and virtual-offset seeking; direct libdeflate calls.

Instances own their file, decoder and buffers and are confined to one worker.
Buffer views expire on the next read or seek, move, or destruction.
"""

from std.ffi import external_call
from std.memory import unsafe_memcpy
from libdeflate import Decompressor
from .buffer import Buffer, BytePtr, le32, le64


struct Input(Movable):
    var file: Int
    var codec: Optional[Decompressor]
    var packed: Buffer
    var data: Buffer
    var position: Int
    var address: UInt64
    var next_address: UInt64
    var compressed: Bool
    var eof: Bool

    def __init__(out self, path: String) raises:
        self.file = 0
        self.codec = None
        self.packed = Buffer(65536)
        self.data = Buffer(65536)
        self.position = 0
        self.address = 0
        self.next_address = 0
        self.compressed = False
        self.eof = False
        var mode = String("rb")
        var c_path = path.copy()
        self.file = external_call["fopen", Int](c_path.as_c_string_span(), mode.as_c_string_span())
        if not self.file:
            raise Error("cannot open input: " + path)
        var first = external_call["fgetc", Int32](self.file)
        if first != -1 and external_call["ungetc", Int32](first, self.file) == -1:
            raise Error("input pushback failed")
        self.compressed = first == 31
        if self.compressed:
            self.codec = Decompressor()

    def __deinit__(deinit self):
        if self.file:
            _ = external_call["fclose", Int32](self.file)

    def raw_read(self, dest: BytePtr, count: Int, eof_ok: Bool = False) raises -> Bool:
        var got = external_call["fread", Int](dest, Int(1), count, self.file)
        if got == count:
            return True
        if got == 0 and eof_ok and external_call["feof", Int32](self.file):
            return False
        raise Error("truncated input or read failure")

    def fill(mut self) raises -> Bool:
        if self.position < self.data.length:
            return True
        if self.eof:
            return False
        self.position = 0
        self.data.length = 0
        if not self.compressed:
            self.data.length = external_call["fread", Int](
                self.data.data, Int(1), Int(65536), self.file
            )
            if external_call["ferror", Int32](self.file):
                raise Error("input read failed")
            self.eof = self.data.length == 0
            return not self.eof
        while True:
            self.address = self.next_address
            var p = self.packed.data
            if not self.raw_read(p, 12, True):
                self.eof = True
                return False
            if le32(p) != UInt32(0x04088B1F):
                raise Error("expected BGZF, not ordinary gzip")
            var extra = Int(p[unsafe_offset=10]) | (Int(p[unsafe_offset=11]) << 8)
            if extra > 65510:
                raise Error("invalid BGZF extra length")
            _ = self.raw_read(p.unsafe_offset(12), extra)
            var block = 0
            var at = 12
            while at + 4 <= 12 + extra:
                var count = Int(p[unsafe_offset=at + 2]) | (Int(p[unsafe_offset=at + 3]) << 8)
                if count > 12 + extra - at - 4:
                    raise Error("invalid BGZF extra field")
                if p[unsafe_offset=at] == 66 and p[unsafe_offset=at + 1] == 67 and count == 2:
                    block = (Int(p[unsafe_offset=at + 4]) | (Int(p[unsafe_offset=at + 5]) << 8)) + 1
                at += 4 + count
            if block < 12 + extra + 8 or block > 65536:
                raise Error("missing or invalid BGZF BC field")
            _ = self.raw_read(p.unsafe_offset(12 + extra), block - 12 - extra)
            var result = self.codec.value().decompress_gzip(
                Span(unsafe_ptr=p.unsafe_mut_cast[False](), length=block),
                Span(unsafe_ptr=self.data.data, length=65536),
            )
            if result.consumed != block:
                raise Error("BGZF block contains trailing compressed bytes")
            self.next_address += UInt64(block)
            self.data.length = result.written
            if result.written:
                return True

    def read(mut self, dest: BytePtr, count: Int) raises -> Bool:
        var at = 0
        while at < count:
            if not self.fill():
                if at == 0:
                    return False
                raise Error("truncated input")
            var take = min(count - at, self.data.length - self.position)
            unsafe_memcpy(
                dest=dest.unsafe_offset(at),
                src=self.data.data.unsafe_offset(self.position),
                count=take,
            )
            at += take
            self.position += take
        return True

    def exact(mut self, dest: BytePtr, count: Int) raises:
        if not self.read(dest, count):
            raise Error("unexpected end of input")

    def skip(mut self, count: Int) raises:
        var remaining = count
        while remaining:
            if not self.fill():
                raise Error("unexpected end of input")
            var take = min(remaining, self.data.length - self.position)
            remaining -= take
            self.position += take

    @always_inline
    def word(mut self, maximum: UInt32 = UInt32.MAX) raises -> UInt32:
        if self.data.length - self.position >= 4:
            var value = le32(self.data.data.unsafe_offset(self.position))
            self.position += 4
            if value > maximum:
                raise Error("invalid BAM/index length")
            return value
        var scratch = UInt32(0)
        var p = Pointer(to=scratch).unsafe_bitcast[UInt8]().unsafe_origin_cast[MutUntrackedOrigin]()
        self.exact(p, 4)
        var value = le32(p)
        if value > maximum:
            raise Error("invalid BAM/index length")
        return value

    def wide(mut self) raises -> UInt64:
        var scratch = UInt64(0)
        var p = Pointer(to=scratch).unsafe_bitcast[UInt8]().unsafe_origin_cast[MutUntrackedOrigin]()
        self.exact(p, 8)
        return le64(p)

    def seek(mut self, offset: UInt64) raises:
        if not self.compressed:
            raise Error("virtual seek requires BGZF")
        var address = offset >> 16
        var position = Int(offset & 65535)
        if self.data.length and address == self.address:
            if position > self.data.length:
                raise Error("invalid virtual offset")
            self.position = position
            return
        if address > UInt64(Int.MAX) or external_call["fseeko", Int32](
            self.file, Int(address), Int32(0)
        ):
            raise Error("seek failed")
        self.eof = False
        self.position = 0
        self.data.length = 0
        self.next_address = address
        if not self.fill() and position:
            raise Error("virtual offset beyond EOF")
        if position > self.data.length:
            raise Error("invalid virtual offset")
        self.position = position

    @always_inline
    def tell(self) -> UInt64:
        if self.position == self.data.length:
            return self.next_address << 16
        return (self.address << 16) | UInt64(self.position)
