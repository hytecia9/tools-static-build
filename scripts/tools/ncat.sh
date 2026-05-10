#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh
source /opt/tsb/lib/nmap-common.sh

if [[ "${TSB_TARGET_OS}" != "windows" ]]; then
  echo "ncat is only wired for Windows targets" >&2
  exit 1
fi

build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}" >/dev/null 2>&1 || true' EXIT

src_dir="$(nmap_download_source "${build_root}")"
prefix_dir="${build_root}/prefix"
nbase_dir="${src_dir}/nbase"
nsock_dir="${src_dir}/nsock/src"
ncat_dir="${src_dir}/ncat"

nmap_prepare_windows_source "${src_dir}"
nmap_disable_nsock_pcap "${src_dir}"

export CFLAGS="${CFLAGS:-} -Os"
export CXXFLAGS="${CXXFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"
export LIBS="${LIBS:-} -liphlpapi -lws2_32"

configure_project "${nbase_dir}" "${nbase_dir}" "${prefix_dir}"
configure_project "${nsock_dir}" "${nsock_dir}" "${prefix_dir}" \
  --without-libpcap \
  --without-openssl
configure_project "${ncat_dir}" "${ncat_dir}" "${prefix_dir}" \
  --without-openssl \
  --without-liblua

perl -0pi -e 's/^OBJS = (.*)$/OBJS = $1 nbase_winunix.o/m' "${nbase_dir}/Makefile"
perl -0pi -e 's/\sgetaddrinfo\.o//g; s/\sinet_ntop\.o//g; s/\sinet_pton\.o//g' "${nbase_dir}/Makefile"

sed -i 's/ -I..\/libpcap//g' "${ncat_dir}/Makefile"
sed -i 's/^PCAP_LIBS =.*/PCAP_LIBS =/' "${ncat_dir}/Makefile"
sed -i 's/ncat_posix\.c/ncat_win.c ncat_exec_win.c/' "${ncat_dir}/Makefile"
sed -i 's/ncat_posix\.o/ncat_win.o ncat_exec_win.o/' "${ncat_dir}/Makefile"
sed -i 's/^#define HAVE_LIBPCAP 1$/\/\* #undef HAVE_LIBPCAP \*\//' "${ncat_dir}/config.h" || true
sed -i 's/^#define HAVE_PCAP_SET_IMMEDIATE_MODE 1$/\/\* #undef HAVE_PCAP_SET_IMMEDIATE_MODE \*\//' "${ncat_dir}/config.h" || true

make -C "${nbase_dir}" -j"$(jobs)"
make -C "${nsock_dir}" -j"$(jobs)"
make -C "${ncat_dir}" -j"$(jobs)"

ncat_binary="${ncat_dir}/ncat$(binary_suffix)"
if [[ ! -f "${ncat_binary}" ]]; then
	ncat_binary="$(find_built_binary "${ncat_dir}" "ncat" || true)"
fi

if [[ -z "${ncat_binary}" || ! -f "${ncat_binary}" ]]; then
  echo "failed to locate built ncat binary" >&2
  exit 1
fi

install_artifact "${ncat_binary}" "ncat$(binary_suffix)"