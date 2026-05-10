# tools-static-build

Cross-build harness for the folders in this repository. Each tool has its Dockerfile under `docker/<tool>/Dockerfile`, and CMake generates build targets that run those Docker images to produce binaries under `artifacts/`.

## Requirements

- CMake 3.24+
- Docker
- On Windows hosts: Docker Desktop plus a WSL distro with a working `docker` CLI for Linux-based dockcross images
- For Windows MSVC container targets: Docker Desktop must be switched to Windows containers

The top-level configure step auto-detects a usable WSL distro on Windows and routes Linux/Android builds through `wsl -d <distro> -- docker` when needed.

## Quick Start

Configure once:

```powershell
cmake -S . -B build
```

Build the verified subset:

```powershell
cmake --build build --config Release
```

Build the full experimental matrix:

```powershell
cmake --build build --target full-matrix --config Release
```

Build a single tool or target:

```powershell
cmake --build build --target curl-windows-mingw-x64 --config Release
cmake --build build --target gdb-linux-glibc-x64 --config Release
cmake --build build --target ncat-windows-msvc-x86 --config Release
cmake --build build --target nmap-windows-msvc-x86 --config Release
```

Validate completion stamps against the declared matrix:

```powershell
cmake --build build --target validate-all-static --config Release
cmake --build build --target validate-gdb --config Release
cmake --build build --target validate-full-matrix --config Release
```

These validation targets only check stamp files for targets declared by CMake. Stale extra folders under `artifacts/` are ignored.

Artifacts are written to:

```text
artifacts/<tool>/<target-id>/
```

Examples:

- `artifacts/curl/windows-mingw-x64/curl.exe`
- `artifacts/gdb/linux-glibc-x64/gdb`
- `artifacts/gdb/linux-glibc-x64/gdbserver`

## Layout

- `CMakeLists.txt`: entry point and verified target selection
- `cmake/TargetMatrix.cmake`: OS, libc, and architecture matrix
- `cmake/StaticBuild.cmake`: per-tool/per-target target generation
- `cmake/RunDockerBuild.cmake`: Docker bridge for dockcross and Windows MSVC containers
- `scripts/tools/*.sh`: actual build logic per tool
- `scripts/windows/**/*.ps1`: Windows MSVC container bootstrap and build logic
- `docker/<tool>/Dockerfile`: per-tool Dockerfile used by the generated targets

## Supported Matrix

The generated target set models these families:

- Linux: `x64`, `x86`, `armv5`, `armv7`, `aarch64`, `mips`, `mipsel`, `ppc`, `riscv64`
- Linux libcs: `glibc`, `musl`, `uClibc` where dockcross images exist in this repository
- Android: `armv7`, `aarch64`, `x86`, `x64` with bionic
- Windows: `x64`, `x86`, `aarch64` via MinGW-based dockcross images
- Windows MSVC containers: currently `x86` for upstream Visual Studio solutions that are effectively Win32-only

Not every tool currently succeeds on every generated target. The complete matrix is exposed through `full-matrix`; the default `all-static` target is the verified subset.

## Verified Subset

`cmake --build build --config Release` builds `all-static`, which is the representative subset currently verified in this workspace.

The older README omitted `musl`, `uClibc`, and several non-x64 architectures from this section. That omission was documentation drift, not an intentional support boundary. The default verified subset now includes representative `musl` and `uClibc` targets again, and several full families were revalidated separately.

Representative targets in `all-static`:

- `busybox-linux-glibc-x64`
- `busybox-linux-musl-armv7`
- `busybox-linux-uclibc-mips`
- `busybox-android-bionic-aarch64`
- `curl-linux-glibc-x64`
- `curl-android-bionic-aarch64`
- `curl-windows-mingw-x64`
- `curl-windows-mingw-x86`
- `curl-windows-mingw-aarch64`
- `lstrace-linux-glibc-x64`
- `nc-linux-glibc-x64`
- `nc-linux-musl-armv7`
- `nc-linux-uclibc-mips`
- `nmap-linux-glibc-x64`
- `nmap-linux-glibc-x86`
- `socat-linux-glibc-x64`
- `socat-linux-uclibc-mips`
- `socat-android-bionic-x64`
- `strace-linux-glibc-x64`
- `tcpdump-linux-glibc-x64`
- `toybox-linux-glibc-x64`
- `toybox-android-bionic-aarch64`
- `wget-linux-glibc-x64`
- `wget-windows-mingw-x64`
- `wget-windows-mingw-x86`
- `wget-windows-mingw-aarch64`

Verified additional output:

- `gdbserver` is produced for `gdb-linux-glibc-x64`
- `nmap` Linux targets also install `ncat` plus the required `share/nmap` runtime data files

Separately revalidated families in this workspace:

