"""Interval overlap queries for CPU and GPU.

Import `Interval`, `Lapper`, and `BITSLapper` from `lapper`. Queries use half-open
intervals: touching boundaries do not overlap. GPU queries borrow device
buffers, which must remain alive until queued work completes.
"""

from .lapper import BITSLapper, Interval, IntervalVisitor, Lapper
