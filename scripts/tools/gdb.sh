#!/usr/bin/env bash
set -euo pipefail

source /opt/tsb/lib/common.sh

version="${GDB_VERSION:-17.1}"
source_url="${GDB_SOURCE_URL:-https://ftp.gnu.org/gnu/gdb/gdb-${version}.tar.xz}"
gmp_version="${GMP_VERSION:-6.3.0}"
gmp_source_url="${GMP_SOURCE_URL:-https://ftp.gnu.org/gnu/gmp/gmp-${gmp_version}.tar.xz}"
mpfr_version="${MPFR_VERSION:-4.2.1}"
mpfr_source_url="${MPFR_SOURCE_URL:-https://ftp.gnu.org/gnu/mpfr/mpfr-${mpfr_version}.tar.xz}"
iconv_version="${ICONV_VERSION:-1.17}"
iconv_source_url="${ICONV_SOURCE_URL:-https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${iconv_version}.tar.gz}"
build_root="$(mktemp -d)"
trap 'rm -rf "${build_root}"' EXIT

dep_prefix_dir="${build_root}/deps"
mkdir -p "${dep_prefix_dir}"

download_and_extract "${gmp_source_url}" "${build_root}/gmp-src"
gmp_src_dir="$(find_single_directory "${build_root}/gmp-src")"

export CFLAGS="${CFLAGS:-} -Os"
export CXXFLAGS="${CXXFLAGS:-} -Os"
export LDFLAGS="${LDFLAGS:-} -static"

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
  export ac_cv_func_nl_langinfo=no
  export ac_cv_header_langinfo_h=no
  export ac_cv_func_getrandom=yes
  export ac_cv_type_Elf32_auxv_t=yes
  export ac_cv_type_Elf64_auxv_t=yes
  export ac_cv_func_getpwent=no
  export ac_cv_func_setpwent=no
  export ac_cv_func_endpwent=no
  export ac_cv_func_posix_spawn=no
  export ac_cv_func_posix_spawnp=no
  export ac_cv_func_posix_spawnattr_init=no
  export ac_cv_func_posix_spawnattr_setflags=no
  export ac_cv_func_posix_spawnattr_destroy=no
  export ac_cv_header_sys_random_h=yes
  export ac_cv_func_posix_spawn_file_actions_init=no
  export ac_cv_func_posix_spawn_file_actions_destroy=no
  export ac_cv_func_posix_spawn_file_actions_addclose=no
  export ac_cv_func_posix_spawn_file_actions_adddup2=no
fi

if [[ "${TSB_TARGET_OS}" == "windows" ]]; then
  compat_src="${build_root}/windows-compat.cc"
  compat_obj="${build_root}/windows-compat.o"
  compat_lib="${build_root}/libwindows-compat.a"

  cat > "${compat_src}" <<'EOF'
#include <windows.h>

#include <cstdlib>
#include <cstring>

extern "C" int setenv(const char *name, const char *value, int overwrite)
{
  if (name == nullptr || *name == '\0' || std::strchr(name, '=') != nullptr)
    return -1;

  if (!overwrite && std::getenv(name) != nullptr)
    return 0;

  return _putenv_s(name, value != nullptr ? value : "") == 0 ? 0 : -1;
}

extern "C" int unsetenv(const char *name)
{
  if (name == nullptr || *name == '\0' || std::strchr(name, '=') != nullptr)
    return -1;

  return _putenv_s(name, "") == 0 ? 0 : -1;
}
EOF

  if [[ "${TSB_TARGET_ARCH}" == "aarch64" ]]; then
    cat >> "${compat_src}" <<'EOF'

static char *dup_string(const char *value)
{
  if (value == nullptr)
    return nullptr;

  size_t length = std::strlen(value) + 1;
  char *copy = static_cast<char *>(std::malloc(length));

  if (copy != nullptr)
    std::memcpy(copy, value, length);

  return copy;
}

