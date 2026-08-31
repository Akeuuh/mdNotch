# freeze-markitdown

Freezes [microsoft/markitdown](https://github.com/microsoft/markitdown) into a
standalone arm64 binary with PyInstaller. This binary is the real
implementation behind the app's `MarkdownConverter` protocol; it is embedded
in the app bundle and invoked as a subprocess. No Python is required on the
target machine.

## Build

```bash
./build.sh            # reproducible build from requirements.lock
./build.sh --relock   # re-resolve requirements.in first (upgrades pins)
```

Requires [uv](https://docs.astral.sh/uv/) (`brew install uv`). The script
creates an isolated Python 3.12 venv in `.venv/`, installs the exact pinned
versions from `requirements.lock`, runs PyInstaller with
`markitdown-bin.spec`, then smoke-tests the result:

- `dist/markitdown-bin/markitdown-bin sample/sample.pdf` must print non-empty
  markdown on stdout;
- a missing input file must exit non-zero with a message on stderr.

## Output

`dist/markitdown-bin/` — a onedir PyInstaller bundle. onedir (not onefile) is
deliberate: every dylib stays visible on disk so the release script can
codesign each one, as notarization requires.

CLI contract:

```
./dist/markitdown-bin/markitdown-bin <file>   # markdown on stdout, exit 0
                                              # on failure: exit != 0, message on stderr
```

## Pinned versions

See `requirements.lock` (committed). Currently `markitdown==0.1.7`,
`pyinstaller==6.22.2`, Python 3.12.

Installed markitdown extras: `pdf, docx, pptx, xlsx, xls`. HTML, CSV, JSON,
XML, EPUB and ZIP are covered by markitdown core. Image and audio extras are
intentionally excluded (offline-only app; those need external binaries or an
LLM key).

## Bundle size

~179 MB (onedir, arm64). This is the accepted cost of the zero-dependency
constraint (see SPEC.md §1).

## Network

No network calls happen during conversion: the installed converters are the
pure-Python offline ones (pdfminer, mammoth, python-pptx, openpyxl, xlrd,
BeautifulSoup...). The extras that would require network (audio/YouTube
transcription, Azure Document Intelligence) are not installed.
