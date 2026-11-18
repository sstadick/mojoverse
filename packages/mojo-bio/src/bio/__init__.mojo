"""BAM/BGZF and streaming FASTA/FASTQ readers with byte-oriented records."""

from .bam import Bam, Reader, Record, Reference, Region, decode_sequence
from .bgzf import Input
from .buffer import Buffer
from .fastx import KRead, GZFile, BufferedReader, FastxReader, FastxRecord