char *windows_get_absolute_argv0(const char *argv0)
{
  if (argv0 == nullptr)
    return nullptr;

  DWORD required = GetFullPathNameA(argv0, 0, nullptr, nullptr);

  if (required == 0)
    return dup_string(argv0);

  char *buffer = static_cast<char *>(std::malloc(required));

  if (buffer == nullptr)
    return dup_string(argv0);

  DWORD written = GetFullPathNameA(argv0, required, buffer, nullptr);

  if (written == 0 || written >= required)
    {
      std::free(buffer);
      return dup_string(argv0);
    }

  return buffer;
}
EOF
  fi

  "${CXX:-g++}" -c -Os -o "${compat_obj}" "${compat_src}"
  read -r -a ar_cmd <<< "${AR:-ar}"
  "${ar_cmd[@]}" rcs "${compat_lib}" "${compat_obj}"

  if [[ -n "${RANLIB:-}" ]]; then
    read -r -a ranlib_cmd <<< "${RANLIB}"
    "${ranlib_cmd[@]}" "${compat_lib}"
  fi

  gdb_extra_libs="${compat_lib}"
  export ac_cv_func_setenv=yes
  export ac_cv_func_unsetenv=yes
fi

gmp_configure_args=(
  --disable-shared
  --enable-cxx
  --enable-static
)

if [[ "${TSB_TARGET_ARCH}" == "armv5" || "${TSB_TARGET_ARCH}" == "armv7" ]]; then
  gmp_configure_args+=(--disable-assembly)
fi

if [[ "${TSB_TARGET_ARCH}" == "x86" && "${TSB_TARGET_OS}" != "windows" ]]; then
  ABI=32 configure_project "${gmp_src_dir}" "${build_root}/gmp-build" "${dep_prefix_dir}" "${gmp_configure_args[@]}"
else
  configure_project "${gmp_src_dir}" "${build_root}/gmp-build" "${dep_prefix_dir}" "${gmp_configure_args[@]}"
fi
make -C "${build_root}/gmp-build" -j"$(jobs)"
make -C "${build_root}/gmp-build" install

download_and_extract "${mpfr_source_url}" "${build_root}/mpfr-src"
mpfr_src_dir="$(find_single_directory "${build_root}/mpfr-src")"
export CPPFLAGS="${CPPFLAGS:-} -I${dep_prefix_dir}/include"
export LDFLAGS="${LDFLAGS:-} -L${dep_prefix_dir}/lib -static"
configure_project "${mpfr_src_dir}" "${build_root}/mpfr-build" "${dep_prefix_dir}" \
  --disable-shared \
  --enable-static \
  --with-gmp="${dep_prefix_dir}"
make -C "${build_root}/mpfr-build" -j"$(jobs)"
make -C "${build_root}/mpfr-build" install

if [[ "${TSB_TARGET_OS}" == "android" || "${TSB_TARGET_LIBC}" == "uclibc" ]]; then
  download_and_extract "${iconv_source_url}" "${build_root}/iconv-src"
  iconv_src_dir="$(find_single_directory "${build_root}/iconv-src")"

  configure_project "${iconv_src_dir}" "${build_root}/iconv-build" "${dep_prefix_dir}" \
    --disable-shared \
    --enable-static
  make -C "${build_root}/iconv-build" -j"$(jobs)"
  make -C "${build_root}/iconv-build" install

  gdb_extra_libs="-liconv ${gdb_extra_libs:-}"
fi

