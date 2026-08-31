"""PyInstaller entry point for the frozen markitdown binary.

Converts the file given as argv[1] to Markdown on stdout.
Exits non-zero with a message on stderr on failure.
"""

import sys

from markitdown.__main__ import main

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - single choke point for CLI errors
        print(f"markitdown error: {exc}", file=sys.stderr)
        sys.exit(1)
