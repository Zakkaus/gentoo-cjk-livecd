[English](README.md) | [正體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | 日本語 | [한국어](README.ko.md)

Gentoo CJK 最小インストール CD
------------------------------
Gentoo の Catalyst が公式 Release Engineering の spec から構築する、サードパー
ティの amd64 最小インストール CD です。`install-amd64-minimal-*.iso` との違いは
次の三点だけです。

1. 構築環境に `gentoo-zh` overlay を設定する。
2. カーネルは `sys-kernel/gentoo-cjk-kernel-bin` である。cjktty パッチを含むた
   め、Linux コンソールが CJK を表示する。
3. `sys-fs/zfs` をそのカーネル向けに構築する。したがってこのメディアは ZFS
   プールをインポートできる。

残りはすべて上流のものです。パッケージ一覧、`livecd/unmerge`、`livecd/empty`、
dracut の引数、GRUB テーマが該当します。

カーネルの版は固定せず導出します。`sys-fs/zfs` が `MODULES_KERNEL_MAX` に宣言し
た版以下で最新の `sys-kernel/gentoo-cjk-kernel-bin` を採用し、ZFS が許す範囲で最
も広いハードウェア対応を得ます。構築はそれを超える版をマスクし、`portageq
best_visible` に選ばせます。zfs がその値を上げれば、変更なしに新しいカーネルが選
ばれます。`sys-fs/zfs` は 2.4 以降モジュールを自身に含むため `sys-fs/zfs-kmod` は
使いません。

stage1 は公式 binhost を利用します。依存関係が 465 パッケージに展開され、その大半
の時間を占めるのが LLVM と Rust だからです。両者はビルド依存として入り、最後は
`livecd/unmerge` が取り除きます。stage2 は利用しません。`sys-fs/zfs` は直前に導入
した CJK カーネル向けに構築する必要があり、バイナリ版は Gentoo 自身の dist-kernel
向けに構築されているためです。名前でも除外してあるので、stage2 で binhost を有効
にしてもこの制約は保たれます。

Fork 元
-------
このリポジトリは Gentoo Release Engineering リポジトリの fork です。

  公式 GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  読み取り専用ミラー: https://github.com/gentoo/releng

上流は `upstream` リモートとして参照し、作業は `gentoo-cjk` ブランチで行います。
上流のファイルは変更せず、差分は次の追加パスだけです。

  releases/specs/amd64/installcd-cjk-stage1.replacements
  releases/specs/amd64/installcd-cjk-stage2-minimal.spec.append
  releases/portage/isos-cjk/
  docker/
  tests/

Catalyst の spec パーサーは後に現れたキーで前のキーを置き換えるため、この append
ファイルを構築時に公式 stage2 spec の末尾へ連結します。

置換表は、公式 stage1 spec がなお列挙し `::gentoo` が削除予定でマスクしたパッケー
ジを扱い、代替は各マスクコメントが指名したものです。旧アトムが spec に無い場合は構
築を中止するため、上流が自ら代替を採用した後も古い行が黙って残ることはありません。

検証
----
`install-amd64-cjk-minimal-20260829T210059Z.iso`、0.93 GiB。2026-08-29 に CI が生成
し、KVM で起動しました。`tests/boot-test.py` の結果は次のとおりです。

    ok    kernel: 7.1.12-gentoo-cjk-dist-bin
    ok    zfs: zfs-loaded
    ok    zpool: no pools available to import
    ok    cjk-console: CONFIG_FRAMEBUFFER_CONSOLE=y CONFIG_FONT_CJK=y CONFIG_FONT_CJK_16x16=y
    ok    storage-tools: listed

シリアルコンソールが伝えるのはバイト列であって字形ではないため、画面に CJK が描画
されるかは対象外です。確認できたのは、フォントがカーネルに組み込まれており、
framebuffer console が引き継げることです。

構築
----
    docker build -t gentoo-cjk-livecd -f docker/Dockerfile .
    docker run --rm --privileged -v /dev:/dev \
        -v "$PWD/catalyst:/var/tmp/catalyst" \
        -v "$PWD/output:/output" gentoo-cjk-livecd

Catalyst が loop デバイスと `mount` を使うため、コンテナには `--privileged` と
`/dev` が必要です。構築スクリプトが読む環境変数は `STOREDIR`、`OUTPUT_DIR`、
`JOBS`、`GENTOO_ZH_URI`、`AUTOBUILDS_URI` です。

`build-installcd.sh preflight` は `emerge --pretend` で両方のパッケージ一覧を解決
します。所要は約二分で、構築は行いません。完全な構築はツリースナップショットの
ために loop と squashfs を要しますが、依存解決には不要です。

エントリポイントは `preflight`、`stage1`、`stage2`、`all` を受け取り、既定は
`all` です。
`.github/workflows/build-installcd.yml` は二つの段階を別々のジョブとして実行しま
す。パッケージ一覧を一つのジョブで構築すると六時間の上限に収まらないためです。
ジョブ間で storedir を受け渡すので、`stage2` にはツリースナップショット、stage1
の tarball、stage1 が書いた `build.env` が必要です。

謝辞
----
本リポジトリは Gentoo Release Engineering リポジトリを fork したものです。構築用
の spec は同リポジトリが保守しています。これらの spec の構築には Gentoo の
Catalyst が必要です。

  Official Repo GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  Read-only mirror: https://github.com/gentoo/releng

https://github.com/zozx/gentoo-cjk-livecd は、この方法で CJK インストール CD を
構築できること、および追加の `package.use` を要するパッケージを示しました。

cjktty パッチと `sys-kernel/gentoo-cjk-kernel-bin` は
https://github.com/gentoo-zh/overlay および
https://github.com/gentoo-zh/cjktty-patches に由来します。
