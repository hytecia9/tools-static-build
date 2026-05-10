#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

version="${SOCAT_VERSION:-1.8.0.3}"
source_url="${SOCAT_SOURCE_URL:-http://www.dest-unreach.org/socat/download/socat-${version}.tar.gz}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

download_and_extract "${source_url}" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"
build_dir="${build_root}/build"
prefix_dir="${build_root}/prefix"

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
  perl -0pi -e 's@extern int xio_res_init\(struct single \*sfd, struct __res_state \*save_res\);@extern int xio_res_init(struct single *sfd, void *save_res);@g; s@extern int xio_res_restore\(struct __res_state \*save_res\);@extern int xio_res_restore(void *save_res);@g' "${src_dir}/xio-ip.h"
  perl -0pi -e 's@\bstruct __res_state save_res;@char save_res[1];@g' "${src_dir}/xioopen.c"
  perl -0pi -e 's@int xio_res_init\(@#if defined(__ANDROID__)\nint xio_res_init(struct single *sfd, void *save_res)\n{\n    (void)sfd;\n    (void)save_res;\n    return 0;\n}\n\nint xio_res_restore(void *save_res)\n{\n    (void)save_res;\n    return 0;\n}\n#else\n\nint xio_res_init\(@s' "${src_dir}/xio-ip.c"
  printf '\n#endif\n' >> "${src_dir}/xio-ip.c"
  perl -0pi -e 's@ctermid\(s\)@"/dev/tty"@g' "${src_dir}/procan.c"
fi

export CFLAGS="${CFLAGS:-} -Os"
export CPPFLAGS="${CPPFLAGS:-} -D_GNU_SOURCE"
export LDFLAGS="${LDFLAGS:-} -static"

if [[ "${TSB_TARGET_LIBC:-}" == "uclibc" ]]; then
  export LDFLAGS="${LDFLAGS} -Wl,--allow-multiple-definition"
fi

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
  export CPPFLAGS="${CPPFLAGS} -DRES_DEBUG=0 -DRES_USEVC=0 -DRES_IGNTC=0 -DRES_RECURSE=0 -DRES_DEFNAMES=0 -DRES_STAYOPEN=0 -DRES_DNSRCH=0 -DRES_INIT=0"
fi

configure_project "${src_dir}" "${build_dir}" "${prefix_dir}" \
  --disable-openssl \
  --disable-readline \
  --disable-libwrap

if [[ "${TSB_TARGET_LIBC:-}" == "uclibc" || "${TSB_TARGET_OS}" == "android" ]]; then
  config_header="${build_dir}/config.h"
  # Socat's configure checks miss these libc functions on some static targets.
  for feature_macro in \
    HAVE_MEMRCHR \
    HAVE_DECL_MEMRCHR \
    HAVE_PROTOTYPE_MEMRCHR \
    HAVE_PROTOTYPE_LIB_memrchr \
    HAVE_STRNDUP \
    HAVE_DECL_STRNDUP \
    HAVE_PROTOTYPE_STRNDUP \
    HAVE_PROTOTYPE_LIB_strndup
  do
    if grep -q "^#undef ${feature_macro}$" "${config_header}"; then
      sed -i "s/^#undef ${feature_macro}$/#define ${feature_macro} 1/" "${config_header}"
    elif ! grep -q "^#define ${feature_macro} " "${config_header}"; then
      printf '#define %s 1\n' "${feature_macro}" >> "${config_header}"
    fi
  done
fi

make -C "${build_dir}" -j"$(jobs)"
install_artifact "${build_dir}/socat$(binary_suffix)" "socat$(binary_suffix)"
