"""Checked plain/BGZF output using libdeflate, with explicit finalization."""

from std.ffi import external_call
from std.memory import unsafe_memcpy
from libdeflate import alloc_compressor, free_compressor
from threads import available_parallelism
from bio.buffer import Buffer
from options import Options
from compression import compress, CompressionJob, compression_worker


struct Output(Movable):
    var fd: Int
    var codec: Int
    var data: Buffer
    var packed: Buffer
    var jobs: List[CompressionJob]
    var submitted: Int
    var drained: Int

    def __init__(out self, o: Options) raises:
        self.fd = -1
        self.codec = 0
        self.data = Buffer(65280 if o.bgzip else 1)
        self.packed = Buffer(65536 if o.bgzip else 1)
        self.jobs = List[CompressionJob]()
        self.submitted = 0
        self.drained = 0
        var input = o.input.copy()
        var output = o.output.copy()
        self.fd = Int(
            external_call["pb_output", Int32](input.as_c_string_span(), output.as_c_string_span())
        )
        if self.fd < 0:
            raise Error("cannot open output (or input/output refer to the same file)")
        if o.bgzip:
            self.codec = alloc_compressor(o.level)
            if not self.codec:
                raise Error("cannot allocate BGZF compressor")
            var workers = min(o.compression_threads, available_parallelism())
            if workers > 1:
                self.jobs.reserve(workers)
                for _ in range(workers):
                    self.jobs.append(CompressionJob(o.level))
                for i in range(workers):
                    var address = Int(self.jobs.unsafe_ptr().unsafe_offset(i))
                    try:
                        self.jobs[i].sync.unsafe_start[compression_worker](address)
                    except err:
                        self.stop_workers()
                        raise err^
                    self.jobs[i].started = True

    def __deinit__(deinit self):
        self.stop_workers()
        if self.codec:
            free_compressor(self.codec)
        if self.fd >= 0:
            _ = external_call["close", Int32](Int32(self.fd))

    def stop_workers(mut self):
        # Signal the objects in their stable backing allocation, before List
        # destruction can move a job into a temporary for its destructor.
        for i in range(len(self.jobs)):
            ref job = self.jobs[i]
            if job.started:
                job.sync.lock()
                job.stop = True
                job.sync.notify_all()
                job.sync.unlock()
                job.sync.join()
                job.started = False

    def raw(self, data: Buffer) raises:
        if external_call["pb_write", Int32](Int32(self.fd), data.data, data.length):
            raise Error("output write failed")

    def drain(mut self) raises:
        ref job = self.jobs[self.drained % len(self.jobs)]
        job.sync.lock()
        while job.state != 2:
            job.sync.wait()
        job.sync.unlock()
        if job.failed:
            raise Error("BGZF compression overflow")
        self.raw(job.packed)
        self.drained += 1

    def block(mut self) raises:
        if len(self.jobs):
            if self.submitted - self.drained == len(self.jobs):
                self.drain()
            ref job = self.jobs[self.submitted % len(self.jobs)]
            job.sync.lock()
            unsafe_memcpy(dest=job.data.data, src=self.data.data, count=self.data.length)
            job.data.length = self.data.length
            job.state = 1
            job.sync.notify_all()
            job.sync.unlock()
            self.submitted += 1
        else:
            if not compress(self.codec, self.data, self.packed):
                raise Error("BGZF compression overflow")
            self.raw(self.packed)
        self.data.length = 0

    def write(mut self, data: Buffer) raises:
        if not self.codec:
            self.raw(data)
            return
        var at = 0
        while at < data.length:
            var take = min(data.length - at, self.data.capacity - self.data.length)
            self.data.append(data.data.unsafe_offset(at), take)
            at += take
            if self.data.length == self.data.capacity:
                self.block()

    def close(mut self) raises:
        if self.codec:
            if self.data.length:
                self.block()
            while self.drained < self.submitted:
                self.drain()
            var eof = [
                UInt8(31),
                139,
                8,
                4,
                0,
                0,
                0,
                0,
                0,
                255,
                6,
                0,
                66,
                67,
                2,
                0,
                27,
                0,
                3,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            ]
            self.packed.length = 0
            self.packed.append(eof.unsafe_ptr(), len(eof))
            self.raw(self.packed)
        var fd = self.fd
        self.fd = -1
        if external_call["close", Int32](Int32(fd)):
            raise Error("output close failed")
