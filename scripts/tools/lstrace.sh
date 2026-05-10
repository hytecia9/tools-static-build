#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

ltrace_version="${LSTRACE_VERSION:-0.7.3}"
ltrace_source_url="${LSTRACE_SOURCE_URL:-https://deb.debian.org/debian/pool/main/l/ltrace/ltrace_${ltrace_version}.orig.tar.bz2}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

export CFLAGS="${CFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

download_and_extract "${ltrace_source_url}" "${build_root}/ltrace-src"
ltrace_src_dir="$(find_single_directory "${build_root}/ltrace-src")"

configure_project "${ltrace_src_dir}" "${build_root}/ltrace-build" "${build_root}/prefix" \
  --disable-shared \
  --enable-static \
  --disable-werror
make -C "${build_root}/ltrace-build" -j"$(jobs)"

ltrace_binary="$(find_built_binary "${build_root}/ltrace-build" "ltrace")"
if [[ -z "${ltrace_binary}" ]]; then
  echo "failed to locate built ltrace binary" >&2
  exit 1
fi

install_artifact "${ltrace_binary}" "ltrace$(binary_suffix)"
