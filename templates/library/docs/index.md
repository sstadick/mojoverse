# __PACKAGE__

[API reference](__PACKAGE__/_index.md)

This example uses Hat's generated library. Replace it with an example of your
public API, keeping assertions so documentation cannot silently become stale.

```mojo {doctest="getting_started" global=true}
from std.testing import assert_equal
from __PACKAGE__.lib import pull_rabbit

def main() raises:
    assert_equal(pull_rabbit(), "🐇")
```
