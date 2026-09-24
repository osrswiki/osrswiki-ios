#!/usr/bin/env python3
"""Deterministic pack/unpack helper for the surface-map release zip.

The only supported way to create or refresh map_floors.zip is
scripts/shared/publish-map-release-bundle.sh, which calls this helper.
Do not `gh release upload` the zip by hand.

Reproducible zip options:
- members in floor order: map_floor_0.mbtiles .. map_floor_3.mbtiles
- ZIP_DEFLATED, compresslevel=9
- ZipInfo.date_time = (1980, 1, 1, 0, 0, 0)  (ZIP epoch; ignores source mtimes)
- create_system = 3 (Unix)
- external_attr = 0o644 << 16
- stored names are basenames only (no directories, extra fields, or comments)
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

MEMBERS = (
    "map_floor_0.mbtiles",
    "map_floor_1.mbtiles",
    "map_floor_2.mbtiles",
    "map_floor_3.mbtiles",
)
BUNDLE_NAME = "map_floors.zip"
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
UNIX_FILE_ATTR = 0o644 << 16
CHUNK_SIZE = 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(CHUNK_SIZE)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def pack(source_dir: Path, output: Path) -> None:
    missing = [name for name in MEMBERS if not (source_dir / name).is_file()]
    if missing:
        raise SystemExit(
            "ERROR: required map assets missing for bundle: " + ", ".join(missing)
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.fleet-sync-tmp")
    with ZipFile(temporary, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name in MEMBERS:
            info = ZipInfo(filename=name, date_time=ZIP_EPOCH)
            info.compress_type = ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = UNIX_FILE_ATTR
            archive.writestr(info, (source_dir / name).read_bytes())
    temporary.replace(output)


def unpack(zip_path: Path, destination_dir: Path) -> None:
    destination_dir.mkdir(parents=True, exist_ok=True)
    with ZipFile(zip_path) as archive:
        names = archive.namelist()
        if sorted(names) != sorted(MEMBERS):
            raise SystemExit(
                "ERROR: map bundle members do not match the pinned floor set"
            )
        for name in names:
            path = Path(name)
            if (
                path.name != name
                or path.is_absolute()
                or ".." in path.parts
                or "/" in name
                or "\\" in name
            ):
                raise SystemExit(f"ERROR: refused zip member path: {name}")
        for name in MEMBERS:
            target = destination_dir / name
            temporary = destination_dir / f".{name}.fleet-sync-tmp"
            temporary.write_bytes(archive.read(name))
            temporary.chmod(0o644)
            temporary.replace(target)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    pack_parser = subparsers.add_parser("pack", help="write a deterministic map_floors.zip")
    pack_parser.add_argument("source_dir", type=Path)
    pack_parser.add_argument("output", type=Path)

    unpack_parser = subparsers.add_parser("unpack", help="extract verified zip members")
    unpack_parser.add_argument("zip_path", type=Path)
    unpack_parser.add_argument("destination_dir", type=Path)

    digest_parser = subparsers.add_parser("digest", help="print sha256 and byte size")
    digest_parser.add_argument("path", type=Path)

    args = parser.parse_args(argv)
    if args.command == "pack":
        pack(args.source_dir, args.output)
        return 0
    if args.command == "unpack":
        unpack(args.zip_path, args.destination_dir)
        return 0
    digest = sha256_file(args.path)
    size = args.path.stat().st_size
    print(f"{digest}\t{size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
