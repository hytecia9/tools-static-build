#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

version="${STRACE_VERSION:-7.0}"
source_url="${STRACE_SOURCE_URL:-https://github.com/strace/strace/releases/download/v${version}/strace-${version}.tar.xz}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

download_and_extract "${source_url}" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"
build_dir="${build_root}/build"
prefix_dir="${build_root}/prefix"

fallback_time_types_header="${src_dir}/bundled/linux/include/uapi/linux/time_types.h"
if [[ ! -f "${fallback_time_types_header}" ]]; then
  mkdir -p "$(dirname "${fallback_time_types_header}")"
  cat > "${fallback_time_types_header}" <<'EOF'
#ifndef _UAPI_LINUX_TIME_TYPES_H
#define _UAPI_LINUX_TIME_TYPES_H

#include <stdint.h>

struct __kernel_timespec {
  int64_t tv_sec;
  int64_t tv_nsec;
};

struct __kernel_sock_timeval {
  int64_t tv_sec;
  int64_t tv_usec;
};

#endif
EOF
fi

export CFLAGS="${CFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

if [[ "${TSB_TARGET_OS}" == "linux" && "${TSB_TARGET_LIBC:-}" == "glibc" && "${TSB_TARGET_ARCH}" == "mipsel" ]]; then
  export LIBS="${LIBS:-} -pthread"
fi

configure_project "${src_dir}" "${build_dir}" "${prefix_dir}" \
  --disable-gcc-Werror \
  --disable-shared \
  --enable-mpers=no \
  --with-libdw=no \
  --with-libunwind=no
make -C "${build_dir}" -j"$(jobs)"
install_artifact "${build_dir}/src/strace$(binary_suffix)" "strace$(binary_suffix)"
