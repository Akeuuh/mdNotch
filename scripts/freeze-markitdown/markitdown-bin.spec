# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the frozen markitdown binary (onedir, arm64).
# onedir (not onefile): every dylib stays visible on disk so the release
# script can codesign each one, as notarization requires.

from PyInstaller.utils.hooks import collect_all, copy_metadata

datas = []
binaries = []
hiddenimports = []

# magika ships an ONNX model as package data; markitdown ships converter
# plugins discovered via metadata. collect_all pulls both in.
for pkg in ("markitdown", "magika"):
    d, b, h = collect_all(pkg)
    datas += d
    binaries += b
    hiddenimports += h

datas += copy_metadata("markitdown")

a = Analysis(
    ["entry.py"],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter"],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="markitdown-bin",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    target_arch="arm64",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="markitdown-bin",
)
