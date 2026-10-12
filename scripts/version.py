#!/usr/bin/env python3
"""Validate and update Sarti's repository-wide release version."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
FLUTTER_VERSION = re.compile(r"(?m)^version: ([^\s]+)$")
BACKEND_VERSION = re.compile(r'(?m)^__version__ = "([^"]+)"$')


@dataclass(frozen=True)
class ReleaseVersion:
    major: int
    minor: int
    patch: int
    build: int

    @property
    def public(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    @property
    def flutter(self) -> str:
        return f"{self.public}+{self.build}"


def read_version(root: Path) -> ReleaseVersion:
    public = (root / "VERSION").read_text(encoding="utf-8").strip()
    match = SEMVER.fullmatch(public)
    if match is None:
        raise ValueError("VERSION must contain X.Y.Z with no prefix or suffix")
    raw_build = (root / "BUILD_NUMBER").read_text(encoding="utf-8").strip()
    if not raw_build.isascii() or not raw_build.isdecimal() or int(raw_build) < 1:
        raise ValueError("BUILD_NUMBER must contain a positive decimal integer")
    return ReleaseVersion(*(int(value) for value in match.groups()), int(raw_build))


def check(root: Path, tag: str | None = None) -> ReleaseVersion:
    version = read_version(root)
    pubspec = (root / "mobile/pubspec.yaml").read_text(encoding="utf-8")
    flutter_match = FLUTTER_VERSION.search(pubspec)
    if flutter_match is None or flutter_match.group(1) != version.flutter:
        raise ValueError(f"mobile/pubspec.yaml must use version: {version.flutter}")

    backend = (root / "backend/src/sarti_backend/__init__.py").read_text(
        encoding="utf-8"
    )
    backend_match = BACKEND_VERSION.search(backend)
    if backend_match is None or backend_match.group(1) != version.public:
        raise ValueError(f"backend __version__ must be {version.public}")

    if tag is not None and tag != f"v{version.public}":
        raise ValueError(f"release tag must be v{version.public}")
    return version


def bump(root: Path, part: str) -> ReleaseVersion:
    current = read_version(root)
    if part == "major":
        updated = ReleaseVersion(current.major + 1, 0, 0, current.build + 1)
    elif part == "minor":
        updated = ReleaseVersion(current.major, current.minor + 1, 0, current.build + 1)
    elif part == "patch":
        updated = ReleaseVersion(current.major, current.minor, current.patch + 1, current.build + 1)
    else:
        updated = ReleaseVersion(current.major, current.minor, current.patch, current.build + 1)

    (root / "VERSION").write_text(f"{updated.public}\n", encoding="utf-8")
    (root / "BUILD_NUMBER").write_text(f"{updated.build}\n", encoding="utf-8")

    pubspec_path = root / "mobile/pubspec.yaml"
    pubspec = pubspec_path.read_text(encoding="utf-8")
    pubspec_path.write_text(
        FLUTTER_VERSION.sub(f"version: {updated.flutter}", pubspec, count=1),
        encoding="utf-8",
    )

    backend_path = root / "backend/src/sarti_backend/__init__.py"
    backend = backend_path.read_text(encoding="utf-8")
    backend_path.write_text(
        BACKEND_VERSION.sub(f'__version__ = "{updated.public}"', backend, count=1),
        encoding="utf-8",
    )
    return check(root)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--tag")
    bump_parser = subparsers.add_parser("bump")
    bump_parser.add_argument("part", choices=("major", "minor", "patch", "build"))
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent

    try:
        version = (
            check(root, tag=arguments.tag)
            if arguments.command == "check"
            else bump(root, arguments.part)
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(version.flutter)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
