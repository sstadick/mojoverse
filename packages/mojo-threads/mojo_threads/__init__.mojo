"""Portable pthread workers. Link with -lmojo_threads_native -lpthread."""

from .worker import Worker, available_parallelism
