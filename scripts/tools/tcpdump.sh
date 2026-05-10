#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

libpcap_version="${LIBPCAP_VERSION:-1.10.6}"
libpcap_source_url="${LIBPCAP_SOURCE_URL:-https://www.tcpdump.org/release/libpcap-${libpcap_version}.tar.gz}"
tcpdump_version="${TCPDUMP_VERSION:-4.99.6}"
tcpdump_source_url="${TCPDUMP_SOURCE_URL:-https://www.tcpdump.org/release/tcpdump-${tcpdump_version}.tar.gz}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

prefix_dir="${build_root}/prefix"
mkdir -p "${prefix_dir}"

export CFLAGS="${CFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

download_and_extract "${libpcap_source_url}" "${build_root}/libpcap-src"
libpcap_src_dir="$(find_single_directory "${build_root}/libpcap-src")"
configure_project "${libpcap_src_dir}" "${build_root}/libpcap-build" "${prefix_dir}" \
  --disable-shared \
  --enable-static \
  --without-dag \
  --without-dbus \
  --without-libnl \
  --without-bluetooth \
  --without-netmap \
  --without-rdma \
  --without-septel \
  --without-snf \
  --without-turbocap
make -C "${build_root}/libpcap-build" -j"$(jobs)"
make -C "${build_root}/libpcap-build" install

download_and_extract "${tcpdump_source_url}" "${build_root}/tcpdump-src"
tcpdump_src_dir="$(find_single_directory "${build_root}/tcpdump-src")"

export CPPFLAGS="${CPPFLAGS:-} -I${prefix_dir}/include"
export LDFLAGS="${LDFLAGS:-} -L${prefix_dir}/lib -static"

configure_project "${tcpdump_src_dir}" "${build_root}/tcpdump-build" "${prefix_dir}" \
  --disable-shared \
  --enable-static \
  --without-crypto
make -C "${build_root}/tcpdump-build" -j"$(jobs)"
install_artifact "${build_root}/tcpdump-build/tcpdump$(binary_suffix)" "tcpdump$(binary_suffix)"
