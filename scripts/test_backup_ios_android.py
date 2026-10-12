"""Run BACKUP-XPLAT-001 (iOS to Android) or -002 (Android to iOS).

Transfers only synthetic .srtbk ciphertext via simulator/ADB app sandboxes while
integration apps are running (flutter test removes them afterwards). Passkeys,
production relay and physical secure storage are intentionally separate tests.
"""

import argparse
import hashlib
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
TARGET = "integration_test/backup_portability_test.dart"
TRANSFER = "backup-portability-transfer.srtbk"
READY = "backup-portability-ready"
IOS_APP = "app.sarti.sartiMobile"
ANDROID_APP = "app.sarti.sarti_mobile"


def wait_until(process, probe):
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        found = probe()
        if found:
            return found
        if process.poll() is not None:
            raise RuntimeError(
                f"Device test stopped before transfer: {process.returncode}"
            )
        time.sleep(2)
    raise TimeoutError("Device build/transfer readiness timed out")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-device", required=True)
    parser.add_argument("--android-device", required=True)
    parser.add_argument("--adb", default="adb")
    parser.add_argument(
        "--direction",
        choices=("ios-to-android", "android-to-ios"),
        default="ios-to-android",
    )
    args = parser.parse_args()
    adb = [args.adb, "-s", args.android_device]
    source, destination = args.direction.split("-to-")
    scenario = "BACKUP-XPLAT-001" if source == "ios" else "BACKUP-XPLAT-002"
    devices = {"ios": args.ios_device, "android": args.android_device}

    def start(platform, phase, digest=None):
        command = [
            "flutter",
            "test",
            TARGET,
            "-d",
            devices[platform],
            f"--dart-define=BACKUP_PHASE={phase}",
            f"--dart-define=BACKUP_DIRECTION={args.direction}",
        ]
        if digest is not None:
            command.append(f"--dart-define=BACKUP_EXPECTED_SHA256={digest}")
        return subprocess.Popen(command, cwd=MOBILE)

    def ios_support():
        result = subprocess.run(
            ["xcrun", "simctl", "get_app_container", args.ios_device, IOS_APP, "data"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            return None
        markers = list(Path(result.stdout.strip()).rglob(READY))
        return markers[0].parent if len(markers) == 1 else None

    def readiness(platform, phase):
        if platform == "ios":
            support = ios_support()
            if support is not None:
                try:
                    return support if (support / READY).read_text() == phase else None
                except FileNotFoundError:
                    return None
            return None
        result = subprocess.run(
            [*adb, "exec-out", "run-as", ANDROID_APP, "cat", f"files/{READY}"],
            check=False,
            capture_output=True,
        )
        return result.returncode == 0 and result.stdout == phase.encode()

    def read_blob(platform, support):
        if platform == "ios":
            return (support / TRANSFER).read_bytes()
        return subprocess.check_output(
            [*adb, "exec-out", "run-as", ANDROID_APP, "cat", f"files/{TRANSFER}"]
        )

    def acknowledge(platform, support):
        if platform == "ios":
            (support / f"{TRANSFER}.copied").touch()
        else:
            subprocess.run(
                [
                    *adb,
                    "shell",
                    "run-as",
                    ANDROID_APP,
                    "touch",
                    f"files/{TRANSFER}.copied",
                ],
                check=True,
            )

    def cleanup():
        subprocess.run(
            [
                *adb,
                "shell",
                "run-as",
                ANDROID_APP,
                "rm",
                "-f",
                f"files/{TRANSFER}",
                f"files/{TRANSFER}.copied",
                f"files/{READY}",
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        support = ios_support()
        if support is not None:
            for name in (TRANSFER, f"{TRANSFER}.copied", READY):
                (support / name).unlink(missing_ok=True)

    process = None
    with tempfile.TemporaryDirectory(prefix="sarti-portability-") as temp:
        artifact = Path(temp) / TRANSFER
        try:
            cleanup()
            print(f"{scenario}: create encrypted file on {source}", flush=True)
            process = start(source, "export")
            support = wait_until(process, lambda: readiness(source, "export"))
            blob = read_blob(source, support)
            artifact.write_bytes(blob)
            if not blob.startswith(b"SART\x02"):
                raise RuntimeError("Export did not produce a v2 encrypted backup")
            digest = hashlib.sha256(blob).hexdigest()
            acknowledge(source, support)
            if process.wait() != 0:
                raise RuntimeError(f"{source} export failed")
            print(f"Exported {len(blob)} encrypted bytes; SHA-256 {digest}", flush=True)
            print(f"{scenario}: restore same file on {destination}", flush=True)
            process = start(destination, "restore", digest)
            support = wait_until(process, lambda: readiness(destination, "restore"))
            if destination == "ios":
                (support / TRANSFER).write_bytes(artifact.read_bytes())
            else:
                with artifact.open("rb") as incoming:
                    subprocess.run(
                        [
                            *adb,
                            "shell",
                            "run-as",
                            ANDROID_APP,
                            "sh",
                            "-c",
                            f'"cat > files/{TRANSFER}"',
                        ],
                        stdin=incoming,
                        check=True,
                    )
            if read_blob(destination, support) != blob:
                raise RuntimeError("Transferred ciphertext changed")
            acknowledge(destination, support)
            if process.wait() != 0:
                raise RuntimeError(f"{destination} restore failed")
            print(
                f"PASS: {source}-created .srtbk restored on {destination}; exact ciphertext match.",
                flush=True,
            )
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait()
            cleanup()


if __name__ == "__main__":
    main()
