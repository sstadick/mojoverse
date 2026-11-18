"""libdeflate bindings. Link with the installed static archive (-ldeflate)."""

from .codec import (
    alloc_compressor,
    free_compressor,
    alloc_decompressor,
    free_decompressor,
    deflate_compress,
    gzip_decompress,
    crc32,
)
