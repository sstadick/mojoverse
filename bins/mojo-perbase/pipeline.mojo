"""Persistent pthread workers with byte-bounded, ordered mailboxes.

Mailbox addresses stay stable from start through join. Only immutable options,
jobs and BAM indexes cross workers. Every mutable mailbox access holds its lock.
Worker failures terminate this CLI with nonzero status; partial output is invalid.
"""

from std.ffi import external_call
from std.memory import unsafe_memcpy
from mojo_threads import Worker
from mojo_seqair.bam import Bam, Region
from mojo_seqair.buffer import Buffer, BytePtr
from options import Options
from count import Counter
from text import literal
from output import Output


def fatal(err: Error):
    var message = String("mojo-perbase: ", err, "\n")
    _ = external_call["pb_write", Int32](
        Int32(2), message.as_bytes().unsafe_ptr(), message.byte_length()
    )
    external_call["exit", NoneType](Int32(1))


struct Mailbox(Movable):
    var sync: Worker
    var data: Buffer
    var begin: Int
    var size: Int
    var done: Bool
    var id: Int
    var window: Int
    var jobs: Pointer[List[Region], ImmUntrackedOrigin]
    var bam: Pointer[Bam, ImmUntrackedOrigin]
    var options: Pointer[Options, ImmUntrackedOrigin]

    def __init__(
        out self, id: Int, window: Int, capacity: Int, jobs: List[Region], bam: Bam, o: Options
    ) raises:
        self.sync = Worker()
        self.data = Buffer(capacity)
        self.begin = 0
        self.size = 0
        self.done = False
        self.id = id
        self.window = window
        self.jobs = Pointer(to=jobs).unsafe_origin_cast[ImmUntrackedOrigin]()
        self.bam = Pointer(to=bam).unsafe_origin_cast[ImmUntrackedOrigin]()
        self.options = Pointer(to=o).unsafe_origin_cast[ImmUntrackedOrigin]()


def send(context: Int, bytes: BytePtr, n: Int) raises:
    ref m = Pointer[Mailbox, MutUntrackedOrigin](unsafe_from_address=context)[]
    m.sync.lock()
    var sent = 0
    while sent < n:
        while m.size == m.data.capacity:
            m.sync.wait()
        var end = (m.begin + m.size) % m.data.capacity
        var take = min(n - sent, min(m.data.capacity - end, m.data.capacity - m.size))
        unsafe_memcpy(
            dest=m.data.data.unsafe_offset(end), src=bytes.unsafe_offset(sent), count=take
        )
        m.size += take
        sent += take
        m.sync.notify_all()
    m.sync.unlock()


def worker(context: Int) abi("C") -> Int:
    try:
        ref m = Pointer[Mailbox, MutUntrackedOrigin](unsafe_from_address=context)[]
        var counter = Counter[send](m.options[], context)
        var job = m.id
        while job < len(m.jobs[]):
            counter.region(m.bam[], m.jobs[][job])
            m.sync.lock()
            m.done = True
            m.sync.notify_all()
            while m.done:
                m.sync.wait()
            m.sync.unlock()
            job += m.window
    except err:
        fatal(err)
    return 0


def run(o: Options, bam: Bam, jobs: List[Region]) raises:
    var workers = max(1, o.threads - 2)
    var longest = 0
    for i in range(len(bam.references)):
        longest = max(longest, len(bam.references[i].name))
    var estimate = 65536 if o.only else o.chunk * (longest + 64)
    var budget = o.channel * 1e9 * Float64(workers)
    var window = min(len(jobs), min(workers, max(1, Int(budget / Float64(estimate)))))
    var capacity = 65536
    if not o.only and window:
        capacity = max(65536, min(estimate, Int(budget / Float64(window))))
    var output = Output(o)
    var mail = List[Mailbox](capacity=window)
    for i in range(window):
        mail.append(Mailbox(i, window, capacity, jobs, bam, o))
    var header = Buffer()
    if o.only:
        if not o.bed_format:
            literal(header, "REF\tPOS\tEND\tDEPTH\n")
    else:
        literal(header, "REF\tPOS\t")
        if o.reference:
            literal(header, "REF_BASE\t")
        literal(
            header,
            "DEPTH\tA\tC\tG\tT\tN\tR\tY\tS\tW\tK\tM\tINS\tDEL\tREF_SKIP\tFAIL\tCOUNT_OF_MATE_RESOLUTIONS\tNEAR_MAX_DEPTH\n",
        )
    var receive = Buffer(65536)
    # From this point exceptions must not unwind owners while workers run.
    try:
        for i in range(window):
            var address = Int(mail.unsafe_ptr().unsafe_offset(i))
            mail[i].sync.unsafe_start[worker](address)
        var wrote_header = False
        for job in range(len(jobs)):
            ref m = mail[job % window]
            while True:
                m.sync.lock()
                while not m.size and not m.done:
                    m.sync.wait()
                if not m.size and m.done:
                    m.begin = 0
                    m.done = False
                    m.sync.notify_all()
                    m.sync.unlock()
                    break
                var n = min(m.size, receive.capacity)
                var first = min(n, m.data.capacity - m.begin)
                unsafe_memcpy(
                    dest=receive.data, src=m.data.data.unsafe_offset(m.begin), count=first
                )
                unsafe_memcpy(
                    dest=receive.data.unsafe_offset(first), src=m.data.data, count=n - first
                )
                m.begin = (m.begin + n) % m.data.capacity
                m.size -= n
                m.sync.notify_all()
                m.sync.unlock()
                if not wrote_header:
                    output.write(header)
                    wrote_header = True
                receive.length = n
                output.write(receive)
        for i in range(window):
            mail[i].sync.join()
    except err:
        fatal(err)
        # fatal exits. This explicit use prevents ASAP destruction of live
        # mailboxes before entering the handler on an output exception.
        _ = mail^
    # Explicit whole-owner borrows keep all shared allocations alive through join.
    _ = len(jobs)
    _ = len(bam.references)
    _ = o.threads
    output.close()
