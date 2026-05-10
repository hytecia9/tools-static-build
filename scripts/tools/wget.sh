#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

version="${WGET_VERSION:-1.25.0}"
source_url="${WGET_SOURCE_URL:-https://ftp.gnu.org/gnu/wget/wget-${version}.tar.gz}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

download_and_extract "${source_url}" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"
build_dir="${build_root}/build"
prefix_dir="${build_root}/prefix"

if [[ "${TSB_TARGET_LIBC:-}" == "uclibc" ]]; then
  perl -0pi -e 's/#include <config.h>\n\n#include <sys\/random.h>/#include <config.h>\n\n#include <stddef.h>\n#include <sys\/random.h>/g' "${src_dir}/lib/getrandom.c"
  perl -0pi -e 's/#include <stdint.h>\n#include <sys\/random.h>/#include <stdint.h>\n#include <stddef.h>\n#include <sys\/random.h>/g' "${src_dir}/lib/tempname.c"
fi

export CFLAGS="${CFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

if [[ "${TSB_TARGET_OS}" == "windows" ]]; then
  export LIBS="${LIBS:-} -lbcrypt"
else
  export gl_cv_func_working_mktime=yes
fi

configure_project "${src_dir}" "${build_dir}" "${prefix_dir}" \
  --disable-shared \
  --enable-static \
  --disable-nls \
  --disable-rpath \
  --without-libpsl \
  --without-ssl \
  --without-zlib
make -C "${build_dir}" -j"$(jobs)"
install_artifact "${build_dir}/src/wget$(binary_suffix)" "wget$(binary_suffix)"
