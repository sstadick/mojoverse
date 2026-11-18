# Callback registration for the raylib safe API.
#
# raylib has several "set callback" entry points. The codegen skips them in the
# generated layers because passing a Mojo function to C needs care:
#
#   * The callback must carry Mojo's `abi("C")` effect so C can call it.
#   * An `abi("C")` function value can't be forwarded through an ordinary
#     parameter in Mojo 1.0 — the effect is dropped on a parameter's type
#     and the value doesn't conform to `AnyType` for `external_call`. The only
#     form that lowers to a real C function pointer is an *inferred compile-time*
#     parameter `materialize`d at the call site. Hence the callback is supplied
#     in `[...]`, not `(...)`:
#
#         def my_log(level: c_int, text: Pointer[c_char, ImmUntrackedOrigin]) abi("C"):
#             ...
#         set_trace_log_callback[my_log]()
#
# The callback's parameter type can't be checked (an `abi("C")` function-pointer
# type can't be carried here), so each function documents the exact C signature
# its callback must have — getting it wrong is undefined behaviour.

"""Register C-compatible callbacks with raylib's safe Mojo API.

Callbacks are inferred compile-time parameters so Mojo can materialize stable C
function pointers. Each helper documents the exact callback signature required
by raylib.
"""

from std.ffi import c_char, c_int, c_uint, external_call
import raylib.types as public_types
from raylib.types import AudioStream


def set_trace_log_callback[CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT]():
    """Set a custom trace-log handler.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Callback: `def(level: c_int, text: Pointer[c_char, ImmUntrackedOrigin]) abi("C")`.
    Routed through the native shim, which formats raylib's `va_list` message
    into a plain C string before invoking `cb`.
    """
    external_call["mojo_raylib_SetTraceLogCallback", NoneType](
        materialize[cb]()
    )


def set_load_file_data_callback[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
]():
    """Set a custom binary-file loader.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Callback: `def(fileName: Pointer[c_char, ImmUntrackedOrigin], dataSize: Pointer[c_int, MutUntrackedOrigin]) -> Pointer[c_uchar, MutUntrackedOrigin] abi("C")`.
    """
    external_call["SetLoadFileDataCallback", NoneType](materialize[cb]())


def set_save_file_data_callback[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
]():
    """Set a custom binary-file saver.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Callback: `def(fileName: Pointer[c_char, ImmUntrackedOrigin], data: Pointer[NoneType, MutUntrackedOrigin], dataSize: c_int) -> Bool abi("C")`.
    """
    external_call["SetSaveFileDataCallback", NoneType](materialize[cb]())


def set_load_file_text_callback[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
]():
    """Set a custom text-file loader.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Callback: `def(fileName: Pointer[c_char, ImmUntrackedOrigin]) -> Pointer[c_char, MutUntrackedOrigin] abi("C")`.
    """
    external_call["SetLoadFileTextCallback", NoneType](materialize[cb]())


def set_save_file_text_callback[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
]():
    """Set a custom text-file saver.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Callback: `def(fileName: Pointer[c_char, ImmUntrackedOrigin], text: Pointer[c_char, ImmUntrackedOrigin]) -> Bool abi("C")`.
    """
    external_call["SetSaveFileTextCallback", NoneType](materialize[cb]())


def attach_audio_mixed_processor[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
]():
    """Attach an audio processor to the entire audio pipeline.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Callback: `def(bufferData: Pointer[NoneType, MutUntrackedOrigin], frames: c_uint) abi("C")`,
    receiving `frames` x 2 samples as `float` (stereo).
    """
    external_call["AttachAudioMixedProcessor", NoneType](materialize[cb]())


def detach_audio_mixed_processor[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
]():
    """Detach a pipeline audio processor previously attached with the same `cb`.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.
    """
    external_call["DetachAudioMixedProcessor", NoneType](materialize[cb]())


def set_audio_stream_callback[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
](stream: AudioStream):
    """Set the audio-thread callback that requests new data for `stream`.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Args:
        stream: The audio stream that receives data from the callback.

    Callback: `def(bufferData: Pointer[NoneType, MutUntrackedOrigin], frames: c_uint) abi("C")`.
    """
    var raw_stream = public_types._to_raw_audio_stream(stream)
    external_call["mojo_raylib_SetAudioStreamCallback", NoneType](
        Pointer(to=raw_stream), materialize[cb]()
    )


def attach_audio_stream_processor[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
](stream: AudioStream):
    """Attach an audio processor to `stream` (`frames` x 2 `float` samples, stereo).

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Args:
        stream: The audio stream to process.

    Callback: `def(bufferData: Pointer[NoneType, MutUntrackedOrigin], frames: c_uint) abi("C")`.
    """
    var raw_stream = public_types._to_raw_audio_stream(stream)
    external_call["mojo_raylib_AttachAudioStreamProcessor", NoneType](
        Pointer(to=raw_stream), materialize[cb]()
    )


def detach_audio_stream_processor[
    CbT: ImplicitlyCopyable & Deinitable, //, cb: CbT
](stream: AudioStream):
    """Detach a processor previously attached to `stream` with the same `cb`.

    Parameters:
        CbT: The inferred Mojo type of `cb`.
        cb: The C-compatible callback function.

    Args:
        stream: The audio stream from which to detach the processor.
    """
    var raw_stream = public_types._to_raw_audio_stream(stream)
    external_call["mojo_raylib_DetachAudioStreamProcessor", NoneType](
        Pointer(to=raw_stream), materialize[cb]()
    )
