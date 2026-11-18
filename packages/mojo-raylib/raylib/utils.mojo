"""Hand-written helpers for the raylib safe API.

Bridge a few raylib FFI patterns that aren't worth wiring through the rlparser
codegen:

* `void_ref(x)` — opaque mutable byte pointer to a Mojo value, ready for
  `set_shader_value`, `update_texture_rec`, `update_audio_stream`, etc.
* `void_ref_array(ptr)` — same, but for an existing typed pointer (e.g. a
  heap-allocated buffer).

Both preserve the concrete origin of the input while reinterpreting its pointee
as `NoneType`, which is the representation the generated bindings use for
`void *` parameters.
"""


@always_inline
def void_ref[
    T: AnyType, origin: MutOrigin, //
](ref[origin] value: T,) -> Pointer[NoneType, origin]:
    """Take an opaque mutable byte pointer to `value`.

    Parameters:
        T: The pointee type.
        origin: The mutable origin carried by `value` and the result.

    Args:
        value: The value whose address is reinterpreted.

    Returns:
        A mutable opaque pointer with the same origin as `value`.
    """
    return Pointer(to=value).unsafe_bitcast[NoneType]()


@always_inline
def void_ref_array[
    T: AnyType, //, origin: Origin[mut=True]
](ptr: Pointer[T, origin],) -> Pointer[NoneType, origin]:
    """Reinterpret a typed buffer pointer as `void *` for a raylib FFI call.

    Parameters:
        T: The source buffer's element type.
        origin: The mutable origin carried by `ptr` and the result.

    Args:
        ptr: The typed buffer pointer to reinterpret.

    Returns:
        An opaque pointer to the same storage with the same origin.
    """
    return ptr.unsafe_bitcast[NoneType]()
