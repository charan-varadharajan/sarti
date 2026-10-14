"""Run the prepared same-platform iOS suite; never include portability transfers."""

import json
import os
from pathlib import Path
import subprocess

from run_tests import ROOT, SCENARIOS


def select_device(devices):
    candidates = [
        (runtime, device)
        for runtime, group in devices.items()
        if ".iOS-" in runtime
        for device in group
        if device.get("isAvailable") and device["name"].startswith("iPhone")
    ]
    if not candidates:
        raise RuntimeError("No available iOS iPhone simulator/runtime installed")

    def version(item):
        return tuple(int(part) for part in item[0].split(".iOS-")[1].split("-"))

    return max(
        candidates, key=lambda item: (version(item), item[1].get("state") == "Booted")
    )[1]


def main():
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    device = select_device(json.loads(result.stdout)["devices"])
    if device["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], check=True)
    logs = ROOT / "test-results" / "ios-ci"
    logs.mkdir(parents=True, exist_ok=True)
    rows = ["## Native iOS scenarios", "", "| Scenario | Result |", "| --- | --- |"]
    failed = False
    for name, target in SCENARIOS.items():
        with (logs / f"{name}.log").open("w") as output:
            run = subprocess.run(
                [
                    "flutter",
                    "test",
                    target,
                    "-d",
                    device["udid"],
                    "--reporter",
                    "expanded",
                ],
                cwd=ROOT / "mobile",
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=900,
            )
        status = "PASS" if run.returncode == 0 else "FAIL"
        print(f"{name}: {status}", flush=True)
        rows.append(f"| {name} | {status} |")
        if run.returncode:
            failed = True
            subprocess.run(
                [
                    "xcrun",
                    "simctl",
                    "io",
                    device["udid"],
                    "screenshot",
                    str(logs / f"{name}-failure.png"),
                ],
                check=False,
            )
    summary = "\n".join(rows) + "\n"
    (logs / "SUMMARY.md").write_text(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as out:
            out.write(summary)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
