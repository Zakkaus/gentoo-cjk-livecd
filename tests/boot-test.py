#!/usr/bin/env python3
"""Boot an installation CD headless in KVM and answer the medium's checks."""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# name, command, and the pattern the answer has to match. A check that cannot
# fail is not a check: every entry judges its own output.
CHECKS = [
    ("kernel", "uname -r", r"-gentoo-cjk-dist-bin$"),
    ("zfs", "modprobe zfs && echo zfs-loaded || echo zfs-failed", r"^zfs-loaded$"),
    ("zpool", "zpool import 2>&1 | tail -1", r"pool"),
    # The serial console carries bytes, not glyphs, so rendering cannot be seen
    # from here. The font being built in and fbcon being able to take over is
    # the most this test can establish.
    ("cjk-console",
     "zcat /proc/config.gz 2>/dev/null "
     "| grep -E '^CONFIG_FONT_CJK|^CONFIG_FRAMEBUFFER_CONSOLE=' "
     "| tr '\\n' ' ' || echo no-config",
     # Order-independent, and 32x32 must be absent: the base patch ships an
     # empty font table for it.
     r"(?=.*CONFIG_FONT_CJK_16x16=y)(?=.*CONFIG_FRAMEBUFFER_CONSOLE=y)"
     r"(?!.*CONFIG_FONT_CJK_32x32=y)"),
    ("storage-tools",
     "for t in cryptsetup lvm mdadm mkfs.btrfs mkfs.xfs sgdisk; "
     "do command -v $t >/dev/null || echo missing:$t; done; echo listed",
     r"^listed$"),
]

PROMPT = re.compile(rb"[#$] $")


def volume_id(iso: Path) -> str:
    # xorriso reports on stderr, so the table of contents arrives there.
    out = subprocess.run(["xorriso", "-indev", str(iso), "-toc"],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, check=True)
    match = re.search(r"^Volume id\s*:\s*'(.+)'$", out.stdout, re.M)
    if not match:
        sys.exit(f"no volume id in {iso}")
    return match.group(1)


def extract(iso: Path, source: str, dest: Path) -> Path:
    subprocess.run(["xorriso", "-osirrox", "on", "-indev", str(iso),
                    "-extract", source, str(dest)],
                   capture_output=True, check=True)
    return dest


def extract_boot_files(iso: Path, workdir: Path) -> tuple[Path, Path]:
    """No GRUB entry sets a serial console, so boot -kernel/-initrd instead.

    grub.cfg names the kernel, which is why it is read rather than guessed.
    """
    config = extract(iso, "/boot/grub/grub.cfg", workdir / "grub.cfg").read_text()
    kernel = re.search(r"^\s*linux\s+(\S+)", config, re.M)
    initrd = re.search(r"^\s*initrd\s+(\S+)", config, re.M)
    if not kernel or not initrd:
        sys.exit(f"no linux or initrd line in the grub.cfg of {iso}")

    return (extract(iso, kernel.group(1), workdir / "kernel"),
            extract(iso, initrd.group(1), workdir / "initrd"))


class Console:
    def __init__(self, command: list[str], log: Path) -> None:
        self.proc = subprocess.Popen(command, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, bufsize=0)
        self.log = log.open("wb")
        self.buffer = bytearray()

    def close(self) -> None:
        self.proc.kill()
        self.proc.wait()
        self.log.close()

    def expect(self, pattern: re.Pattern[bytes], deadline: float) -> bytes:
        while time.monotonic() < deadline:
            byte = self.proc.stdout.read(1)
            if not byte:
                raise TimeoutError("the guest closed the serial connection")
            self.log.write(byte)
            self.buffer += byte
            match = pattern.search(self.buffer)
            if match:
                seen = bytes(self.buffer[:match.end()])
                del self.buffer[:match.end()]
                return seen
        raise TimeoutError(f"no match for {pattern.pattern!r}")

    def send(self, line: str) -> None:
        self.proc.stdin.write(line.encode() + b"\n")
        self.proc.stdin.flush()


ESCAPES = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")


def run_checks(console: Console, deadline: float) -> dict[str, str]:
    """The shell echoes what it is sent, so the markers are split in the
    command and whole only in the output."""
    results = {}
    for name, command, _ in CHECKS:
        console.send(f'echo BE""GIN-{name}; {command}; echo EN""D-{name}')
        seen = console.expect(re.compile(rf"END-{name}".encode()), deadline)
        text = ESCAPES.sub("", seen.decode("utf-8", "replace"))
        body = text.split(f"BEGIN-{name}")[-1].split(f"END-{name}")[0]
        lines = [line.strip() for line in body.splitlines() if line.strip()]
        results[name] = " | ".join(lines) if lines else "(no output)"
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", type=Path)
    parser.add_argument("--log", type=Path, default=Path("boot-test.log"))
    parser.add_argument("--memory", type=int, default=4096)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    workdir = Path(tempfile.mkdtemp(prefix="boot-test-"))
    console = None
    try:
        kernel, initrd = extract_boot_files(args.iso, workdir)
        cmdline = (f"root=live:CDLABEL={volume_id(args.iso)} rd.live.dir=/ "
                   "rd.live.squashimg=image.squashfs cdroot console=ttyS0,115200")
        # A GitHub runner has /dev/kvm but does not always grant access to it,
        # so the test is whether it opens, not whether it exists.
        accel = (["-enable-kvm", "-cpu", "host"]
                 if os.access("/dev/kvm", os.R_OK | os.W_OK) else ["-cpu", "max"])
        console = Console([
            "qemu-system-x86_64", *accel,
            "-m", str(args.memory), "-smp", "4", "-nographic", "-no-reboot",
            "-drive", f"file={args.iso},media=cdrom,readonly=on",
            "-kernel", str(kernel), "-initrd", str(initrd), "-append", cmdline,
        ], args.log)

        deadline = time.monotonic() + args.timeout
        console.expect(PROMPT, deadline)
        console.send("")
        console.expect(PROMPT, deadline)
        results = run_checks(console, deadline)
    except TimeoutError as error:
        print(f"failed: {error}; serial log in {args.log}")
        return 1
    finally:
        if console:
            console.close()
        shutil.rmtree(workdir, ignore_errors=True)

    failed = 0
    for name, _, expected in CHECKS:
        answer = results[name]
        if re.search(expected, answer):
            print(f"ok    {name}: {answer}")
        else:
            failed += 1
            print(f"FAIL  {name}: {answer}  (expected /{expected}/)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
