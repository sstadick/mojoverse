"""Indexed BAM and BGZF primitives. Link libdeflate when using I/O APIs."""

from .bam import Bam, Reader, Record, Reference, Region, decode_sequence
from .bgzf import Input
from .buffer import Buffer
