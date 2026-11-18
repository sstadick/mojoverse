"""Persistent BGZF compression workers; callers drain blocks in input order.

Job allocations must not move after start. Each worker owns its compressor;
the destructor stops and joins it before releasing any shared allocation.
"""

from std.memory import unsafe_memcpy
from threads import Worker
from libdeflate import alloc_compressor, free_compressor, deflate_compress, crc32
from bio.buffer import Buffer


def compress(codec: Int, data: Buffer, mut packed: Buffer) -> Bool:
    var p = packed.data
    var prefix = [UInt8(31), 139, 8, 4, 0, 0, 0, 0, 0, 255, 6, 0, 66, 67, 2, 0, 0, 0]
    unsafe_memcpy(dest=p, src=prefix.unsafe_ptr(), count=18)
    var n = deflate_compress(codec, data.data, data.length, p.unsafe_offset(18), Int(65510))
    if not n:
        return False
    var size = n + 26
    p[unsafe_offset=16] = UInt8((size - 1) & 255)
    p[unsafe_offset=17] = UInt8((size - 1) >> 8)
    var crc = crc32(UInt32(0), data.data, data.length)
    for i in range(4):
        p[unsafe_offset=18 + n + i] = UInt8((crc >> UInt32(i * 8)) & 255)
        p[unsafe_offset=22 + n + i] = UInt8((data.length >> (i * 8)) & 255)
    packed.length = size
    return True


struct CompressionJob(Movable):
    var sync: Worker
    var codec: Int
    var data: Buffer
    var packed: Buffer
    var state: Int
    var stop: Bool
    var failed: Bool
    var started: Bool

    def __init__(out self, level: Int) raises:
        self.sync = Worker()
        self.codec = alloc_compressor(level)
        self.data = Buffer(65280)
        self.packed = Buffer(65536)
        self.state = 0
        self.stop = False
        self.failed = False
        self.started = False
        if not self.codec:
            raise Error("cannot allocate compression worker")

    def __deinit__(deinit self):
        if self.codec:
            free_compressor(self.codec)


def compression_worker(context: Int) abi("C") -> Int:
    ref job = Pointer[CompressionJob, MutUntrackedOrigin](unsafe_from_address=context)[]
    job.sync.lock()
    while True:
        while job.state != 1 and not job.stop:
            job.sync.wait()
        if job.stop:
            break
        job.sync.unlock()
        var failed = not compress(job.codec, job.data, job.packed)
        job.sync.lock()
        job.failed = failed
        job.state = 2
        job.sync.notify_all()
    job.sync.unlock()
    return 0
