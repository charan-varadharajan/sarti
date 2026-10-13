"""Small local Flutter test entry point; no production services or backup runs."""

import argparse
import json
import platform
import shlex
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = {
    "calendar": "integration_test/calendar_add_event_scenario_test.dart",
    "child": "integration_test/child_profile_sync_test.dart",
    "grid": "integration_test/calendar_grid_scenario_test.dart",
    "guardian": "integration_test/guardian_onboarding_scenario_test.dart",
}


def machine(command):
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def candidates(devices, target):
    return sorted(
        [
            device
            for device in devices
            if device.get("emulator") is True
            and device.get("isSupported") is not False
            and (
                device.get("targetPlatform") == "ios"
                if target == "ios"
                else device.get("targetPlatform", "").startswith("android")
            )
        ],
        key=lambda device: device["id"],
    )


def select_device(target, requested, emit):
    if target == "ios" and platform.system() != "Darwin":
        raise ValueError("iOS tests require a Mac with Xcode and an iOS simulator.")
    devices = candidates(machine(["flutter", "devices", "--machine"]), target)
    if requested:
        matches = [device for device in devices if device["id"] == requested]
        if not matches:
            raise ValueError(
                "Requested device must be a running supported simulator/emulator."
            )
        return matches[0]["id"]
    if not devices:
        if target == "ios":
            inventory = machine(
                ["xcrun", "simctl", "list", "devices", "available", "--json"]
            )
            available = sorted(
                [
                    device
                    for runtime, entries in inventory["devices"].items()
                    if ".iOS-" in runtime
                    for device in entries
                    if device.get("isAvailable") and device["name"].startswith("iPhone")
                ],
                key=lambda device: (device["name"], device["udid"]),
            )
            if not available:
                raise ValueError(
                    "No iPhone simulator installed. Install an iOS runtime in Xcode."
                )
            chosen = available[0]
            emit(f"Starting {chosen['name']} ({chosen['udid']})")
            if chosen["state"] != "Booted":
                subprocess.run(["xcrun", "simctl", "boot", chosen["udid"]], check=True)
            subprocess.run(["open", "-a", "Simulator"], check=True)
        else:
            available = sorted(
                [
                    emulator
                    for emulator in machine(["flutter", "emulators", "--machine"])
                    if emulator.get("platformType") == "android"
                ],
                key=lambda emulator: emulator["id"],
            )
            if not available:
                raise ValueError(
                    "No Android emulator configured. Create one in Android Studio."
                )
            emit(f"Starting Android emulator {available[0]['id']}")
            subprocess.run(
                ["flutter", "emulators", "--launch", available[0]["id"]], check=True
            )
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            devices = candidates(machine(["flutter", "devices", "--machine"]), target)
            if devices:
                break
            time.sleep(2)
        if not devices:
            raise ValueError(
                "Device did not become available within 120 seconds. Start it manually and retry."
            )
    emit(f"Using {devices[0]['name']} ({devices[0]['id']})")
    if len(devices) > 1:
        emit("Multiple devices are running; use --device ID to select another.")
    return devices[0]["id"]


def commands(args, device=None):
    if not (args.ios or args.android):
        return [["flutter", "test", "--reporter", "expanded"]]
    names = list(SCENARIOS) if args.scenario == "all" else [args.scenario]
    return [
        ["flutter", "test", SCENARIOS[name], "-d", device, "--reporter", "expanded"]
        for name in names
    ]


def run_command(command, emit):
    emit("$ " + shlex.join(command))
    with subprocess.Popen(
        command,
        cwd=ROOT / "mobile",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    ) as process:
        try:
            for line in process.stdout:
                emit(line.rstrip("\n"))
            return process.wait()
        except KeyboardInterrupt:
            process.terminate()
            process.wait()
            raise


def main():
    parser = argparse.ArgumentParser(
        description="Run Sarti tests and save output in test-results/."
    )
    targets = parser.add_mutually_exclusive_group()
    targets.add_argument(
        "--ios", action="store_true", help="prepared UI journeys on an iOS simulator"
    )
    targets.add_argument(
        "--android",
        action="store_true",
        help="prepared UI journeys on an Android emulator",
    )
    parser.add_argument("--scenario", choices=["all", *SCENARIOS], default="all")
    parser.add_argument("--device", help="optional running simulator/emulator ID")
    args = parser.parse_args()
    if not (args.ios or args.android) and (args.device or args.scenario != "all"):
        parser.error("--device and --scenario require --ios or --android")
    target = "ios" if args.ios else "android" if args.android else "widget"
    output = ROOT / "test-results"
    output.mkdir(exist_ok=True)
    log_path = output / f"{target}-{datetime.now():%Y%m%d-%H%M%S-%f}.log"
    with log_path.open("w", encoding="utf-8") as log:

        def emit(message):
            print(message, flush=True)
            log.write(message + "\n")
            log.flush()

        emit(f"Log: {log_path}")
        try:
            device = (
                select_device(target, args.device, emit) if target != "widget" else None
            )
            for command in commands(args, device):
                code = run_command(command, emit)
                if code:
                    emit(f"FAIL (exit {code}). Log: {log_path}")
                    return code if code > 0 else 1
            emit(f"PASS. Log: {log_path}")
            return 0
        except KeyboardInterrupt:
            emit("INTERRUPTED")
            return 130
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            emit(f"ERROR: {error}")
            return 1


if __name__ == "__main__":
    sys.exit(main())
