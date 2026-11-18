"""Portable pthread workers. Link with -lmojo_threads_native -lpthread."""

from .thread import Thread, spawn
from .worker import Worker, available_parallelism