- `busybox`: all generated Linux and Android targets rebuilt successfully after the 1.37.0 refresh and the SHA/strip/Android compatibility fixes
- `nc`: all generated Linux and Android targets rebuilt successfully after adding `scripts/tools/nc.sh`
- `socat`: all generated Linux and Android targets rebuilt successfully after the uClibc and Android compatibility fixes

Artifact presence for the verified entries above was checked in this workspace after the latest script changes.

Separately validated Windows MSVC targets:

- `ncat-windows-msvc-x86`
- `nmap-windows-msvc-x86`

These targets were built successfully in Windows container mode in this workspace. The current x86 MSVC path was also revalidated after warning cleanup in this workspace. They are not part of `all-static` because the default verified target mixes Linux dockcross builds and Windows MSVC container builds, which require different Docker backends on Windows hosts.

Observed but not yet counted as green targets:

- `ncat-windows-mingw-x64`
- `ncat-windows-mingw-x86`

Those MinGW targets produced fresh `artifacts/ncat/windows-mingw-*/ncat.exe` files in this workspace, but the generated VS/MSBuild custom build step still reports a spurious `-1` after artifact installation on this Windows host. They remain excluded from `all-static` until that runner-layer issue is isolated.

## Notes Per Tool

- `gdb`: Linux targets build `gdb` and `gdbserver`. Windows targets currently build `gdb` only.
- `lstrace`: implemented by building upstream `ltrace`, so the output binary is `ltrace`.
- `nc`: Linux and Android targets use netcat 0.7.1.
- `ncat`: separate tool. MinGW targets remain available, and Windows MSVC `x86` is built from the upstream Visual Studio solution in a Windows container.
- `nmap`: validated for Linux `x64` and `x86`, plus Windows MSVC `x86`. Windows artifacts include `nmap.exe` and the runtime data files required at runtime.
- `strace`: Linux-only in practice.

## Known Gaps

These targets are still part of `full-matrix`, but are not part of the verified default build:

- `gdb` is still the main matrix holdout. The currently observed failures are: musl `armv5` termios field mismatches, musl `armv7` GMP assembly using unsupported `umaal`/`mls`, uClibc `armv5`/`mips` configure failures around `libiconv`, and Windows MinGW console-symbol issues on `aarch64`
- `gdb` on Android is still not green in this workspace
- `ncat-windows-mingw-x64` and `ncat-windows-mingw-x86` currently build their artifacts but still surface a false-negative exit through the generated Windows/MSBuild runner on this host
- There is no Windows MSVC `x64` Nmap/Ncat target yet because upstream project files are effectively Win32-only and the current `nmap-mswin32-aux` import libraries (`Packet.lib`, `wpcap.lib`, `libssl.lib`, `libcrypto.lib`) are `machine (x86)`
- `full-matrix` is still not a one-shot target on a Windows host when it mixes Linux/Android/MinGW dockcross builds with Windows MSVC container builds; those backends must be validated separately

## Practical Notes

- Tool images inherit from dockcross images such as `dockcross/linux-x64`, `dockcross/android-arm64`, `dockcross/windows-static-x64`, and `dockcross/windows-arm64`.
- Windows MSVC images inherit from `TSB_WINDOWS_MSVC_BASE_IMAGE` and install Visual Studio Build Tools following the Microsoft container guidance, with extra utilities installed through Chocolatey.
- Output directories are treated as build stamps, so rerunning the same target is incremental.
- Set `TSB_MAKE_JOBS` in the host environment to override in-container `make -j` parallelism for troubleshooting or memory-constrained hosts.
- If Docker is switched to Windows containers, Linux and Android targets on Windows hosts will fail unless CMake can route Docker through WSL.
- Build the Windows MSVC targets separately when Docker Desktop is in Windows container mode:
	- `cmake --build build --target ncat-windows-msvc-x86 --config Release`
	- `cmake --build build --target nmap-windows-msvc-x86 --config Release`
- Windows MSVC container tuning:
	- `TSB_WINDOWS_MSVC_BASE_IMAGE`: base image for the Windows build containers
	- `TSB_WINDOWS_CONTAINER_ISOLATION`: defaults to `hyperv`, can be set to `process`
	- `TSB_WINDOWS_CONTAINER_BUILD_MEMORY`: defaults to `2GB` for Build Tools image creation

## GitHub Actions

- `.github/workflows/build.yml`: builds the current `all-static` dockcross subset on `ubuntu-latest` and uploads a compressed artifact bundle
- `.github/workflows/release.yml`: rebuilds the dockcross verified subset on `ubuntu-latest`, builds the Windows MSVC x86 archive on `windows-2022`, and publishes both assets to the same GitHub release for tags or manual release runs
- `.github/workflows/windows-msvc.yml`: standalone Windows MSVC workflow for ad-hoc runs, and also the reusable workflow called by `release.yml`

The release workflow now uses GitHub-hosted runners for both halves: Ubuntu for dockcross builds and Windows 2022 with process-isolated Windows containers for the MSVC subset.

