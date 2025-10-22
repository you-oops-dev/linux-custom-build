#!/usr/bin/env bash

set -euxo pipefail

if [ -z "${1:-}" ]; then
    $0 setup-builddeps
    $0 setup-secureboot
    $0 build-packages
    $0 sign-packages
    exit
fi

pacman()
{
    command pacman --noconfirm "$@"
}

case "${1:-}" in
setup-builddeps)
    # Update the container
    pacman -Syu

    # Install makepkg deps
    pacman -S binutils fakeroot base base-devel git wget axel ccache gcc curl sudo --needed

    # Install tools for singing the kernel for secureboot
    pacman -S sbsigntools

    # Install my repo powered OBS
    pacman-key --init && echo -e "\n[home_you-oops-dev_Arch]\nServer = https://download.opensuse.org/repositories/home:/you-oops-dev/Arch/\$arch" | tee -ai /etc/pacman.conf && curl -4s "https://build.opensuse.org/projects/home:you-oops-dev/signing_keys/download?kind=gpg" > /tmp/home_you-oops-dev_key.gpg && pacman-key --add /tmp/home_you-oops-dev_key.gpg && pacman-key --finger 8f390f892aeafe7d && pacman-key --lsign-key 8f390f892aeafe7d && pacman -Sy && pacman -Fy

    # Install package from my repository
    pacman -S cmake3-bin --needed

    # Install actual build dependencies from PKGBUILD
    pushd pkg/arch/kernel || exit 1

    deps=$(bash -c 'source PKGBUILD && echo "${makedepends[@]}"')
    pacman --noconfirm -S ${deps}

    popd || exit 1
    ;;
setup-secureboot)
    if [ -z "${SB_KEY:-}" ]; then
        echo "WARNING: No secureboot key configured, skipping signing."
        exit
    fi

    # Install the surface secureboot certificate
    echo "${SB_KEY}" | base64 -d > pkg/arch/kernel/MOK.key
    cp pkg/keys/surface.crt pkg/arch/kernel/MOK.crt
    ;;
build-packages)
    pushd pkg/arch/kernel || exit 1

    # Fix permissions (can't makepkg as root)
    chown -R nobody .

    # Package compression settings (Matches latest Arch)
    export PKGEXT='.pkg.tar.zst'
    export COMPRESSZST=(zstd -c -T0 --ultra -20 -)
#    export MAKEFLAGS="-j2"

    # Build
    runuser -u nobody -- makepkg -sf --skippgpcheck --noconfirm

    # Prepare release
    mkdir release
    find . -name '*.pkg.tar.zst' -type f -print0 | xargs -0 -I '{}' mv {} release

    popd || exit 1
    ;;
sign-packages)
    if [ -z "${GPG_KEY:-}" ] || [ -z "${GPG_KEY_ID:-}" ]; then
        echo "WARNING: No GPG key configured, skipping signing."
        exit
    fi

    pushd pkg/arch/kernel/release || exit 1

    # import GPG key
    echo "${GPG_KEY}" | base64 -d | gpg --import --no-tty --batch --yes

    # sign packages
    find . -name '*.pkg.tar.zst' -type f -print0 | xargs -0 -I '{}' \
        gpg --detach-sign --batch --no-tty -u "${GPG_KEY_ID}" {}

    popd || exit 1
    ;;
esac
