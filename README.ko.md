[English](README.md) | [正體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | 한국어

Gentoo CJK 최소 설치 CD
-----------------------
Gentoo의 Catalyst가 공식 Release Engineering spec으로 구축하는 서드파티 amd64
최소 설치 CD입니다. `install-amd64-minimal-*.iso`와의 차이는 다음 세 가지뿐입
니다.

1. 구축 환경에 `gentoo-zh` overlay를 설정한다.
2. 커널이 `sys-kernel/gentoo-cjk-kernel-bin`이다. cjktty 패치를 포함하므로
   Linux 콘솔이 CJK를 표시한다.
3. `sys-fs/zfs`를 그 커널에 맞추어 빌드한다. 따라서 이 매체는 ZFS 풀을 가져올
   수 있다.

나머지는 모두 상류의 것입니다. 패키지 목록, `livecd/unmerge`, `livecd/empty`,
dracut 인자, GRUB 테마가 여기에 해당합니다.

커널 버전은 고정하지 않고 도출합니다. `sys-fs/zfs`가 `MODULES_KERNEL_MAX`에 선언한
버전 이하에서 가장 최신인 `sys-kernel/gentoo-cjk-kernel-bin`을 사용하여, ZFS가
허용하는 범위에서 가장 넓은 하드웨어 지원을 얻습니다. 구축은 그 위를 마스크하고
`portageq best_visible`이 고르게 합니다. zfs가 그 값을 올리면 수정 없이 더 새로운
커널이 선택됩니다. `sys-fs/zfs`는 2.4부터 모듈을 자체에 포함하므로
`sys-fs/zfs-kmod`는 사용하지 않습니다.

stage1은 공식 binhost를 사용합니다. 의존성이 465개 패키지로 전개되고 그 대부분의
시간을 LLVM과 Rust가 차지하기 때문입니다. 둘은 빌드 의존성으로 들어왔다가
`livecd/unmerge`가 다시 제거합니다. stage2는 사용하지 않습니다. `sys-fs/zfs`는 방금
설치한 CJK 커널에 맞추어 빌드해야 하는데 바이너리 패키지는 Gentoo 자체
dist-kernel에 맞추어 빌드되기 때문입니다. 이름으로도 제외하므로 stage2에서
binhost를 켜더라도 이 제약은 유지됩니다.

Fork 출처
---------
이 저장소는 Gentoo Release Engineering 저장소의 fork입니다.

  공식 GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  읽기 전용 미러: https://github.com/gentoo/releng

상류는 `upstream` 리모트로 두고 작업은 `gentoo-cjk` 브랜치에서 합니다. 상류 파일
은 수정하지 않으며, 차이는 다음 추가 경로뿐입니다.

  releases/specs/amd64/installcd-cjk-stage1.replacements
  releases/specs/amd64/installcd-cjk-stage2-minimal.spec.append
  releases/portage/isos-cjk/
  docker/
  tests/

Catalyst의 spec 파서는 뒤에 나온 키가 앞의 키를 대체하므로, 이 append 파일을 구축
시 공식 stage2 spec 뒤에 붙입니다.

대체 표는 공식 stage1 spec이 여전히 나열하지만 `::gentoo`가 제거 예정으로 마스크한
패키지를 다루며, 대체 패키지는 각 마스크 주석이 지목한 것입니다. 옛 아톰이 spec에
없으면 구축을 중단하므로, 상류가 스스로 대체를 반영한 뒤에도 낡은 줄이 조용히 남지
않습니다.

검증
----
`install-amd64-cjk-minimal-20260829T210059Z.iso`, 0.93 GiB. 2026-08-29에 CI가
생성했고 KVM에서 부팅했습니다. `tests/boot-test.py`의 결과는 다음과 같습니다.

    ok    kernel: 7.1.12-gentoo-cjk-dist-bin
    ok    zfs: zfs-loaded
    ok    zpool: no pools available to import
    ok    cjk-console: CONFIG_FRAMEBUFFER_CONSOLE=y CONFIG_FONT_CJK=y CONFIG_FONT_CJK_16x16=y
    ok    storage-tools: listed

시리얼 콘솔은 글리프가 아니라 바이트를 전달하므로 화면에 CJK가 그려지는지는 다루지
않습니다. 확인된 것은 폰트가 커널에 내장되어 있고 framebuffer console이 이어받을 수
있다는 점입니다.

구축
----
    docker build -t gentoo-cjk-livecd -f docker/Dockerfile .
    docker run --rm --privileged -v /dev:/dev \
        -v "$PWD/catalyst:/var/tmp/catalyst" \
        -v "$PWD/output:/output" gentoo-cjk-livecd

Catalyst가 loop 장치와 `mount`를 사용하므로 컨테이너에는 `--privileged`와
`/dev`가 필요합니다. 구축 스크립트가 읽는 환경 변수는 `STOREDIR`,
`OUTPUT_DIR`, `JOBS`, `GENTOO_ZH_URI`, `AUTOBUILDS_URI`입니다.

`build-installcd.sh preflight`는 `emerge --pretend`로 두 패키지 목록을 해석합니다.
약 2분이 걸리며 아무것도 빌드하지 않습니다. 전체 구축은 트리 스냅샷을 위해 loop와
squashfs가 필요하지만 의존성 해석에는 필요하지 않습니다.

진입점은 `preflight`, `stage1`, `stage2`, `all`을 받으며 기본값은 `all`입니다.
`.github/workflows/build-installcd.yml`은 두 단계를 별도의 잡으로 실행합니다.
패키지 목록 전체를 한 잡에서 빌드하면 여섯 시간 제한에 들어가지 않기 때문입니다.
잡 사이에 storedir을 넘기므로 `stage2`에는 트리 스냅샷, stage1 tarball, stage1이
기록한 `build.env`가 필요합니다.

감사의 말
---------
이 저장소는 Gentoo Release Engineering 저장소를 fork한 것입니다. 구축용 spec은 해
당 저장소가 관리합니다. 이 spec을 구축하려면 Gentoo의 Catalyst가 필요합니다.

  Official Repo GitWeb: https://gitweb.gentoo.org/proj/releng.git/
  Read-only mirror: https://github.com/gentoo/releng

https://github.com/zozx/gentoo-cjk-livecd 는 이 방식으로 CJK 설치 CD를 구축할 수
있다는 점과, 추가 `package.use` 항목이 필요한 패키지를 보여 주었습니다.

cjktty 패치와 `sys-kernel/gentoo-cjk-kernel-bin`은
https://github.com/gentoo-zh/overlay 와
https://github.com/gentoo-zh/cjktty-patches 에서 옵니다.
