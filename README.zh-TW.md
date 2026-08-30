[English](README.md) | 正體中文 | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

Gentoo CJK 最小安裝 CD
----------------------
第三方的 amd64 最小安裝 CD，由 Gentoo 的 Catalyst 依官方 Release Engineering
的 spec 建置。與 `install-amd64-minimal-*.iso` 只有三處差別：

1. 建置環境設定 `gentoo-zh` overlay。
2. 核心是 `sys-kernel/gentoo-cjk-kernel-bin`，其中包含 cjktty 補丁，因此 Linux console 可以顯示 CJK。
3. `sys-fs/zfs` 針對該核心編譯，因此鏡像可以匯入 ZFS 儲存池。

其餘都是上游的：套件清單、`livecd/unmerge`、`livecd/empty`、dracut 參數與 GRUB
主題。

核心版本不寫死，而是推導出來的。鏡像取 `sys-kernel/gentoo-cjk-kernel-bin` 在
`sys-fs/zfs` 宣告的 `MODULES_KERNEL_MAX` 以內最新的一版，讓安裝 CD 在 ZFS 容許的
範圍內得到最廣的硬體支援。建置把超過該值的版本遮蔽，交給 `portageq best_visible`
選擇；zfs 提高該值之後會自動選到更新的核心，不需要改任何一行。`sys-fs/zfs` 從 2.4
起自帶模組，因此不使用 `sys-fs/zfs-kmod`。

stage1 使用官方 binhost，因為 stage1 的相依展開是 465 個套件，長尾是 LLVM 與 Rust，兩者
以建置相依的身分進來，最後又被 `livecd/unmerge` 剝掉。stage2 不使用：`sys-fs/zfs`
必須對著剛安裝的 CJK 核心編譯，而二進位版本是對 Gentoo 自己的 dist-kernel 編的。
`sys-fs/zfs` 同時以名稱排除，因此 stage2 日後啟用 binhost 時這條約束仍然成立。

Fork 來源
---------
本倉庫 fork 自 Gentoo Release Engineering 倉庫：

  官方 GitWeb：https://gitweb.gentoo.org/proj/releng.git/
  唯讀鏡像：https://github.com/gentoo/releng

上游是 `upstream` remote，開發位於 `gentoo-cjk` 分支。上游檔案不修改，差異只有以
下新增路徑：

  releases/specs/amd64/installcd-cjk-stage1.replacements
  releases/specs/amd64/installcd-cjk-stage2-minimal.spec.append
  releases/portage/isos-cjk/
  docker/
  tests/

Catalyst 的 spec 解析器以後出現的鍵取代先出現的鍵，所以建置時將該 append 檔連接在
官方 stage2 spec 之後。

替換表處理官方 stage1 spec 仍然列出、而 `::gentoo` 已遮蔽待移除的套件，替代品取自
各自的遮蔽註解。舊原子不在 spec 裡時建置中止，因此上游自己帶了替代品之後，過時的
一行不會靜默留下。

驗證
----
`install-amd64-cjk-minimal-20260829T210059Z.iso`，0.93 GiB，2026-08-29 由 CI 產出
並在 KVM 內開機。`tests/boot-test.py` 的回答：

    ok    kernel: 7.1.12-gentoo-cjk-dist-bin
    ok    zfs: zfs-loaded
    ok    zpool: no pools available to import
    ok    cjk-console: CONFIG_FRAMEBUFFER_CONSOLE=y CONFIG_FONT_CJK=y CONFIG_FONT_CJK_16x16=y
    ok    storage-tools: listed

序列埠傳輸的是位元組而不是字形，因此螢幕上是否畫得出 CJK 不在涵蓋範圍內。已確立
的是字型編入核心，而且 framebuffer console 能夠接手。

建置
----
    docker build -t gentoo-cjk-livecd -f docker/Dockerfile .
    docker run --rm --privileged -v /dev:/dev \
        -v "$PWD/catalyst:/var/tmp/catalyst" \
        -v "$PWD/output:/output" gentoo-cjk-livecd

容器需要 `--privileged` 與 `/dev`，因為 Catalyst 使用 loop 裝置與 `mount`。
建置腳本讀取這些環境變數：`STOREDIR`、`OUTPUT_DIR`、`JOBS`、`GENTOO_ZH_URI`、
`AUTOBUILDS_URI`。

`build-installcd.sh preflight` 以 `emerge --pretend` 解析兩份套件清單，約兩分鐘，
不產生任何建置產物。完整建置需要 loop 與 squashfs 掛載樹快照，相依解析不需要。

進入點接受 `preflight`、`stage1`、`stage2` 或 `all`，預設是 `all`。
`.github/workflows/build-installcd.yml` 把兩個階段拆成兩個 job，因為單一 job 編完
整份套件清單放不進六小時的上限。兩個 job 之間傳遞 storedir，所以 `stage2` 需要樹
快照、stage1 的 tarball，以及 stage1 寫下的 `build.env`。

致謝
----
本倉庫 fork 自 Gentoo Release Engineering 倉庫，建置用的 spec 由該倉庫維護。
建置這些 spec 需要 Gentoo 的 Catalyst。

  Official Repo GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  Read-only mirror: https://github.com/gentoo/releng

https://github.com/zozx/gentoo-cjk-livecd 示範以這個方式建置 CJK 安裝 CD，並指出
哪些套件需要額外的 `package.use` 條目。

cjktty 補丁與 `sys-kernel/gentoo-cjk-kernel-bin` 來自
https://github.com/gentoo-zh/overlay 與
https://github.com/gentoo-zh/cjktty-patches。
