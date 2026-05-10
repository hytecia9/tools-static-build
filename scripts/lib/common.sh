#!/usr/bin/env bash
set -euo pipefail

jobs() {
  if [[ -n "${TSB_MAKE_JOBS:-}" ]]; then
    printf '%s\n' "${TSB_MAKE_JOBS}"
    return
  fi

  if command -v nproc >/dev/null 2>&1; then
    nproc
  else
    getconf _NPROCESSORS_ONLN
  fi
}

build_triplet() {
  if command -v gcc >/dev/null 2>&1; then
    gcc -dumpmachine
  elif command -v clang >/dev/null 2>&1; then
    clang -dumpmachine
  else
    printf '%s-unknown-linux-gnu\n' "$(uname -m)"
  fi
}

cc_executable() {
  local token

  for token in ${CC}; do
    case "${token}" in
      ccache|sccache|distcc)
        continue
        ;;
      *=*)
        continue
        ;;
      -*)
        continue
        ;;
      *)
        printf '%s\n' "${token}"
        return
        ;;
    esac
  done

  printf '%s\n' "${CC%% *}"
}

cc_triplet() {
  local compiler
  local compiler_name
  local triplet

  compiler="$(cc_executable)"
  compiler_name="$(basename "${compiler}")"

  if [[ "${compiler_name}" =~ ^([A-Za-z0-9._+-]+)-(gcc|g\+\+|cc|c\+\+)(-[0-9.]+)?$ ]]; then
    triplet="${BASH_REMATCH[1]}"
  else
    triplet="$("${compiler}" -dumpmachine)"
  fi

  if [[ "${TSB_TARGET_OS:-}" == "windows" && "${triplet}" == "aarch64-w64-windows-gnu" ]]; then
    printf '%s\n' 'aarch64-w64-mingw32'
    return
  fi

  printf '%s\n' "${triplet}"
}

binary_suffix() {
  if [[ "${TSB_TARGET_OS}" == "windows" ]]; then
    printf '.exe\n'
  else
    printf '\n'
  fi
}

configure_project() {
  local src_dir="$1"
  local build_dir="$2"
  local prefix="$3"

  shift 3

  mkdir -p "${build_dir}"

  (
    cd "${build_dir}"
    env \
      CC="${CC}" \
      CXX="${CXX:-}" \
      AR="${AR:-}" \
      RANLIB="${RANLIB:-}" \
      STRIP="${STRIP:-}" \
      PKG_CONFIG="${PKG_CONFIG:-false}" \
      PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}" \
      PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-}" \
      "${src_dir}/configure" \
      --build="$(build_triplet)" \
      --host="$(cc_triplet)" \
      --prefix="${prefix}" \
      "$@"
  )
}

download_and_extract() {
  local url="$1"
  local work_dir="$2"
  local archive_name

  mkdir -p "${work_dir}"
  archive_name="${work_dir}/$(basename "${url}")"

  curl \
    -4 \
    --connect-timeout 30 \
    --retry 5 \
    --retry-all-errors \
    --retry-delay 2 \
    -fsSL \
    "${url}" \
    -o "${archive_name}"

  case "${archive_name}" in
    *.tar.gz|*.tgz)
      tar -xzf "${archive_name}" -C "${work_dir}"
      ;;
    *.tar.bz2)
      tar -xjf "${archive_name}" -C "${work_dir}"
      ;;
    *.tar.xz)
      tar -xJf "${archive_name}" -C "${work_dir}"
      ;;
    *.zip)
      unzip -q "${archive_name}" -d "${work_dir}"
      ;;
    *)
      echo "unsupported archive format: ${archive_name}" >&2
      exit 1
      ;;
  esac
}

find_single_directory() {
  local root="$1"
  find "${root}" -mindepth 1 -maxdepth 1 -type d -print -quit
}

find_built_binary() {
  local root="$1"
  local name="$2"

  find "${root}" -type f \( -name "${name}" -o -name "${name}.exe" \) -print -quit
}

install_artifact() {
  local source_path="$1"
  local destination_name="${2:-$(basename "${source_path}")}"

  mkdir -p "${TSB_OUTPUT_DIR}"

  if [[ "${TSB_TARGET_OS:-}" == "windows" ]]; then
    cp "${source_path}" "${TSB_OUTPUT_DIR}/${destination_name}"
  else
    install -m 0755 "${source_path}" "${TSB_OUTPUT_DIR}/${destination_name}"
  fi
}
