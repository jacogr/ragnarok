#!/usr/bin/env python3
"""List, verify or explicitly restore archived historical experiment scripts.

Restoration copies source bytes only. It never imports or executes a payload.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent


def relative_path(value, prefix):
    path = PurePosixPath(value)
    if (path.is_absolute() or path.as_posix() != value or "\\" in value
            or ".." in path.parts or not path.parts or path.parts[0] != prefix):
        raise ValueError(f"Invalid {prefix} path: {value}")
    return path


def main():
    manifest = json.loads((HERE / "manifest.json").read_text())
    groups = sorted({entry["group"] for entry in manifest["files"]})
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=("list", "verify", "restore"), default="list")
    parser.add_argument("--group", choices=["all", *groups], default="all")
    parser.add_argument("--root", type=Path, help="Explicit destination Git checkout for restore")
    args = parser.parse_args()
    entries = [entry for entry in manifest["files"]
               if args.group == "all" or entry["group"] == args.group]
    if args.action == "list":
        for entry in entries:
            print(f'{entry["group"]}: {entry["target"]}')
        return

    verified = []
    for entry in entries:
        payload = HERE / relative_path(entry["payload"], "payloads")
        if payload.is_symlink() or not payload.resolve().is_relative_to(HERE):
            raise ValueError(f"Payload escapes archive: {payload}")
        data = payload.read_bytes()
        if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"Archived payload changed: {payload}")
        verified.append((entry, data))
    if args.action == "verify":
        print(f"Verified {len(verified)} source entries; no payload executed.")
        return

    if args.root is None:
        parser.error("restore requires --root pointing to the intended historical checkout")
    root = args.root.resolve()
    if not root.is_dir() or not (root / ".git").exists():
        parser.error("--root must identify an existing Git checkout")
    pending = []
    for entry, data in verified:
        relative = relative_path(entry["target"], "build")
        if relative.suffix != ".py":
            raise ValueError(f"Restore target is not Python source: {relative}")
        target = root / relative
        cursor = root
        for part in relative.parts:
            cursor = cursor / part
            if cursor.is_symlink():
                raise ValueError(f"Refusing a symlink in restore path: {cursor}")
        if not target.resolve().is_relative_to(root / "build"):
            raise ValueError(f"Restore target escapes build directory: {target}")
        if target.exists():
            if not target.is_file() or target.read_bytes() != data:
                raise FileExistsError(f"Refusing to overwrite different content: {target}")
        else:
            pending.append((target, data))
    for target, data in pending:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as output:
            output.write(data)
    print(f"Restored {len(pending)} scripts; {len(verified) - len(pending)} already identical. "
          "No script executed.")


if __name__ == "__main__":
    main()
