from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main

from version import bump, check, read_version


class VersionTest(TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "mobile").mkdir()
        (self.root / "backend/src/sarti_backend").mkdir(parents=True)
        (self.root / "VERSION").write_text("0.1.0\n", encoding="utf-8")
        (self.root / "BUILD_NUMBER").write_text("7\n", encoding="utf-8")
        (self.root / "mobile/pubspec.yaml").write_text(
            "name: sarti_mobile\nversion: 0.1.0+7\n", encoding="utf-8"
        )
        (self.root / "backend/src/sarti_backend/__init__.py").write_text(
            '"""Sarti backend package."""\n\n__version__ = "0.1.0"\n',
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_check_validates_every_version_surface_and_tag(self) -> None:
        self.assertEqual(check(self.root, tag="v0.1.0").flutter, "0.1.0+7")
        (self.root / "mobile/pubspec.yaml").write_text(
            "name: sarti_mobile\nversion: 0.1.1+7\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(ValueError, "pubspec"):
            check(self.root)

    def test_minor_bump_resets_patch_and_increments_build(self) -> None:
        updated = bump(self.root, "minor")
        self.assertEqual(updated.flutter, "0.2.0+8")
        self.assertEqual(read_version(self.root), updated)
        self.assertEqual(check(self.root), updated)

    def test_build_bump_preserves_public_version(self) -> None:
        updated = bump(self.root, "build")
        self.assertEqual(updated.flutter, "0.1.0+8")
        self.assertEqual(check(self.root, tag="v0.1.0"), updated)


if __name__ == "__main__":
    main()
