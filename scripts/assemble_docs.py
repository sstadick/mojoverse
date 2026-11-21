"""Combine nightly and stable documentation built with their own locked compilers."""

import argparse
from pathlib import Path

from mojoverse.versions import assemble_sites


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nightly", type=Path, required=True)
    parser.add_argument("--stable", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("target/docs-versions"))
    args = parser.parse_args()
    assemble_sites(args.nightly, args.stable, args.output)
    print(f"Built nightly/stable documentation: {args.output}")


if __name__ == "__main__":
    main()
