#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

version="${TOYBOX_VERSION:-0.8.13}"
source_url="${TOYBOX_SOURCE_URL:-https://landley.net/toybox/downloads/toybox-${version}.tar.gz}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

download_and_extract "${source_url}" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"
target_cc="$(cc_executable)"
extra_ldflags="${LDFLAGS:-}"

cd "${src_dir}"
make distclean >/dev/null 2>&1 || true

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
	make CROSS_COMPILE= CC="${target_cc}" HOSTCC=gcc android_defconfig >/dev/null
	sed -i 's/^CONFIG_TOYBOX_SELINUX=y/# CONFIG_TOYBOX_SELINUX is not set/' .config
	sed -i 's/^CONFIG_TOYBOX_LIBCRYPTO=y/# CONFIG_TOYBOX_LIBCRYPTO is not set/' .config
	sed -i 's/^CONFIG_ICONV=y/# CONFIG_ICONV is not set/' .config
else
	make CROSS_COMPILE= CC="${target_cc}" HOSTCC=gcc defconfig >/dev/null
fi

if [[ "${TSB_TARGET_LIBC}" == "uclibc" ]]; then
	sed -i 's/^CONFIG_BLKDISCARD=y/# CONFIG_BLKDISCARD is not set/' .config
	sed -i 's/^CONFIG_CHATTR=y/# CONFIG_CHATTR is not set/' .config
	sed -i 's/^CONFIG_GPIODETECT=y/# CONFIG_GPIODETECT is not set/' .config
	sed -i 's/^CONFIG_GPIOFIND=y/# CONFIG_GPIOFIND is not set/' .config
	sed -i 's/^CONFIG_GPIOGET=y/# CONFIG_GPIOGET is not set/' .config
	sed -i 's/^CONFIG_GPIOINFO=y/# CONFIG_GPIOINFO is not set/' .config
	sed -i 's/^CONFIG_GPIOSET=y/# CONFIG_GPIOSET is not set/' .config
	sed -i 's/^CONFIG_GETCONF=y/# CONFIG_GETCONF is not set/' .config
	sed -i 's/^CONFIG_I2CDETECT=y/# CONFIG_I2CDETECT is not set/' .config
	sed -i 's/^CONFIG_I2CDUMP=y/# CONFIG_I2CDUMP is not set/' .config
	sed -i 's/^CONFIG_I2CGET=y/# CONFIG_I2CGET is not set/' .config
	sed -i 's/^CONFIG_I2CSET=y/# CONFIG_I2CSET is not set/' .config
	sed -i 's/^CONFIG_I2CTRANSFER=y/# CONFIG_I2CTRANSFER is not set/' .config
	sed -i 's/^CONFIG_ICONV=y/# CONFIG_ICONV is not set/' .config
	sed -i 's/^CONFIG_INSMOD=y/# CONFIG_INSMOD is not set/' .config
	sed -i 's/^CONFIG_LSATTR=y/# CONFIG_LSATTR is not set/' .config
	sed -i 's/^CONFIG_LOSETUP=y/# CONFIG_LOSETUP is not set/' .config
	sed -i 's/^CONFIG_NSENTER=y/# CONFIG_NSENTER is not set/' .config
	sed -i 's/^CONFIG_UNSHARE=y/# CONFIG_UNSHARE is not set/' .config
	sed -i 's/^CONFIG_UCLAMPSET=y/# CONFIG_UCLAMPSET is not set/' .config
	sed -i 's/^CONFIG_ULIMIT=y/# CONFIG_ULIMIT is not set/' .config
fi

if [[ "${TSB_TARGET_ARCH}" == "ppc" ]]; then
	sed -i 's/^CONFIG_LOGIN=y/# CONFIG_LOGIN is not set/' .config
	sed -i 's/^CONFIG_MKPASSWD=y/# CONFIG_MKPASSWD is not set/' .config
	sed -i 's/^CONFIG_PASSWD=y/# CONFIG_PASSWD is not set/' .config
	sed -i 's/^CONFIG_SU=y/# CONFIG_SU is not set/' .config
fi

sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
set +o pipefail
yes '' | make CROSS_COMPILE= CC="${target_cc}" HOSTCC=gcc oldconfig >/dev/null
set -o pipefail

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
	perl -0pi -e 's@    if \(strcmp\("UTF-8", nl_langinfo\(CODESET\)\)\)@#if !defined(__ANDROID__)\n    if (strcmp("UTF-8", nl_langinfo(CODESET)))@' main.c
	perl -0pi -e 's@        newlocale\(LC_CTYPE_MASK, "en_US\.UTF-8", 0\)\);@        newlocale(LC_CTYPE_MASK, "en_US.UTF-8", 0));\n#endif@' main.c

	perl -0pi -e 's@#if __has_include\(<sys/random\.h>\)@#if __has_include(<sys/random.h>) \&\& !defined(__ANDROID__)@' lib/portability.c
fi

if [[ "${TSB_TARGET_LIBC}" == "uclibc" ]]; then
	perl -0pi -e 's@#if __has_include\(<sys/random\.h>\) && \(!defined\(__ANDROID__\) \|\| __ANDROID_API__>28\)@#if __has_include(<sys/random.h>) && (!defined(__ANDROID__) || __ANDROID_API__>28) && !defined(__UCLIBC__)@' lib/portability.c
	perl -0pi -e 's@#if defined\(__linux__\)\n  // 2 is RENAME_EXCHANGE\n  return syscall\(SYS_renameat2, AT_FDCWD, file1, AT_FDCWD, file2, 2\);@#if defined(__linux__) && defined(SYS_renameat2)\n  // 2 is RENAME_EXCHANGE\n  return syscall(SYS_renameat2, AT_FDCWD, file1, AT_FDCWD, file2, 2);@' lib/portability.c
	perl -0pi -e 's@    if \(strcmp\("UTF-8", nl_langinfo\(CODESET\)\)\)@#if !defined(__UCLIBC__)\n    if (strcmp("UTF-8", nl_langinfo(CODESET)))@' main.c
	perl -0pi -e 's@        newlocale\(LC_CTYPE_MASK, "en_US\.UTF-8", 0\)\);@        newlocale(LC_CTYPE_MASK, "en_US.UTF-8", 0));\n#endif@' main.c
fi

make -j"$(jobs)" CROSS_COMPILE= CC="${target_cc}" HOSTCC=gcc LDFLAGS="${extra_ldflags}"

install_artifact toybox "toybox$(binary_suffix)"
