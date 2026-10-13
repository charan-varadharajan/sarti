"""Runner selection regressions; these tests never launch Flutter or devices."""

import argparse
from unittest import TestCase
from unittest.mock import patch

from run_tests import candidates, commands, run_command, select_device


class TestRunner(TestCase):
    def test_default_is_unit_widgets_only(self):
        args = argparse.Namespace(ios=False, android=False, scenario="all")
        self.assertEqual(
            commands(args), [["flutter", "test", "--reporter", "expanded"]]
        )

    def test_native_allowlist_excludes_backup_portability(self):
        args = argparse.Namespace(ios=True, android=False, scenario="all")
        selected = commands(args, "simulator")
        self.assertEqual(len(selected), 4)
        self.assertTrue(all("backup" not in " ".join(command) for command in selected))
        args.scenario = "child"
        self.assertEqual(len(commands(args, "simulator")), 1)

    def test_physical_and_wrong_platform_devices_are_excluded(self):
        devices = [
            {"id": "physical", "emulator": False, "targetPlatform": "ios"},
            {"id": "android", "emulator": True, "targetPlatform": "android-arm64"},
            {"id": "ios", "emulator": True, "targetPlatform": "ios"},
        ]
        self.assertEqual([d["id"] for d in candidates(devices, "ios")], ["ios"])

    @patch("run_tests.platform.system", return_value="Darwin")
    @patch("run_tests.machine", return_value=[])
    def test_explicit_missing_device_fails_without_booting(self, machine, system):
        with self.assertRaisesRegex(ValueError, "running supported"):
            select_device("ios", "missing", lambda message: None)
        self.assertEqual(machine.call_count, 1)

    @patch("run_tests.subprocess.Popen")
    def test_failure_exit_code_is_preserved(self, popen):
        process = popen.return_value.__enter__.return_value
        process.stdout = iter(["test failed\n"])
        process.wait.return_value = 7
        lines = []
        self.assertEqual(run_command(["flutter", "test"], lines.append), 7)
        self.assertIn("test failed", lines)
