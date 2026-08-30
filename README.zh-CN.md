[English](README.md) | [正體中文](README.zh-TW.md) | 简体中文 | [日本語](README.ja.md) | [한국어](README.ko.md)

Gentoo CJK 最小安装 CD
----------------------
第三方的 amd64 最小安装 CD，由 Gentoo 的 Catalyst 依官方 Release Engineering
的 spec 构建。与 `install-amd64-minimal-*.iso` 只有三处差别：

1. 构建环境配置 `gentoo-zh` overlay。
2. 内核是 `sys-kernel/gentoo-cjk-kernel-bin`，其中包含 cjktty 补丁，因此 Linux console 可以显示 CJK。
3. `sys-fs/zfs` 针对该内核编译，因此镜像可以导入 ZFS 存储池。

其余都是上游的：软件包清单、`livecd/unmerge`、`livecd/empty`、dracut 参数与 GRUB
主题。

内核版本不写死，而是推导出来的。镜像取 `sys-kernel/gentoo-cjk-kernel-bin` 在
`sys-fs/zfs` 声明的 `MODULES_KERNEL_MAX` 以内最新的一版，让安装 CD 在 ZFS 容许的
范围内得到最广的硬件支持。构建把超过该值的版本屏蔽，交给 `portageq best_visible`
选择；zfs 提高该值之后会自动选到更新的内核，不需要改任何一行。`sys-fs/zfs` 从 2.4
起自带模块，因此不使用 `sys-fs/zfs-kmod`。

stage1 使用官方 binhost，因为 stage1 的依赖展开是 465 个软件包，长尾是 LLVM 与 Rust，两
者以构建依赖的身份进来，最后又被 `livecd/unmerge` 剥掉。stage2 不使用：
`sys-fs/zfs` 必须对着刚安装的 CJK 内核编译，而二进制版本是对 Gentoo 自己的
dist-kernel 编的。`sys-fs/zfs` 同时以名称排除，因此 stage2 日后启用 binhost 时这条约束仍然
成立。

Fork 来源
---------
本仓库 fork 自 Gentoo Release Engineering 仓库：

  官方 GitWeb：https://gitweb.gentoo.org/proj/releng.git/
  只读镜像：https://github.com/gentoo/releng

上游是 `upstream` remote，开发位于 `gentoo-cjk` 分支。上游文件不修改，差异只有以
下新增路径：

  releases/specs/amd64/installcd-cjk-stage1.replacements
  releases/specs/amd64/installcd-cjk-stage2-minimal.spec.append
  releases/portage/isos-cjk/
  docker/
  tests/

Catalyst 的 spec 解析器以后出现的键取代先出现的键，所以构建时将该 append 文件连接
在官方 stage2 spec 之后。

替换表处理官方 stage1 spec 仍然列出、而 `::gentoo` 已屏蔽待移除的软件包，替代品取
自各自的屏蔽注释。旧原子不在 spec 里时构建中止，因此上游自己带了替代品之后，过时的
一行不会静默留下。

验证
----
`install-amd64-cjk-minimal-20260829T210059Z.iso`，0.93 GiB，2026-08-29 由 CI 产出
并在 KVM 内启动。`tests/boot-test.py` 的回答：

    ok    kernel: 7.1.12-gentoo-cjk-dist-bin
    ok    zfs: zfs-loaded
    ok    zpool: no pools available to import
    ok    cjk-console: CONFIG_FRAMEBUFFER_CONSOLE=y CONFIG_FONT_CJK=y CONFIG_FONT_CJK_16x16=y
    ok    storage-tools: listed

串口传输的是字节而不是字形，因此屏幕上是否画得出 CJK 不在覆盖范围内。已确立的是
字体编入内核，而且 framebuffer console 能够接手。

构建
----
    docker build -t gentoo-cjk-livecd -f docker/Dockerfile .
    docker run --rm --privileged -v /dev:/dev \
        -v "$PWD/catalyst:/var/tmp/catalyst" \
        -v "$PWD/output:/output" gentoo-cjk-livecd

容器需要 `--privileged` 与 `/dev`，因为 Catalyst 使用 loop 设备与 `mount`。
构建脚本读取这些环境变量：`STOREDIR`、`OUTPUT_DIR`、`JOBS`、`GENTOO_ZH_URI`、
`AUTOBUILDS_URI`。

`build-installcd.sh preflight` 以 `emerge --pretend` 解析两份软件包清单，约两分钟，
不产生任何构建产物。完整构建需要 loop 与 squashfs 挂载树快照，依赖解析不需要。

入口点接受 `preflight`、`stage1`、`stage2` 或 `all`，默认是 `all`。
`.github/workflows/build-installcd.yml` 把两个阶段拆成两个 job，因为单一 job 编完
整份软件包清单放不进六小时的上限。两个 job 之间传递 storedir，所以 `stage2` 需要树
快照、stage1 的 tarball，以及 stage1 写下的 `build.env`。

致谢
----
本仓库 fork 自 Gentoo Release Engineering 仓库，构建用的 spec 由该仓库维护。
构建这些 spec 需要 Gentoo 的 Catalyst。

  Official Repo GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  Read-only mirror: https://github.com/gentoo/releng

https://github.com/zozx/gentoo-cjk-livecd 示范以这个方式构建 CJK 安装 CD，并指出
哪些软件包需要额外的 `package.use` 条目。

cjktty 补丁与 `sys-kernel/gentoo-cjk-kernel-bin` 来自
https://github.com/gentoo-zh/overlay 与
https://github.com/gentoo-zh/cjktty-patches。
