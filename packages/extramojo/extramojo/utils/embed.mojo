"""Embed assets at comptime on little-endian ELF64 and Mach-O 64-bit targets.

Paths are relative to the compiler working directory or absolute. Run
`mojo --clear-cache` and rebuild after editing a file or when a different
working directory gives the same relative path a new meaning.
"""
from std.builtin.globals import global_constant
from std.collections import Array
from std.collections.string.string_span import get_static_string
from std.memory import unsafe_memcpy
from std.os import abort
from std.sys import CompilationTarget, inlined_assembly


def _asm_path[path: StaticString]() -> Array[Byte, 4 * path.byte_length()]:
    # Octal escapes preserve each filename byte through LLVM's inline assembly
    # operand substitution and the assembler's quoted-string parser.
    comptime assert path.byte_length() > 0, "empty embedded file path"
    var escaped = Array[Byte, 4 * path.byte_length()](uninitialized=True)
    var bytes = path.as_bytes()
    for i in range(len(bytes)):
        var b = bytes[i]
        if b == 0:
            abort("embedded file path contains a NUL byte")
        escaped[4 * i] = 0x5C  # backslash
        escaped[4 * i + 1] = 0x30 + (b >> 6)
        escaped[4 * i + 2] = 0x30 + ((b >> 3) & 7)
        escaped[4 * i + 3] = 0x30 + (b & 7)
    return escaped^


def _section_directive() -> StaticString:
    comptime if CompilationTarget.is_macos():
        return ".pushsection __DATA,__mojo_asset,regular"
    else:
        return '.pushsection .mojo_asset,"",@0x60004d4a'


def _escaped_path[path: StaticString]() -> StaticString:
    return StaticString(
        unsafe_from_utf8=Span(global_constant[_asm_path[path]()]())
    )


def _asset_section[path: StaticString]():
    inlined_assembly[
        get_static_string[
            _section_directive(),
            '\n.incbin "',
            _escaped_path[path](),
            '"\n.popsection',
        ](),
        NoneType,
        constraints="",
    ]()


def _object_bytes[f: def() thin -> None]() -> Span[Byte, ImmStaticOrigin]:
    # Compile the carrier during elaboration to make its object bytes available
    # to the comptime caller. The compiled carrier is never executed.
    var object_data = __mlir_attr[
        `#kgen.struct.extract<#kgen.compile_assembly<current_target(), =object, "", false, :!kgen.generator<!lit.generator<() -> !kgen.none>> `,
        f,
        `>, 0> : !kgen.string`,
    ]
    return StaticString(object_data).as_bytes()


def _read_le(data: Span[Byte, ImmStaticOrigin], offset: Int, width: Int) -> Int:
    var value = 0
    for i in range(width):
        value |= Int(data[offset + i]) << (8 * i)
    return value


def _elf_asset(obj: Span[Byte, ImmStaticOrigin]) -> Span[Byte, ImmStaticOrigin]:
    # Read the section headers of the ELF64 little-endian object we just emitted.
    if (
        len(obj) < 64
        or _read_le(obj, 0, 4) != 0x464C457F
        or obj[4] != 2
        or obj[5] != 1
    ):
        abort("expected a little-endian ELF64 object")
    var table = _read_le(obj, 40, 8)
    var stride = _read_le(obj, 58, 2)
    var count = _read_le(obj, 60, 2)
    # The emitter above assigns a private ELF section type to the asset.
    for i in range(count):
        var header = table + i * stride
        if _read_le(obj, header + 4, 4) == 0x60004D4A:
            var offset = _read_le(obj, header + 24, 8)
            return obj[offset : offset + _read_le(obj, header + 32, 8)]
    abort("asset section missing")


def _macho_asset(
    obj: Span[Byte, ImmStaticOrigin]
) -> Span[Byte, ImmStaticOrigin]:
    if len(obj) < 32 or _read_le(obj, 0, 4) != 0xFEEDFACF:
        abort("expected a little-endian Mach-O 64-bit object")
    var command = 32
    comptime name: StaticString = "__mojo_asset\0"
    for _ in range(_read_le(obj, 16, 4)):
        if _read_le(obj, command, 4) == 0x19:  # LC_SEGMENT_64
            var section = command + 72
            for _ in range(_read_le(obj, command + 64, 4)):
                if (
                    obj[section : section + name.byte_length()]
                    == name.as_bytes()
                ):
                    var offset = _read_le(obj, section + 48, 4)
                    return obj[offset : offset + _read_le(obj, section + 40, 8)]
                section += 80
        command += _read_le(obj, command + 4, 4)
    abort("asset section missing")


def _asset_bytes(
    obj: Span[Byte, ImmStaticOrigin]
) -> Span[Byte, ImmStaticOrigin]:
    comptime if CompilationTarget.is_macos():
        return _macho_asset(obj)
    else:
        return _elf_asset(obj)


def _copy_payload[
    data: Span[Byte, ImmStaticOrigin]
]() -> Array[Byte, len(data)]:
    var result = Array[Byte, len(data)](uninitialized=True)
    comptime if len(data) > 0:
        unsafe_memcpy(
            dest=result.unsafe_ptr(), src=data.unsafe_ptr(), count=len(data)
        )
    return result^


def include_bytes_requires_cache_clear_on_edit[
    path: StaticString
]() -> Span[Byte, ImmStaticOrigin]:
    """Return a static read-only span of the file's exact bytes.

    Relative paths resolve from the compiler's working directory. After editing
    the file, run `mojo --clear-cache` and rebuild.

    Parameters:
        path: The file to embed.

    Returns:
        The file contents in static storage.
    """
    comptime payload = _asset_bytes(_object_bytes[_asset_section[path]]())
    return Span(global_constant[_copy_payload[payload]()]())


def _decode_utf8(bytes: Span[Byte, ImmStaticOrigin]) -> StaticString:
    try:
        return StaticString(from_utf8=bytes)
    except:
        abort("embedded file contains invalid UTF-8")


def include_string_requires_cache_clear_on_edit[
    path: StaticString
]() -> StaticString:
    """Return the embedded text and reject invalid UTF-8 at compile time.

    Relative paths resolve from the compiler's working directory. After editing
    the file, run `mojo --clear-cache` and rebuild.

    Parameters:
        path: The file to embed.

    Returns:
        The file contents in static storage.
    """
    comptime text = _decode_utf8(
        include_bytes_requires_cache_clear_on_edit[path]()
    )
    return text
