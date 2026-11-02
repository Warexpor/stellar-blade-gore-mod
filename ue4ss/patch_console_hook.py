#!/usr/bin/env python3
"""Patch only the pinned, unmodified UE4SS console mod's self-unregistering hook."""
import pathlib
import sys

target, stock = map(pathlib.Path, sys.argv[1:3])
if not target.is_file() or not stock.is_file():
    print("console startup compatibility: console mod absent; skipped")
    sys.exit(0)

original = target.read_bytes()
marker = b'-- SBGore UE4SS startup compatibility: keep the completed hook dormant.'
if marker in original:
    print("console startup compatibility: already applied")
    sys.exit(0)

normalize = lambda data: data.replace(b'\r\n', b'\n')
if normalize(original) != normalize(stock.read_bytes()):
    print("WARNING: console mod differs from pinned stock; startup compatibility patch skipped")
    sys.exit(0)

line = b'UnregisterHook("/Script/Engine.PlayerController:ClientRestart", Pre, Post)'
if original.count(line) != 1:
    raise SystemExit("console startup compatibility: expected hook not found exactly once")
backup = target.with_name(target.name + '.before-sbgore-startup-fix')
if not backup.exists():
    backup.write_bytes(original)
target.write_bytes(original.replace(line, marker, 1))
print("console startup compatibility: prevented self-unregister; original backed up")
