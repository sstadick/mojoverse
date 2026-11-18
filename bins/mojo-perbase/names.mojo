"""Worker-local QNAME interning over bytes, with reusable group heads."""

from std.ffi import external_call
from bio.buffer import Buffer, BytePtr


@fieldwise_init
struct Group(ImplicitlyCopyable):
    var name: Int
    var head: Int
    var end: Int
    var overlaps: Bool


@always_inline
def hash_name(p: BytePtr) -> UInt64:
    var h = UInt64(14695981039346656037)
    var i = 0
    while p[unsafe_offset=i]:
        h = (h ^ UInt64(p[unsafe_offset=i])) * UInt64(1099511628211)
        i += 1
    return h


struct Names(Movable):
    var names: Buffer
    var groups: List[Group]
    var table: List[Int]

    def __init__(out self):
        self.names = Buffer()
        self.groups = List[Group]()
        self.table = List[Int]()

    def clear(mut self):
        if len(self.groups):
            for i in range(len(self.table)):
                self.table[i] = -1
        self.groups.clear()
        self.names.length = 0

    def group(mut self, name: BytePtr, length: Int) raises -> Int:
        if (len(self.groups) + 1) * 2 > len(self.table):
            var size = max(len(self.table) * 2, 128)
            self.table.resize(size, -1)
            for i in range(size):
                self.table[i] = -1
            for i in range(len(self.groups)):
                var at = Int(
                    hash_name(self.names.data.unsafe_offset(self.groups[i].name)) & UInt64(size - 1)
                )
                while self.table[at] != -1:
                    at = (at + 1) & (size - 1)
                self.table[at] = i
        var at = Int(hash_name(name) & UInt64(len(self.table) - 1))
        while self.table[at] != -1:
            var id = self.table[at]
            if (
                external_call["strcmp", Int32](
                    name, self.names.data.unsafe_offset(self.groups[id].name)
                )
                == 0
            ):
                return id
            at = (at + 1) & (len(self.table) - 1)
        var id = len(self.groups)
        self.table[at] = id
        self.groups.append(Group(self.names.length, -1, -1, False))
        self.names.append(name, length + 1)
        return id