download_and_extract "${source_url}" "${build_root}"
src_dir="$(find_single_directory "${build_root}")"
build_dir="${build_root}/build"
prefix_dir="${build_root}/prefix"
native_triplet="$(cc_triplet)"

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
  perl -0pi -e 's@#include <time\.h>\n@#include <time.h>\n#if defined(__ANDROID__) && defined(__ANDROID_API__) && __ANDROID_API__ < 28\nextern ssize_t getrandom (void *, size_t, unsigned int);\n#endif\n@' "${src_dir}/gnulib/import/tempname.c"
  perl -0pi -e 's@return gdb::handle_eintr \(-1, ::open, pathname, flags\);@return gdb::handle_eintr (-1, [] (const char *open_path, int open_flags) { return ::open (open_path, open_flags); }, pathname, flags);@' "${src_dir}/gdbsupport/eintr.h"
  perl -0pi -e 's@#include <signal\.h>\n@#include <signal.h>\n#if defined(__ANDROID__) && !defined(PAGE_SIZE)\n#define PAGE_SIZE ((size_t) getpagesize ())\n#endif\n@' "${src_dir}/gdb/nat/linux-btrace.c"
  perl -0pi -e 's@#if HAVE_QSORT_R_ARG_LAST@#if HAVE_QSORT_R_ARG_LAST && !defined(__ANDROID__)@' "${src_dir}/libctf/ctf-decls.h"
  perl -0pi -e 's@#elif HAVE_QSORT_R_COMPAR_LAST@#elif HAVE_QSORT_R_COMPAR_LAST && !defined(__ANDROID__)@' "${src_dir}/libctf/ctf-decls.h"
  perl -0pi -e 's@#ifndef HAVE_ELF32_AUXV_T@#if !defined(HAVE_ELF32_AUXV_T) && !defined(__ANDROID__)@' "${src_dir}/gdbserver/linux-low.cc"
  perl -0pi -e 's@#ifndef HAVE_ELF64_AUXV_T@#if !defined(HAVE_ELF64_AUXV_T) && !defined(__ANDROID__)@' "${src_dir}/gdbserver/linux-low.cc"
  perl -0pi -e 's@const char \*cset = nl_langinfo \(CODESET\);@const char *cset = "UTF-8";@' "${src_dir}/gdbserver/linux-low.cc"
fi

if [[ "${TSB_TARGET_LIBC}" == "musl" ]]; then
  perl -0pi -e 's@tio\.c_ospeed = rate;@tio.__c_ospeed = rate;@; s@tio\.c_ispeed = rate;@tio.__c_ispeed = rate;@' "${src_dir}/gdb/ser-unix.c"
fi

mkdir -p "${build_dir}"
cd "${build_dir}"

configure_args=(
  "--build=$(build_triplet)"
  "--host=${native_triplet}"
  "--target=${native_triplet}"
  "--prefix=${prefix_dir}"
  --disable-binutils
  --disable-gas
  --disable-gold
  --disable-inprocess-agent
  --disable-gprof
  --disable-gprofng
  --disable-ld
  --disable-nls
  --disable-sim
  --disable-source-highlight
  --disable-tui
  --disable-werror
  --with-system-readline=no
  --with-static-standard-libraries
  --without-babeltrace
  --without-debuginfod
  --without-expat
  --without-guile
  --without-intel-pt
  --without-libunwind-ia64
  --without-lzma
  --without-python
  --without-xxhash
  --without-zstd
  "--with-gmp=${dep_prefix_dir}"
  "--with-mpfr=${dep_prefix_dir}"
)

if [[ "${TSB_TARGET_OS}" == "windows" ]]; then
  configure_args+=(--disable-gdbserver)
fi

env \
  CC="${CC}" \
  CXX="${CXX:-}" \
  AR="${AR:-}" \
  LIBS="${gdb_extra_libs:-} ${LIBS:-}" \
  RANLIB="${RANLIB:-}" \
  STRIP="${STRIP:-}" \
  "${src_dir}/configure" "${configure_args[@]}"

make_args=(-j"$(jobs)")

if [[ -n "${gdb_extra_libs:-}" ]]; then
  make_args+=("LIBS=${gdb_extra_libs} ${LIBS:-}")
fi

if [[ "${TSB_TARGET_OS}" == "android" ]]; then
  make "${make_args[@]}" all-gdbserver
elif [[ "${TSB_TARGET_OS}" == "windows" ]]; then
  make "${make_args[@]}" all-gdb
else
  make "${make_args[@]}" all-gdb all-gdbserver
fi

if [[ -f "${build_dir}/gdb/gdb$(binary_suffix)" ]]; then
  install_artifact "${build_dir}/gdb/gdb$(binary_suffix)" "gdb$(binary_suffix)"
fi

if [[ "${TSB_TARGET_OS}" != "windows" && -f "${build_dir}/gdbserver/gdbserver$(binary_suffix)" ]]; then
  install_artifact "${build_dir}/gdbserver/gdbserver$(binary_suffix)" "gdbserver$(binary_suffix)"
fi
