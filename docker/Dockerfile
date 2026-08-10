FROM gentoo/stage3:amd64-openrc

COPY docker/etc-portage/ /etc/portage/

# The snapshot and the seed are both signature-checked, hence the release key.
# Listing gemato would pull a rebuild that conflicts with the installed slot.
RUN emerge-webrsync \
 && emerge --quiet --verbose --getbinpkg \
      dev-util/catalyst \
      net-misc/wget \
      sec-keys/openpgp-keys-gentoo-release \
 && rm -rf /var/cache/distfiles/* /var/cache/binpkgs/* /var/db/repos/gentoo

# The official installcd spec names a cdtar that entered catalyst after the
# 4.1.1 release, so releng runs catalyst from git and the released package
# lacks it. Pinned to the commit that added it; drop this once a release ships.
ARG CDTAR_COMMIT=11967e5fb04b743fa02cad3ea7f0239896c9fd0a
ARG CDTAR_SHA256=9bd3d05c6fb1428f5e50fed8bbad048fe495667f67cb9454461418163a9aa87f
RUN cdtar=/usr/share/catalyst/livecd/cdtar/grub-theme-gentoo_frosted.tar.bz2 \
 && if [ -e "$cdtar" ]; then \
      echo "catalyst now ships the cdtar; remove this stage from the Dockerfile"; \
    else \
      wget -q -O "$cdtar" "https://gitweb.gentoo.org/proj/catalyst.git/plain/livecd/cdtar/grub-theme-gentoo_frosted.tar.bz2?id=${CDTAR_COMMIT}" \
      && echo "${CDTAR_SHA256}  $cdtar" | sha256sum -c -; \
    fi

COPY . /repo

ENTRYPOINT ["/repo/docker/build-installcd.sh"]
