import unittest
from ci_ios_tests import select_device
from run_tests import SCENARIOS


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_newest_available_iphone(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
                {"name": "iPhone 17", "udid": "old", "isAvailable": True}
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name": "iPhone 18", "udid": "new", "isAvailable": True},
                {"name": "iPad", "udid": "pad", "isAvailable": True},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-28-0": [
                {"name": "iPhone", "udid": "missing", "isAvailable": False}
            ],
        }
        self.assertEqual(select_device(devices)["udid"], "new")

    def test_missing_runtime_fails_instead_of_skipping(self):
        with self.assertRaises(RuntimeError):
            select_device({})

    def test_portability_directions_excluded(self):
        self.assertTrue(SCENARIOS)
        self.assertFalse(
            any("portability" in x or "cross_platform" in x for x in SCENARIOS.values())
        )
