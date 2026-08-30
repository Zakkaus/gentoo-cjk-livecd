English | [正體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

Gentoo CJK Minimal Installation CD
----------------------------------
A third-party amd64 minimal installation CD, built by Gentoo's Catalyst from the
official Release Engineering specs. It differs from
`install-amd64-minimal-*.iso` in three named ways only:

1. the build has the `gentoo-zh` overlay configured;
2. the kernel is `sys-kernel/gentoo-cjk-kernel-bin`, which carries the cjktty
   patch, so the Linux console renders CJK;
3. `sys-fs/zfs` is built against that kernel, so the medium can import a pool.

Everything else is upstream's: the package list, `livecd/unmerge`,
`livecd/empty`, the dracut arguments and the GRUB theme.

The kernel version is derived, not written down. The medium takes the newest
`sys-kernel/gentoo-cjk-kernel-bin` at or below what `sys-fs/zfs` declares in
`MODULES_KERNEL_MAX`, so an install CD gets as much hardware support as ZFS
allows. The build masks everything above that and lets `portageq best_visible`
choose; when zfs raises the value, a newer kernel is picked with no edit. Since
2.4, `sys-fs/zfs` carries the module itself, so `sys-fs/zfs-kmod` is not used.

stage1 pulls from the official binhost, because its dependency graph is 465
packages and the long tail is LLVM and Rust, which reach it as build
dependencies and are stripped again by `livecd/unmerge`. stage2 does not:
`sys-fs/zfs` has to be compiled against the CJK kernel that was just installed,
and a binary one is built against Gentoo's own dist-kernel. It is excluded by
name as well, so the rule survives someone enabling the binhost there.

Fork
----
This repository is a fork of the Gentoo Release Engineering repository:

  Official Repo GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  Read-only mirror: https://github.com/gentoo/releng

It is tracked as the `upstream` remote and the work sits on the `gentoo-cjk`
branch. Upstream files are not modified. The deviation is these added paths:

  releases/specs/amd64/installcd-cjk-stage1.replacements
  releases/specs/amd64/installcd-cjk-stage2-minimal.spec.append
  releases/portage/isos-cjk/
  docker/
  tests/

Catalyst's spec parser lets a later key replace an earlier one, so the append
file is concatenated onto the official stage2 spec at build time.

The replacements file covers packages the official stage1 spec still lists that
`::gentoo` has masked for removal, each replaced by the package its mask comment
names. The build aborts when an old atom is no longer in the spec, so a stale
line cannot pass unnoticed once upstream carries the replacement itself.

Verification
------------
`install-amd64-cjk-minimal-20260829T210059Z.iso`, 0.93 GiB, built by CI on
2026-08-29 and booted in KVM. `tests/boot-test.py` answered:

    ok    kernel: 7.1.12-gentoo-cjk-dist-bin
    ok    zfs: zfs-loaded
    ok    zpool: no pools available to import
    ok    cjk-console: CONFIG_FRAMEBUFFER_CONSOLE=y CONFIG_FONT_CJK=y CONFIG_FONT_CJK_16x16=y
    ok    storage-tools: listed

A serial console carries bytes, not glyphs, so whether CJK is drawn on screen is
not covered. What is established is that the font is built into the kernel and
that the framebuffer console can take over.

Building
--------
    docker build -t gentoo-cjk-livecd -f docker/Dockerfile .
    docker run --rm --privileged -v /dev:/dev \
        -v "$PWD/catalyst:/var/tmp/catalyst" \
        -v "$PWD/output:/output" gentoo-cjk-livecd

The container needs `--privileged` and `/dev` because Catalyst uses loop devices
and `mount`. `STOREDIR`, `OUTPUT_DIR`, `JOBS`, `GENTOO_ZH_URI` and
`AUTOBUILDS_URI` are the environment variables the build script reads.

`build-installcd.sh preflight` resolves both package lists with `emerge
--pretend` in about two minutes, without building anything. A full build needs
loop and squashfs for the tree snapshot; dependency resolution does not.

The entrypoint takes `preflight`, `stage1`, `stage2` or `all`, and defaults to
`all`. The workflow in `.github/workflows/build-installcd.yml` runs the stages
as separate jobs, each with its own six-hour budget. It passes the storedir
between them, so `stage2` needs the tree snapshot, the stage1 tarball and the
`build.env` that stage1 wrote.

Credits
-------
This repository forks the Gentoo Release Engineering repository, which hosts the
build specs. Building them requires Gentoo's Catalyst.

  Official Repo GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  Read-only mirror: https://github.com/gentoo/releng

https://github.com/zozx/gentoo-cjk-livecd demonstrated that a CJK install CD can
be built this way, and identified the packages that need extra `package.use`
entries.

The cjktty patch and `sys-kernel/gentoo-cjk-kernel-bin` come from
https://github.com/gentoo-zh/overlay and
https://github.com/gentoo-zh/cjktty-patches.
