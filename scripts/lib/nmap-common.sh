#!/usr/bin/env bash
set -euo pipefail

nmap_download_source() {
  local build_root="$1"
  local version="${NMAP_VERSION:-7.99}"
  local source_url="${NMAP_SOURCE_URL:-https://nmap.org/dist/nmap-${version}.tar.bz2}"

  download_and_extract "${source_url}" "${build_root}"
  find_single_directory "${build_root}"
}

nmap_prepare_windows_source() {
  local src_dir="$1"
  local nbase_dir="${src_dir}/nbase"

  perl -0pi -e 's/typedef unsigned __int8 uint8_t;\ntypedef unsigned __int16 uint16_t;\ntypedef unsigned __int32 uint32_t;\ntypedef unsigned __int64 uint64_t;\ntypedef signed __int8 int8_t;\ntypedef signed __int16 int16_t;\ntypedef signed __int32 int32_t;\ntypedef signed __int64 int64_t;/#ifdef __GNUC__\n#include <stdint.h>\n#else\ntypedef unsigned __int8 uint8_t;\ntypedef unsigned __int16 uint16_t;\ntypedef unsigned __int32 uint32_t;\ntypedef unsigned __int64 uint64_t;\ntypedef signed __int8 int8_t;\ntypedef signed __int16 int16_t;\ntypedef signed __int32 int32_t;\ntypedef signed __int64 int64_t;\n#endif/s' "${nbase_dir}/nbase_winconfig.h"
  sed -i 's/char\* WSAAPI gai_strerrorA (int errcode)/char *gai_strerrorA(int errcode)/' "${nbase_dir}/getaddrinfo.c"
  perl -0pi -e 's/#include "nbase_winconfig.h"\n/#include "nbase_winconfig.h"\n#include <errno.h>\n/s' "${nbase_dir}/nbase_winunix.h"
  sed -i '/#include <windows.h>/d' "${nbase_dir}/nbase_winunix.h"
  sed -i '/#include <ws2tcpip.h> \/\* IPv6 stuff \*\//a #include <windows.h>' "${nbase_dir}/nbase_winunix.h"

  find "${src_dir}" -type f \( -name '*.c' -o -name '*.cc' -o -name '*.h' \) -exec sed -i \
    -e 's/<Winsock2.h>/<winsock2.h>/g' \
    -e 's/<WinSock2.h>/<winsock2.h>/g' \
    -e 's/<Ws2tcpip.h>/<ws2tcpip.h>/g' \
    -e 's/<Wspiapi.h>/<wspiapi.h>/g' \
    -e 's/<IPHLPAPI.H>/<iphlpapi.h>/g' \
    -e 's/<WINCRYPT.H>/<wincrypt.h>/g' \
    -e 's/<WinDef.h>/<windef.h>/g' \
    -e 's/<WinBase.h>/<winbase.h>/g' \
    -e 's/<WinNT.h>/<winnt.h>/g' \
    -e 's/<WinError.h>/<winerror.h>/g' \
    -e 's/<WinIoCtl.h>/<winioctl.h>/g' \
    -e 's/<MSWSock.h>/<mswsock.h>/g' \
    -e 's/<Mstcpip.h>/<mstcpip.h>/g' \
    -e 's/"Winsock2.h"/"winsock2.h"/g' \
    -e 's/"WinSock2.h"/"winsock2.h"/g' \
    -e 's/"Ws2tcpip.h"/"ws2tcpip.h"/g' \
    -e 's/"Wspiapi.h"/"wspiapi.h"/g' \
    -e 's/"WinDef.h"/"windef.h"/g' \
    -e 's/"WinBase.h"/"winbase.h"/g' \
    -e 's/"WinNT.h"/"winnt.h"/g' \
    -e 's/"WinError.h"/"winerror.h"/g' \
    -e 's/"WinIoCtl.h"/"winioctl.h"/g' \
    -e 's/"MSWSock.h"/"mswsock.h"/g' \
    -e 's/"Mstcpip.h"/"mstcpip.h"/g' \
    {} +

  perl -0pi -e 's/#endif \/\* NSOCK_WINCONFIG_H \*\//\n#undef HAVE_OPENSSL\n#undef HAVE_POLL\n#undef HAVE_IOCP\n#endif \/\* NSOCK_WINCONFIG_H \*\//s' "${src_dir}/nsock/include/nsock_winconfig.h"
}

nmap_disable_nsock_pcap() {
  local src_dir="$1"

  perl -0pi -e 's/#endif \/\* NSOCK_WINCONFIG_H \*\//\n#undef HAVE_PCAP\n#define DISABLE_NSOCK_PCAP 1\n#endif \/\* NSOCK_WINCONFIG_H \*\//s' "${src_dir}/nsock/include/nsock_winconfig.h"
}

nmap_install_runtime_data() {
  local prefix_dir="$1"

  mkdir -p "${TSB_OUTPUT_DIR}/share/nmap"
  for data_file in \
    nmap.dtd \
    nmap-mac-prefixes \
    nmap-os-db \
    nmap-protocols \
    nmap-rpc \
    nmap-service-probes \
    nmap-services \
    nmap.xsl
  do
    if [[ -f "${prefix_dir}/share/nmap/${data_file}" ]]; then
      install -m 0644 "${prefix_dir}/share/nmap/${data_file}" "${TSB_OUTPUT_DIR}/share/nmap/${data_file}"
    fi
  done
}