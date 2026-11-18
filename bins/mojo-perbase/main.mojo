from std.ffi import external_call
from bio.bam import Bam
from options import options
from regions import make_jobs
from pipeline import run, fatal
from fasta import Fasta
from merge import merge


def main():
    external_call["pb_init", NoneType]()
    try:
        var o = options()
        if o.merge:
            merge(o)
            return
        var bam = Bam(o.input)
        var reference = Fasta(o.reference, 0)
        _ = reference^
        var jobs = make_jobs(bam, o)
        run(o, bam, jobs)
    except err:
        fatal(err)
