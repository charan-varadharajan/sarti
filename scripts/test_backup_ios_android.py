"""Run BACKUP-XPLAT-001 on two booted disposable virtual devices.

Transfers only synthetic .srtbk ciphertext via simulator/ADB app sandboxes while
integration apps are running (flutter test removes them afterwards). Passkeys,
production relay and physical secure storage are intentionally separate tests.
"""

import argparse
import hashlib
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
TARGET = "integration_test/backup_portability_test.dart"
TRANSFER = "backup-portability-transfer.srtbk"
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
    args = parser.parse_args()
    adb = [args.adb, "-s", args.android_device]
    process = None
    with tempfile.TemporaryDirectory(prefix="sarti-portability-") as temp:
        artifact = Path(temp) / TRANSFER
        try:
            print("BACKUP-XPLAT-001: create encrypted file on iOS", flush=True)
            process = subprocess.Popen(
                [
                    "flutter",
                    "test",
                    TARGET,
                    "-d",
                    args.ios_device,
                    "--dart-define=BACKUP_PHASE=export",
                ],
                cwd=MOBILE,
            )

            def find_ios():
                result = subprocess.run(
                    [
                        "xcrun",
                        "simctl",
                        "get_app_container",
                        args.ios_device,
                        IOS_APP,
                        "data",
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                if result.returncode:
                    return None
                matches = list(Path(result.stdout.strip()).rglob(TRANSFER))
                return matches[0] if len(matches) == 1 else None

            ios_transfer = wait_until(process, find_ios)
            shutil.copyfile(ios_transfer, artifact)
            blob = artifact.read_bytes()
            if not blob.startswith(b"SART\x02"):
                raise RuntimeError("Export did not produce a v2 encrypted backup")
            digest = hashlib.sha256(blob).hexdigest()
            Path(str(ios_transfer) + ".copied").touch()
            if process.wait() != 0:
                raise RuntimeError("iOS export failed")
            print(f"Exported {len(blob)} encrypted bytes; SHA-256 {digest}", flush=True)
            # A readiness marker from the running destination test prevents an
            # install/uninstall cycle from erasing a prematurely copied file.
            cleanup = [
                *adb,
                "shell",
                "run-as",
                ANDROID_APP,
                "rm",
                "-f",
                "files/backup-portability-ready",
                f"files/{TRANSFER}",
                f"files/{TRANSFER}.copied",
            ]
            subprocess.run(cleanup, check=False, capture_output=True)
            print("BACKUP-XPLAT-001: restore same file on Android", flush=True)
            process = subprocess.Popen(
                [
                    "flutter",
                    "test",
                    TARGET,
                    "-d",
                    args.android_device,
                    "--dart-define=BACKUP_PHASE=restore",
                    f"--dart-define=BACKUP_EXPECTED_SHA256={digest}",
                ],
                cwd=MOBILE,
            )

            def android_ready():
                result = subprocess.run(
                    [
                        *adb,
                        "exec-out",
                        "run-as",
                        ANDROID_APP,
                        "cat",
                        "files/backup-portability-ready",
                    ],
                    check=False,
                    capture_output=True,
                )
                return result.returncode == 0 and result.stdout == b"restore"

            wait_until(process, android_ready)
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
            received = subprocess.check_output(
                [*adb, "exec-out", "run-as", ANDROID_APP, "cat", f"files/{TRANSFER}"]
            )
            if received != blob:
                raise RuntimeError("Transferred ciphertext changed")
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
            if process.wait() != 0:
                raise RuntimeError("Android restore failed")
            print(
                "PASS: iOS-created .srtbk restored on Android; exact ciphertext match.",
                flush=True,
            )
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait()
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
                    "files/backup-portability-ready",
                ],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )


if __name__ == "__main__":
    main()
