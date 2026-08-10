#!/usr/bin/env bash
# Build the Gentoo CJK minimal installation CD from the official releng specs.
#
# usage: build-installcd.sh [preflight|stage1|stage2|all]
#
# Separate stages so each gets its own six-hour GitHub job. Measured 2026-08-10,
# stage1 took 1h22m with the binhost on, so the split is headroom, not need.
set -euo pipefail

STAGE=${1:-all}
case ${STAGE} in
	preflight | stage1 | stage2 | all) ;;
	*) echo "usage: ${0##*/} [preflight|stage1|stage2|all]" >&2; exit 1 ;;
esac

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STOREDIR=${STOREDIR:-/var/tmp/catalyst}
OUTPUT_DIR=${OUTPUT_DIR:-/output}
GENTOO_ZH_URI=${GENTOO_ZH_URI:-https://github.com/gentoo-zh/overlay.git}
AUTOBUILDS_URI=${AUTOBUILDS_URI:-https://distfiles.gentoo.org/releases/amd64/autobuilds}
JOBS=${JOBS:-$(nproc)}

REL_TYPE=23.0-default
KERNEL_ATOM=sys-kernel/gentoo-cjk-kernel-bin
SPEC_SRC=${REPO_DIR}/releases/specs/amd64
SPEC_DIR=${STOREDIR}/spec
CONF_DIR=${STOREDIR}/portage-confdir
CATALYST_CONF=${STOREDIR}/catalyst.conf
ENVSCRIPT=${STOREDIR}/envscript
BUILD_ENV=${STOREDIR}/build.env

log() { printf '\n=== %s\n' "$*"; }

# A container's own /dev has no loop devices unless the host's is bound in.
setup_loop_devices() {
	[[ -e /dev/loop-control ]] || mknod /dev/loop-control c 10 237
	local i
	for i in {0..15}; do
		[[ -b /dev/loop${i} ]] || mknod -m 0660 /dev/loop${i} b 7 "${i}"
	done
}

# Unset jobs means make -j1. The file is TOML, where a repeated key is an
# error, so envscript is dropped before it is set.
write_catalyst_conf() {
	grep -v '^envscript' /etc/catalyst/catalyst.conf >"${CATALYST_CONF}"
	printf 'jobs = %s\nload-average = %s.0\nenvscript = "%s"\n' \
		"${JOBS}" "${JOBS}" "${ENVSCRIPT}" >>"${CATALYST_CONF}"
}

# Only EMERGE_DEFAULT_OPTS survives: setup_features() overwrites FEATURES right
# after chroot-functions.sh sources this.
write_envscript() {
	if [[ $1 == stage1 ]]; then
		# The seed carries binrepos.conf already and portage runs getuto on the
		# first fetch, so the binhost only has to be switched on.
		cat >"${ENVSCRIPT}" <<-'EOF'
			export EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg --binpkg-respect-use=y --usepkg-exclude sys-fs/zfs --getbinpkg-exclude sys-fs/zfs"
		EOF
	else
		# stage2 builds sys-fs/zfs against the kernel kmerge.sh just installed,
		# and a binary one is built against Gentoo's dist-kernel.
		: >"${ENVSCRIPT}"
	fi
}

compose_portage_confdir() {
	rm -rf "${CONF_DIR}"
	mkdir -p "${CONF_DIR}"
	cp -a "${REPO_DIR}/releases/portage/isos/." "${CONF_DIR}/"
	cp -a "${REPO_DIR}/releases/portage/isos-cjk/." "${CONF_DIR}/"
}

fetch_overlay() {
	local dest=${STOREDIR}/repos/gentoo-zh
	mkdir -p "${STOREDIR}/repos"
	if [[ -d ${dest}/.git ]]; then
		git -C "${dest}" fetch --depth 1 origin HEAD
		git -C "${dest}" reset --hard FETCH_HEAD
	else
		git clone --depth 1 "${GENTOO_ZH_URI}" "${dest}"
	fi
	grep -q '^virtual/dist-kernel$' "${dest}/profiles/package.mask" ||
		log "gentoo-zh no longer masks virtual/dist-kernel; the unmask in releases/portage/isos-cjk is now inert"
}

# Returns the seed timestamp on stdout; everything else goes to stderr.
fetch_seed() {
	local listing path tarball timestamp dest
	listing=$(wget -qO- "${AUTOBUILDS_URI}/latest-stage3-amd64-openrc.txt")
	path=$(grep -E '^[0-9]{8}T[0-9]{6}Z/stage3-amd64-openrc-.*\.tar\.xz' <<<"${listing}" | awk '{print $1}')
	[[ -n ${path} ]] || { echo "no stage3 in latest-stage3-amd64-openrc.txt" >&2; exit 1; }

	tarball=${path##*/}
	timestamp=${tarball#stage3-amd64-openrc-}
	timestamp=${timestamp%.tar.xz}
	dest=${STOREDIR}/builds/${REL_TYPE}/${tarball}

	if [[ ! -s ${dest} ]]; then
		mkdir -p "${dest%/*}"
		# catalyst searches that directory by extension, so a signature beside
		# the seed reads as a second match.
		wget -q -O "${dest}.part" "${AUTOBUILDS_URI}/${path}" >&2
		wget -q -O "${STOREDIR}/seed.asc" "${AUTOBUILDS_URI}/${path}.asc" >&2
		verify_seed "${dest}.part" "${STOREDIR}/seed.asc" >&2
		rm -f "${STOREDIR}/seed.asc"
		mv "${dest}.part" "${dest}"
	fi

	echo "${timestamp}"
}

verify_seed() {
	local gnupghome
	gnupghome=$(mktemp -d)
	GNUPGHOME=${gnupghome} gpg --batch --quiet --import /usr/share/openpgp-keys/gentoo-release.asc
	GNUPGHOME=${gnupghome} gpg --batch --verify "$2" "$1"
	rm -rf "${gnupghome}"
}

# Aborting on a vanished atom is the point: a replacement that silently stops
# matching is how a build succeeds with the wrong package set.
replace_packages() {
	local spec=$1 table=$2 old new
	while read -r old new; do
		[[ -z ${old} || ${old} == "#"* ]] && continue
		grep -qxF "$(printf '\t%s' "${old}")" "${spec}" ||
			{ echo "${spec} no longer lists ${old}" >&2; exit 1; }
		awk -v old="$(printf '\t%s' "${old}")" -v new="$(printf '\t%s' "${new}")" \
			'$0 == old { print new; next } { print }' "${spec}" >"${spec}.new"
		mv "${spec}.new" "${spec}"
	done <"${table}"
}

# The append file works only because a later key replaces an earlier one, so a
# parser change would otherwise yield an image with the wrong kernel.
assert_override() {
	local spec=$1 key=$2 want=$3 got
	got=$(grep "^${key}:" "${spec}" | tail -n 1)
	[[ ${got} == "${key}:${want:+ }${want}" ]] ||
		{ echo "${spec}: ${key} is '${got}', not '${key}:${want:+ }${want}'" >&2; exit 1; }
}

overlay_versions() {
	local ebuild
	for ebuild in "${STOREDIR}/repos/gentoo-zh/${KERNEL_ATOM}"/*.ebuild; do
		ebuild=${ebuild##*/gentoo-cjk-kernel-bin-}
		echo "${ebuild%.ebuild}"
	done
}

# The version sys-fs/zfs declares it was tested against, read from a checked-out
# sys-fs/zfs directory. Only a stable amd64 ebuild counts: portage installs the
# newest visible one and this build does not accept ~amd64. A version with no
# dot in it is the masked live ebuild.
zfs_kernel_max() {
	local dir=$1 ebuild='' file cap
	for file in $(find "${dir}" -maxdepth 1 -name 'zfs-*.ebuild' |
			grep -E '/zfs-[0-9]+(\.[0-9]+)+(-r[0-9]+)?\.ebuild$' | sort -V); do
		if grep -E '^[[:space:]]*KEYWORDS=' "${file}" |
				grep -qE '(^|["[:space:]])amd64(["[:space:]]|$)'; then
			ebuild=${file}
		fi
	done
	[[ -n ${ebuild} ]] ||
		{ echo "no stable amd64 sys-fs/zfs ebuild in ${dir}" >&2; exit 1; }
	cap=$(sed -n 's/^MODULES_KERNEL_MAX=//p' "${ebuild}" | tail -n 1)
	[[ -n ${cap} ]] ||
		{ echo "no MODULES_KERNEL_MAX in ${ebuild}" >&2; exit 1; }
	echo "${cap} ${ebuild##*/}"
}

zfs_dir_from_snapshot() {
	local dir=${STOREDIR}/zfs-ebuilds
	rm -rf "${dir}"
	mkdir -p "${dir}"
	git -C "${STOREDIR}/repos/gentoo.git" archive "${TREEISH}" sys-fs/zfs | tar -x -C "${dir}"
	echo "${dir}/sys-fs/zfs"
}

# MODULES_KERNEL_MAX=7.0 allows 7.0.x, so the first excluded version is 7.1.
exclusive_bound() {
	echo "${1%.*}.$(( ${1##*.} + 1 ))"
}

# Every version of the kernel is ~amd64, so bounding the keyword bounds what is
# visible, and portageq best_visible then picks the newest below it. The file is
# generated because the bound comes from what sys-fs/zfs declares.
write_kernel_bound() {
	local bound=$1
	mkdir -p "${CONF_DIR}/package.accept_keywords"
	printf '# Generated: the bound is the first version above what sys-fs/zfs declares.\n<%s-%s ~amd64\n' \
		"${KERNEL_ATOM}" "${bound}" \
		>"${CONF_DIR}/package.accept_keywords/gentoo-cjk-kernel-bin"
}

# Without this, an overlay carrying nothing below the bound surfaces hours later
# as portageq best_visible returning nothing.
check_kernel_available() {
	local bound=$1 version chosen=''
	for version in $(overlay_versions); do
		if [[ ${version} != "${bound}" &&
			$(printf '%s\n%s\n' "${version}" "${bound}" | sort -V | head -n 1) == "${version}" ]]; then
			chosen=${version}
		fi
	done
	[[ -n ${chosen} ]] || {
		echo "gentoo-zh carries no ${KERNEL_ATOM} below ${bound}. Available:" >&2
		overlay_versions >&2
		exit 1
	}
	echo "kernel ${chosen} is the newest below ${bound}"
}

# Tab-indented values under a list key, which is how catalyst writes them.
spec_list() {
	awk -v key="$1:" '$0 == key { grab = 1; next }
		grab && /^\t/ { print $1; next }
		grab { exit }' "$2"
}

# catalyst reports a missing cdtar one second in, but only after the image has
# been built and stage1 has run, so the fast job checks it instead.
check_spec_files() {
	local spec=$1 key path missing=0
	for key in livecd/cdtar livecd/motd livecd/readme; do
		path=$(sed -n "s|^${key}: ||p" "${spec}")
		[[ -n ${path} && ${path} == /* ]] || continue
		[[ -e ${path} ]] || { echo "${spec} names ${key} ${path}, which is absent" >&2; missing=1; }
	done
	[[ ${missing} -eq 0 ]] || exit 1
}

# Resolve the package lists without building them. catalyst needs loop and
# squashfs for the tree snapshot, so a full run is impossible on a host kernel
# without them; dependency resolution is not, and that is where the masked
# packages and USE conflicts show up.
preflight() {
	local spec=${STOREDIR}/preflight.spec profile cap ebuild bound
	mkdir -p "${SPEC_DIR}"
	cp "${SPEC_SRC}/installcd-stage1.spec" "${spec}"
	replace_packages "${spec}" "${SPEC_SRC}/installcd-cjk-stage1.replacements"

	log "Syncing the ebuild repo"
	emerge-webrsync

	read -r cap ebuild < <(zfs_kernel_max /var/db/repos/gentoo/sys-fs/zfs)
	bound=$(exclusive_bound "${cap}")
	log "${ebuild} declares ${cap}, so the kernel stays below ${bound}"
	write_kernel_bound "${bound}"
	check_kernel_available "${bound}"

	cp -a "${CONF_DIR}/." /etc/portage/
	mkdir -p /etc/portage/repos.conf
	cat >/etc/portage/repos.conf/gentoo-zh.conf <<-EOF
		[gentoo-zh]
		location = ${STOREDIR}/repos/gentoo-zh
	EOF

	profile=$(sed -n 's/^profile: //p' "${spec}")
	log "Setting the profile to ${profile}"
	eselect profile set "${profile}"

	log "Resolving livecd/packages"
	USE="$(spec_list livecd/use "${spec}" | tr '\n' ' ')" \
		emerge --pretend --quiet --usepkg=n $(spec_list livecd/packages "${spec}")

	log "Checking the files the stage2 spec names"
	check_spec_files "${SPEC_SRC}/installcd-stage2-minimal.spec"

	# kmerge.sh merges a dist-kernel with USE=-initramfs, and that flag decides
	# whether installkernel[dracut] is required.
	log "Resolving the stage2 kernel and its modules"
	USE="-initramfs" emerge --pretend --quiet --usepkg=n "${KERNEL_ATOM}" sys-fs/zfs
}

render_spec() {
	local base=$1 append=$2 dest=$3
	cat "${base}" "${append}" |
		sed -e "s|@TIMESTAMP@|${TIMESTAMP}|g" \
		    -e "s|@DATESTAMP@|${DATESTAMP}|g" \
		    -e "s|@TREESTAMP@|${TREESTAMP}|g" \
		    -e "s|@TREEISH@|${TREEISH}|g" \
		    -e "s|@REPO_DIR@|${REPO_DIR}|g" \
		    -e "s|@STOREDIR@|${STOREDIR}|g" >"${dest}"
}

build_stage1() {
	write_envscript stage1

	log "Fetching the stage3 seed"
	TIMESTAMP=$(fetch_seed)
	echo "seed timestamp ${TIMESTAMP}"

	log "Creating the ebuild repo snapshot"
	catalyst -c "${CATALYST_CONF}" -s stable
	TREEISH=$(git -C "${STOREDIR}/repos/gentoo.git" rev-parse stable)
	echo "treeish ${TREEISH}"

	# Upstream's tools/catalyst-auto takes its stamp from the tree commit and
	# the date from today. Our seed is downloaded rather than built in the same
	# run, so TIMESTAMP has to stay the seed's name for source_subpath to
	# resolve, and the image is named from the tree instead.
	TREESTAMP=$(git -C "${STOREDIR}/repos/gentoo.git" show --no-patch \
		--format=%cd --date=format:%Y%m%dT%H%M%SZ "${TREEISH}")
	DATESTAMP=$(date -u +%Y%m%d)
	echo "image stamp ${TREESTAMP}, volume date ${DATESTAMP}"

	local cap ebuild bound
	read -r cap ebuild < <(zfs_kernel_max "$(zfs_dir_from_snapshot)")
	bound=$(exclusive_bound "${cap}")
	echo "${ebuild} declares ${cap}, so the kernel stays below ${bound}"
	write_kernel_bound "${bound}"
	check_kernel_available "${bound}"

	# stage2 cannot rederive these: the stable branch moves, the seed listing
	# names a newer stage3 by then, and the bound has to match what stage1 used.
	printf 'TIMESTAMP=%s\nTREEISH=%s\nTREESTAMP=%s\nDATESTAMP=%s\nKERNEL_BOUND=%s\n' \
		"${TIMESTAMP}" "${TREEISH}" "${TREESTAMP}" "${DATESTAMP}" "${bound}" >"${BUILD_ENV}"

	mkdir -p "${SPEC_DIR}"
	render_spec "${SPEC_SRC}/installcd-stage1.spec" /dev/null \
		"${SPEC_DIR}/installcd-cjk-stage1.spec"
	replace_packages "${SPEC_DIR}/installcd-cjk-stage1.spec" \
		"${SPEC_SRC}/installcd-cjk-stage1.replacements"

	log "Building livecd-stage1"
	catalyst -c "${CATALYST_CONF}" -f "${SPEC_DIR}/installcd-cjk-stage1.spec"
}

build_stage2() {
	write_envscript stage2
	[[ -s ${BUILD_ENV} ]] || { echo "no ${BUILD_ENV}; run stage1 first" >&2; exit 1; }
	# shellcheck source=/dev/null
	source "${BUILD_ENV}"
	write_kernel_bound "${KERNEL_BOUND}"
	check_kernel_available "${KERNEL_BOUND}"

	local spec=${SPEC_DIR}/installcd-cjk-stage2-minimal.spec
	mkdir -p "${SPEC_DIR}"
	render_spec "${SPEC_SRC}/installcd-stage2-minimal.spec" \
		"${SPEC_SRC}/installcd-cjk-stage2-minimal.spec.append" "${spec}"
	assert_override "${spec}" repos "${STOREDIR}/repos/gentoo-zh"
	assert_override "${spec}" portage_confdir "${CONF_DIR}"
	assert_override "${spec}" boot/kernel/gentoo/sources "${KERNEL_ATOM}"
	assert_override "${spec}" boot/kernel/gentoo/config ""
	assert_override "${spec}" livecd/iso "install-amd64-cjk-minimal-${TREESTAMP}.iso"
	assert_override "${spec}" livecd/volid "Gentoo-CJK-amd64-${DATESTAMP}"

	log "Building livecd-stage2"
	catalyst -c "${CATALYST_CONF}" -f "${spec}"

	log "Collecting the image"
	mkdir -p "${OUTPUT_DIR}"
	local iso=${STOREDIR}/builds/${REL_TYPE}/install-amd64-cjk-minimal-${TREESTAMP}.iso
	local artifact
	for artifact in "${iso}" "${iso}".*; do
		if [[ -f ${artifact} ]]; then
			cp -f "${artifact}" "${OUTPUT_DIR}/"
		fi
	done
	ls -l "${OUTPUT_DIR}"
}

compose_portage_confdir

log "Fetching the gentoo-zh overlay"
fetch_overlay

if [[ ${STAGE} == preflight ]]; then
	preflight
	exit 0
fi

setup_loop_devices
# Each stage rewrites this before its own catalyst run; catalyst refuses to
# start when the path is missing.
write_envscript "${STAGE}"
write_catalyst_conf

[[ ${STAGE} == stage2 ]] || build_stage1
[[ ${STAGE} == stage1 ]] || build_stage2
