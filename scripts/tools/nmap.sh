#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh
source /opt/tsb/lib/nmap-common.sh

build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

src_dir="$(nmap_download_source "${build_root}")"
build_dir="${src_dir}"
prefix_dir="${build_root}/prefix"

export CFLAGS="${CFLAGS:-} -Os"
export CXXFLAGS="${CXXFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

configure_project "${src_dir}" "${build_dir}" "${prefix_dir}" \
  --disable-nls \
  --with-libdnet=included \
  --with-liblinear=included \
  --with-libpcap=included \
  --with-libpcre=included \
  --with-libz=included \
  --without-liblua \
  --without-libssh2 \
  --without-openssl \
  --without-ndiff \
  --without-nping \
  --without-zenmap

perl -0pi -e 's/cd \$\(ZLIBDIR\) && \$\(MAKE\);/cd \$\(ZLIBDIR\) \&\& \$\(MAKE\) static;/' "${build_dir}/Makefile"

make -C "${build_dir}" -j"$(jobs)"
make -C "${build_dir}" install

install_artifact "${prefix_dir}/bin/nmap$(binary_suffix)" "nmap$(binary_suffix)"
install_artifact "${prefix_dir}/bin/ncat$(binary_suffix)" "ncat$(binary_suffix)"

nmap_install_runtime_data "${prefix_dir}"