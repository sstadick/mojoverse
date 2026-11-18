"""Perbase command-line options. Validation precedes opening output files."""

from std.ffi import external_call
from std.sys import argv
from std.math import isfinite
from mojo_threads import available_parallelism
from mojopt.default import reflection_default
from mojopt.deserialize import MojOptDeserializable, Opt
from mojopt.error import DisplayHelp
from mojopt.parser import Parser


struct Options(Copyable, Movable):
    var input: String
    var output: String
    var reference: String
    var bed: String
    var variants: String
    var threads: Int
    var chunk: Int
    var max_depth: Int
    var max_bytes: Int
    var cache_size: Int
    var mapq: Int
    var baseq: Int
    var include: Int
    var exclude: Int
    var strategy: Int
    var level: Int
    var compression_threads: Int
    var channel: Float64
    var only: Bool
    var merge: Bool
    var mate: Bool
    var fast: Bool
    var no_merge: Bool
    var bed_format: Bool
    var keep: Bool
    var zero: Bool
    var skip_merge: Bool
    var bgzip: Bool
    var no_header: Bool

    def __init__(out self):
        self.input = ""
        self.output = ""
        self.reference = ""
        self.bed = ""
        self.variants = ""
        self.threads = available_parallelism()
        self.chunk = 1000000
        self.max_depth = 100000
        self.max_bytes = 4294967295
        self.cache_size = 10
        self.mapq = 0
        self.baseq = 0
        self.include = 0
        self.exclude = 0
        self.strategy = 1
        self.level = 2
        self.compression_threads = 4
        self.channel = 0.15
        self.only = False
        self.merge = False
        self.mate = False
        self.fast = False
        self.no_merge = False
        self.bed_format = False
        self.keep = False
        self.zero = False
        self.skip_merge = False
        self.bgzip = False
        self.no_header = False


def number(s: String, maximum: Int) raises -> Int:
    if not s:
        raise Error("empty integer option")
    var value = 0
    for b in s.as_bytes():
        if b < 48 or b > 57 or value > (maximum - Int(b) + 48) // 10:
            raise Error("invalid integer option: " + s)
        value = value * 10 + Int(b) - 48
    if value > maximum:
        raise Error("integer option out of range")
    return value


@fieldwise_init
struct DepthArgs(Defaultable, MojOptDeserializable):
    # Numeric values remain strings until the existing strict range validation.
    # In particular, do not let a narrowing integer conversion wrap CLI input.
    var input: Opt[String, is_arg=True, help="Indexed BAM input"]
    var output: Opt[String, short="o", defaultable=True, help="TSV output (default stdout)"]
    var reference: Opt[String, long="ref-fasta", short="r", defaultable=True]
    var bed: Opt[String, long="bed-file", short="b", defaultable=True]
    var variants: Opt[String, long="bcf-file", short="B", defaultable=True]
    var threads: Opt[
        String, short="t", defaultable=True, help="Worker budget (default available CPUs)"
    ]
    var chunk: Opt[
        String,
        long="chunksize",
        short="c",
        defaultable=True,
        help="Bases per chunk (default 1000000)",
    ]
    var max_depth: Opt[
        String,
        long="max-depth",
        short="D",
        defaultable=True,
        help="base-depth only; default 100000",
    ]
    var max_bytes: Opt[String, long="max-region-bytes", defaultable=True, help="base-depth only"]
    var cache_size: Opt[
        String, long="ref-cache-size", defaultable=True, help="base-depth only; default 10"
    ]
    var mapq: Opt[String, long="min-mapq", short="q", defaultable=True]
    var baseq: Opt[
        String, long="min-base-quality-score", short="Q", defaultable=True, help="base-depth only"
    ]
    var include: Opt[String, long="include-flags", short="f", defaultable=True]
    var exclude: Opt[String, long="exclude-flags", short="F", defaultable=True]
    var strategy: Opt[
        String,
        long="mate-resolution-strategy",
        defaultable=True,
        help="base-depth only; default original",
    ]
    var level: Opt[
        String, long="compression-level", short="L", defaultable=True, help="0..9; default 2"
    ]
    var compression_threads: Opt[
        String, long="compression-threads", short="T", defaultable=True, help="Default 4"
    ]
    var channel: Opt[
        String,
        long="channel-size-modifier",
        short="C",
        defaultable=True,
        help="Default 0.15 (base-depth), 0.001 (only-depth)",
    ]
    var mate: Opt[Bool, long="mate-fix", short="m", defaultable=True]
    var fast: Opt[Bool, long="fast-mode", short="x", defaultable=True, help="only-depth only"]
    var no_merge: Opt[Bool, long="no-merge", short="n", defaultable=True, help="only-depth only"]
    var bed_format: Opt[Bool, long="bed-format", defaultable=True, help="only-depth only"]
    var keep: Opt[Bool, long="keep-zeros", short="k", defaultable=True]
    var zero: Opt[Bool, long="zero-base", short="z", defaultable=True]
    var skip_merge: Opt[Bool, long="skip-merging-intervals", short="M", defaultable=True]
    var bgzip: Opt[Bool, short="Z", defaultable=True]

    def __init__(out self):
        self = reflection_default[Self]()

    @staticmethod
    def description() -> String:
        return "Count indexed BAM alignments. Options marked for the other command are rejected."


