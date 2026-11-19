"""Check the whole-program BED benchmark against an independent coverage oracle."""

from collections import defaultdict
from pathlib import Path
import random
import subprocess
import sys
import tempfile


def encode(records):
    return b"".join(name + f"\t{start}\t{stop}\n".encode() for name, start, stop in records)


def expected(database, queries):
    groups = defaultdict(list)
    for name, start, stop in database:
        if start <= stop:
            groups[name].append((start, stop))
    rows = []
    for name, start, stop in queries:
        hits = [(max(a, start), min(b, stop)) for a, b in groups[name]
                if a < stop and b > start]
        # The Biofast harness starts coverage at zero, even for signed inputs.
        covered = {position for a, b in hits for position in range(max(a, 0), b)}
        rows.append(name + f"\t{start}\t{stop}\t{len(hits)}\t{len(covered)}\n".encode())
    return b"".join(rows)


def main():
    binary = Path(sys.argv[1]).resolve()
    rng = random.Random(1847)
    names = [b"chr1", b"chr10", b"", b"chr\xff", b"chr\0a", b"x" * 65570]
    database = [(rng.choice(names[:5]), start := rng.randrange(1000),
                 start + rng.randrange(75)) for _ in range(500)]
    database += [(name, 9, 101) for name in names] + [(b"chr1", 20, 10)]
    queries = [(rng.choice(names + [b"missing"]), start := rng.randrange(1100),
                start + rng.randrange(100)) for _ in range(150)]
    queries += [(name, 0, 200) for name in names] * 3
    queries += [(b"chr1", -2147483648, 30), (b"chr1", 2147483647, 2147483647),
                (b"chr1", -20, -1), (b"chr1", 0, 0)]
    # Decimal pair boundaries and embedded-zero pairs, in coordinates/counts.
    database += [(b"digits", 0, 101)] * 10001
    queries += [(b"digits", value, value + 1) for value in (0, 9, 10, 99, 100, 999, 1000, 10001)]
    with tempfile.TemporaryDirectory() as directory:
        db, query = (Path(directory) / name for name in ("input.bed", "query.bed"))

        def check(records, requests, db_bytes=None, query_bytes=None):
            db.write_bytes(encode(records) if db_bytes is None else db_bytes)
            query.write_bytes(encode(requests) if query_bytes is None else query_bytes)
            actual = subprocess.check_output([str(binary), str(db), str(query)])
            assert actual == expected(records, requests), "BED output differs from scan/union oracle"

        check(database, queries)
        check([], queries)
        check(database, [])
        check([(b"a", 1, 10), (b"a", 5, 20), (b"b", 0, 12)],
              [(b"a", 2, 7), (b"b", 0, 4), (b"a", -4, 2), (b"a", 1, 6)],
              b"a\t+0001\t0010\r\na\t5suffix\t20extra\nb\t\t12\nmissing-tab\na\t3",
              b"a\t  +02\t 0007\textra\r\nb\t\t+04\na\t-4\t2\na\t1suffix\t6tail")

        # Binary keys around hash/vector boundaries; force cache resizing,
        # dictionary reuse, and unequal names differing at either end or middle.
        key_names = [b""]
        alphabet = [value for value in range(256) if value not in (9, 10)]
        for length in (1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 257):
            name = bytes(rng.choices(alphabet, k=length))
            key_names.append(name)
            for offset in sorted({0, length // 2, length - 1}):
                other = next(value for value in alphabet if value != name[offset])
                key_names.append(name[:offset] + bytes([other]) + name[offset + 1:])
        records = [(name, i % 19, i % 19 + 25) for i, name in enumerate(key_names)]
        records += [(name, 4, 16) for name in key_names[::3]]
        rng.shuffle(records)
        requests = [(name, 2, 21) for name in reversed(key_names)] * 3
        requests += [(b"missing" + name, 0, 50) for name in key_names]
        check(records, requests)
    print("PASS BED CLI: byte names, buffer reuse, signed coordinates, decimal pairs and scan/union oracle")


if __name__ == "__main__":
    main()
