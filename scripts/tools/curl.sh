#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

version="${CURL_VERSION:-8.20.0}"
source_url="${CURL_SOURCE_URL:-https://curl.se/download/curl-${version}.tar.xz}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

download_and_extract "${source_url}" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"
build_dir="${build_root}/build"
prefix_dir="${build_root}/prefix"

export CFLAGS="${CFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

configure_project "${src_dir}" "${build_dir}" "${prefix_dir}" \
  --disable-shared \
  --enable-static \
  --disable-ldap \
  --disable-ldaps \
  --disable-manual \
  --disable-dict \
  --disable-file \
  --disable-ftp \
  --disable-gopher \
  --disable-imap \
  --disable-ipfs \
  --disable-pop3 \
  --disable-rtsp \
  --disable-smb \
  --disable-smtp \
  --disable-telnet \
  --disable-tftp \
  --disable-libcurl-option \
  --without-brotli \
  --without-libidn2 \
  --without-libpsl \
  --without-nghttp2 \
  --without-nghttp3 \
  --without-ngtcp2 \
  --without-ssl \
  --without-openssl \
  --without-zlib \
  --without-zstd

make -C "${build_dir}" -j"$(jobs)"
install_artifact "${build_dir}/src/curl$(binary_suffix)" "curl$(binary_suffix)"
