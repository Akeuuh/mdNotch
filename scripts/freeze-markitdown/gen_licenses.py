"""Collects the license of every Python package frozen into the app.

MIT, BSD and Apache all require the license text and copyright notice to
travel with a binary redistribution, so the generated file ships inside the
app bundle. Run from the freeze venv, which is the authoritative list of
what PyInstaller actually embeds.

Usage:
    .venv/bin/python gen_licenses.py <output-file>
"""

import sys
from importlib.metadata import distributions
from pathlib import Path

HEADER = """\
THIRD-PARTY LICENSES
====================

mdNotch embeds a frozen build of microsoft/markitdown and its dependencies.
The packages below are redistributed inside this application; each is listed
with its license. Where a package ships its full license text, that text is
reproduced verbatim.

PyInstaller itself is not redistributed: only its bootloader, which carries
the Bootloader Exception (SPDX: GPL-2.0-or-later WITH Bootloader-exception)
explicitly permitting embedding in an application under any license.

"""

SEPARATOR = "\n" + "-" * 78 + "\n"


def license_label(metadata) -> str:
    """The package's license, preferring the SPDX expression."""
    expression = metadata.get("License-Expression")
    if expression:
        return expression.strip()

    classifiers = [
        c.split("::")[-1].strip()
        for c in (metadata.get_all("Classifier") or [])
        if c.startswith("License ::")
    ]
    if classifiers:
        return ", ".join(classifiers)

    declared = (metadata.get("License") or "").strip()
    if declared:
        # Some packages dump their whole license text into this field.
        return declared.splitlines()[0][:80]
    return "see project"


def license_texts(dist) -> list[str]:
    """Full license texts the wheel shipped, if any."""
    texts = []
    for file in dist.files or []:
        parts = [p.lower() for p in file.parts]
        # Only metadata shipped by the wheel itself — a path merely
        # containing a "licenses" directory can be vendored source code.
        if not any(p.endswith(".dist-info") for p in parts):
            continue
        if not (parts[-1].startswith(("license", "copying", "notice")) or "licenses" in parts):
            continue
        try:
            text = Path(dist.locate_file(file)).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if text.strip():
            texts.append(text.strip())
    return texts


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)

    output = Path(sys.argv[1])
    packages = []
    for dist in distributions():
        metadata = dist.metadata
        name = metadata.get("Name") or ""
        # Build-time only: never lands in the frozen bundle.
        if name.lower() in {"pyinstaller", "pyinstaller-hooks-contrib", "altgraph", "macholib"}:
            continue
        packages.append((name, metadata.get("Version") or "", license_label(metadata), license_texts(dist)))

    packages.sort(key=lambda p: p[0].lower())

    chunks = [HEADER, "Summary\n-------\n"]
    for name, version, label, _ in packages:
        chunks.append(f"  {name} {version} — {label}\n")

    for name, version, label, texts in packages:
        chunks.append(SEPARATOR)
        chunks.append(f"{name} {version}\nLicense: {label}\n")
        for text in texts:
            chunks.append("\n" + text + "\n")

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("".join(chunks), encoding="utf-8")
    print(f"wrote {output} ({len(packages)} packages)")


if __name__ == "__main__":
    main()
