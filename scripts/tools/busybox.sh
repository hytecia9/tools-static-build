#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

version="${BUSYBOX_VERSION:-1.37.0}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

download_and_extract "https://busybox.net/downloads/busybox-${version}.tar.bz2" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"

set_kconfig_enabled() {
	local key="$1"

	if grep -q "^${key}=" .config; then
		sed -i "s/^${key}=.*/${key}=y/" .config
	elif grep -q "^# ${key} is not set" .config; then
		sed -i "s/^# ${key} is not set/${key}=y/" .config
	else
		printf '%s=y\n' "${key}" >> .config
	fi
}

set_kconfig_disabled() {
	local key="$1"

	if grep -q "^${key}=" .config; then
		sed -i "s/^${key}=.*/# ${key} is not set/" .config
	elif ! grep -q "^# ${key} is not set" .config; then
		printf '# %s is not set\n' "${key}" >> .config
	fi
}

set_kconfig_string() {
	local key="$1"
	local value="$2"

	if grep -q "^${key}=" .config; then
		sed -i "s|^${key}=.*|${key}=\"${value}\"|" .config
	elif grep -q "^# ${key} is not set" .config; then
		sed -i "s|^# ${key} is not set|${key}=\"${value}\"|" .config
	else
		printf '%s="%s"\n' "${key}" "${value}" >> .config
	fi
}

cd "${src_dir}"
make distclean >/dev/null 2>&1 || true

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
	make android2_defconfig >/dev/null
else
	make defconfig >/dev/null
fi

set_kconfig_enabled CONFIG_STATIC
set_kconfig_disabled CONFIG_PIE
set_kconfig_disabled CONFIG_SHA1_HWACCEL
set_kconfig_disabled CONFIG_SHA256_HWACCEL
set_kconfig_disabled CONFIG_FEATURE_IP_LINK_CAN

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
	set_kconfig_string CONFIG_CROSS_COMPILER_PREFIX ""
	set_kconfig_enabled CONFIG_USE_BB_CRYPT
	set_kconfig_disabled CONFIG_ADJTIMEX
	set_kconfig_disabled CONFIG_CONSPY
	set_kconfig_disabled CONFIG_SEEDRNG
	set_kconfig_disabled CONFIG_SWAPOFF
	set_kconfig_disabled CONFIG_SWAPON
	set_kconfig_disabled CONFIG_TC
	set_kconfig_disabled CONFIG_FEATURE_UTMP
	set_kconfig_disabled CONFIG_FEATURE_WTMP
	set_kconfig_disabled CONFIG_FEATURE_SYNC_FANCY
	set_kconfig_disabled CONFIG_FEATURE_SU_CHECKS_SHELLS
	set_kconfig_disabled CONFIG_HOSTID
	set_kconfig_disabled CONFIG_LOGNAME
	set_kconfig_disabled CONFIG_LOADFONT
	set_kconfig_disabled CONFIG_SETFONT
	perl -0pi -e 's@# undef HAVE_MEMPCPY\n# undef HAVE_STRCHRNUL\n# undef HAVE_STRVERSCMP@# undef HAVE_MEMPCPY\n# if __ANDROID_API__ < 24\n#  undef HAVE_STRCHRNUL\n# endif\n# undef HAVE_STRVERSCMP@' include/platform.h
	perl -0pi -e 's@#ifndef HAVE_STRCHRNUL@#if !defined(HAVE_STRCHRNUL) && !(defined(__ANDROID__) && __ANDROID_API__ >= 24)@' libbb/platform.c
fi

if [[ "${TSB_TARGET_LIBC}" == "uclibc" ]]; then
	set_kconfig_disabled CONFIG_NSENTER
	set_kconfig_disabled CONFIG_FEATURE_SYNC_FANCY
fi

set +o pipefail
yes '' | make oldconfig >/dev/null
set -o pipefail

strip_cmd="${STRIP:-}"

if [[ -z "${strip_cmd}" && "${TSB_TARGET_OS}" != "android" ]]; then
	candidate_strip="$(cc_triplet)-strip"
	if command -v "${candidate_strip}" >/dev/null 2>&1; then
		strip_cmd="${candidate_strip}"
	fi
fi

strip_cmd="${strip_cmd:-strip}"

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
	make -j"$(jobs)" CC="${CC}" HOSTCC=gcc busybox_unstripped
	cp busybox_unstripped busybox
	chmod +x busybox
else
	make -j"$(jobs)" CC="${CC}" HOSTCC=gcc STRIP="${strip_cmd}"
fi

install_artifact busybox "busybox$(binary_suffix)"

