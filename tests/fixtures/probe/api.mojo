"""Documentation compatibility probe API."""

def add(a: Int, b: Int) -> Int:
    """Add integers. See [probe.api.Box].

    ```mojo {doctest="add" global=true}
    from std.testing import assert_equal
    from probe.api import add

    def main() raises:
        assert_equal(add(7, -3), 4)
    ```

    Args:
        a: Left operand.
        b: Right operand.

    Returns:
        Their sum.
    """
    return a + b


def add(a: Float64, b: Float64) -> Float64:
    """Add floating-point numbers.

    ```mojo {doctest="floats" global=true}
    from std.testing import assert_equal
    from probe.api import add
    ```

    ```mojo {doctest="floats"}
    assert_equal(add(Float64(2.5), Float64(-1.25)), Float64(1.25))
    ```

    Args:
        a: Left operand.
        b: Right operand.

    Returns:
        Their sum.
    """
    return a + b


@fieldwise_init
struct Box[T: Copyable & Deinitable](Copyable, Movable):
    """A generic owning container.

    Parameters:
        T: Stored value type.
    """
    var value: Self.T
    """The stored value."""