@fieldwise_init
struct MergeArgs(Defaultable, MojOptDeserializable):
    var input: Opt[String, is_arg=True, defaultable=True, help="TSV input (default stdin)"]
    var output: Opt[String, short="o", defaultable=True]
    var bgzip: Opt[Bool, short="Z", defaultable=True]
    var level: Opt[String, long="compression-level", short="L", defaultable=True]
    var compression_threads: Opt[String, long="compression-threads", short="T", defaultable=True]
    var no_header: Opt[Bool, long="no-header", short="n", defaultable=True]

    def __init__(out self):
        self = reflection_default[Self]()


def parse[T: MojOptDeserializable](var args: List[String]) raises -> T:
    try:
        return Parser.parse[T](args^)
    except err:
        if err.isa[DisplayHelp]():
            print(err[DisplayHelp].help)
            external_call["exit", NoneType](Int32(0))
        raise Error(String(err[Error]))


def options() raises -> Options:
    var args = argv()
    var o = Options()
    if len(args) < 2 or args[1] == "--help" or args[1] == "-h":
        print("mojo-perbase <base-depth|only-depth|merge-adjacent> INPUT [OPTIONS]")
        print("Use COMMAND --help for its options. CRAM is not supported.")
        external_call["exit", NoneType](Int32(0))
    o.only = args[1] == "only-depth"
    o.merge = args[1] == "merge-adjacent"
    if not o.only and not o.merge and args[1] != "base-depth":
        raise Error("unknown command")
    if o.only:
        o.channel = 0.001
    var tail = [String(args[i]) for i in range(2, len(args))]
    if o.merge:
        var a = parse[MergeArgs](tail^)
        o.input = a.input.value
        o.output = a.output.value
        o.bgzip = a.bgzip.value
        o.no_header = a.no_header.value
        if a.level.provided:
            o.level = number(a.level.value, 9)
        if a.compression_threads.provided:
            o.compression_threads = number(a.compression_threads.value, 2147483647)
    else:
        var a = parse[DepthArgs](tail^)
        if o.only and (
            a.max_depth.provided
            or a.baseq.provided
            or a.strategy.provided
            or a.max_bytes.provided
            or a.cache_size.provided
        ):
            raise Error("base-depth-only option used with only-depth")
        if not o.only and (a.fast.provided or a.no_merge.provided or a.bed_format.provided):
            raise Error("only-depth option used with base-depth")
        o.input = a.input.value
        o.output = a.output.value
        o.reference = a.reference.value
        o.bed = a.bed.value
        o.variants = a.variants.value
        o.mate = a.mate.value
        o.fast = a.fast.value
        o.no_merge = a.no_merge.value
        o.bed_format = a.bed_format.value
        o.keep = a.keep.value
        o.zero = a.zero.value
        o.skip_merge = a.skip_merge.value
        o.bgzip = a.bgzip.value
        if a.threads.provided:
            o.threads = number(a.threads.value, 2147483647)
        if a.chunk.provided:
            o.chunk = number(a.chunk.value, 4294967295)
        if a.max_depth.provided:
            o.max_depth = number(a.max_depth.value, 4294967295)
        if a.max_bytes.provided:
            o.max_bytes = number(a.max_bytes.value, 4294967295)
        if a.cache_size.provided:
            o.cache_size = number(a.cache_size.value, 2147483647)
        if a.mapq.provided:
            o.mapq = number(a.mapq.value, 255)
        if a.baseq.provided:
            o.baseq = number(a.baseq.value, 255)
        if a.include.provided:
            o.include = number(a.include.value, 65535)
        if a.exclude.provided:
            o.exclude = number(a.exclude.value, 65535)
        if a.level.provided:
            o.level = number(a.level.value, 9)
        if a.compression_threads.provided:
            o.compression_threads = number(a.compression_threads.value, 2147483647)
        if a.channel.provided:
            o.channel = Float64(a.channel.value)
        if a.strategy.provided:
            var strategies = [
                "original",
                "basequalmapqualfirstinpair",
                "basequalmapqualiupac",
                "basequalmapqualn",
                "mapqualbasequalfirstinpair",
                "mapqualbasequaliupac",
                "mapqualbasequaln",
                "iupac",
                "n",
            ]
            o.strategy = 0
            for j in range(len(strategies)):
                if a.strategy.value.lower() == strategies[j]:
                    o.strategy = j + 1
            if not o.strategy:
                raise Error("unknown mate resolution strategy")
    if not o.input and not o.merge:
        raise Error("missing input")
    if o.fast and o.mate:
        raise Error("fast-mode conflicts with mate-fix")
    if (
        not o.threads
        or not o.chunk
        or not o.max_bytes
        or not o.compression_threads
        or not (o.channel > 0)
        or not isfinite(o.channel)
    ):
        raise Error("size and worker options must be positive")
    o.threads = min(o.threads, available_parallelism())
    return o^
