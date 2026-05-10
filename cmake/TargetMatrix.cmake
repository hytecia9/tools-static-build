set(TSB_TARGETS_LINUX
  "linux-glibc-x64|dockcross/linux-x64|linux|x64|glibc"
  "linux-glibc-x86|dockcross/linux-x86|linux|x86|glibc"
  "linux-glibc-armv5|dockcross/linux-armv5|linux|armv5|glibc"
  "linux-musl-armv5|dockcross/linux-armv5-musl|linux|armv5|musl"
  "linux-uclibc-armv5|dockcross/linux-armv5-uclibc|linux|armv5|uclibc"
  "linux-glibc-armv7|dockcross/linux-armv7|linux|armv7|glibc"
  "linux-musl-armv7|dockcross/linux-armv7l-musl|linux|armv7|musl"
  "linux-glibc-aarch64|dockcross/linux-arm64|linux|aarch64|glibc"
  "linux-musl-aarch64|dockcross/linux-arm64-musl|linux|aarch64|musl"
  "linux-glibc-mips|dockcross/linux-mips|linux|mips|glibc"
  "linux-uclibc-mips|dockcross/linux-mips-uclibc|linux|mips|uclibc"
  "linux-glibc-mipsel|dockcross/linux-mipsel-lts|linux|mipsel|glibc"
  "linux-glibc-ppc|dockcross/linux-ppc|linux|ppc|glibc"
  "linux-glibc-riscv64|dockcross/linux-riscv64|linux|riscv64|glibc"
)

set(TSB_TARGETS_ANDROID
  "android-bionic-armv7|dockcross/android-arm|android|armv7|bionic"
  "android-bionic-aarch64|dockcross/android-arm64|android|aarch64|bionic"
  "android-bionic-x86|dockcross/android-x86|android|x86|bionic"
  "android-bionic-x64|dockcross/android-x86_64|android|x64|bionic"
)

set(TSB_TARGETS_LINUX_HOSTED
  "linux-glibc-x64|dockcross/linux-x64|linux|x64|glibc"
)

set(TSB_TARGETS_LINUX_X64_X86
  "linux-glibc-x64|dockcross/linux-x64|linux|x64|glibc"
  "linux-glibc-x86|dockcross/linux-x86|linux|x86|glibc"
)

set(TSB_TARGETS_WINDOWS_X64_X86
  "windows-mingw-x64|dockcross/windows-static-x64|windows|x64|mingw"
  "windows-mingw-x86|dockcross/windows-static-x86|windows|x86|mingw"
)

set(TSB_TARGETS_WINDOWS_MSVC_X86
  "windows-msvc-x86|${TSB_WINDOWS_MSVC_BASE_IMAGE}|windows|x86|msvc"
)

set(TSB_TARGETS_WINDOWS
  "windows-mingw-x64|dockcross/windows-static-x64|windows|x64|mingw"
  "windows-mingw-x86|dockcross/windows-static-x86|windows|x86|mingw"
  "windows-mingw-aarch64|dockcross/windows-arm64|windows|aarch64|mingw"
)