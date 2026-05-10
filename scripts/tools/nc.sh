#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

if [[ "${TSB_TARGET_OS}" == "windows" ]]; then
  echo "nc is only wired for Linux and Android targets" >&2
  exit 1
fi

build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

version="${NETCAT_VERSION:-0.7.1}"
source_url="${NETCAT_SOURCE_URL:-https://master.dl.sourceforge.net/project/netcat/netcat/${version}/netcat-${version}.tar.bz2}"
prefix_dir="${build_root}/prefix"
build_dir="${build_root}/build"

download_and_extract "${source_url}" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"

if [[ -z "${src_dir}" ]]; then
  echo "failed to locate extracted netcat source directory" >&2
  exit 1
fi

for config_script in config.guess config.sub; do
  curl \
    -4 \
    --connect-timeout 30 \
    --retry 5 \
    --retry-all-errors \
    --retry-delay 2 \
    -fsSL \
    "https://raw.githubusercontent.com/chipp/gnu-config/master/${config_script}" \
    -o "${src_dir}/${config_script}"
  chmod +x "${src_dir}/${config_script}"
done

export CFLAGS="${CFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

configure_project "${src_dir}" "${build_dir}" "${prefix_dir}"

make -C "${build_dir}" -j"$(jobs)"

nc_binary="$(find_built_binary "${build_dir}" "netcat")"
if [[ -z "${nc_binary}" ]]; then
  nc_binary="$(find_built_binary "${src_dir}" "netcat")"
fi

if [[ -z "${nc_binary}" ]]; then
  echo "failed to locate built netcat binary" >&2
  exit 1
fi

install_artifact "${nc_binary}" "nc$(binary_suffix)"