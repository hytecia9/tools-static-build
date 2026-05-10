cmake_minimum_required(VERSION 3.24)

project(tools_static_build NONE)

set(TSB_OUTPUT_DIR "${CMAKE_SOURCE_DIR}/artifacts" CACHE PATH "Output directory for built artifacts")
set(TSB_WSL_DISTRO "" CACHE STRING "WSL distro used to run Docker for Linux-based builds on Windows hosts")
set(TSB_WINDOWS_MSVC_BASE_IMAGE "mcr.microsoft.com/dotnet/framework/runtime:4.8.1-windowsservercore-ltsc2022" CACHE STRING "Base image for Windows MSVC build containers")
set(TSB_WINDOWS_CONTAINER_ISOLATION "hyperv" CACHE STRING "Isolation mode for Windows containers: hyperv or process")
set(TSB_WINDOWS_CONTAINER_BUILD_MEMORY "2GB" CACHE STRING "Memory limit passed to docker build for Windows MSVC container images")
option(TSB_DOCKER_BUILD_PULL "Pass --pull to docker build when preparing tool images" OFF)

if(CMAKE_HOST_WIN32 AND TSB_WSL_DISTRO STREQUAL "")
  execute_process(
    COMMAND wsl -l -q
    OUTPUT_VARIABLE tsb_wsl_distros_raw
    RESULT_VARIABLE tsb_wsl_list_result
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(tsb_wsl_list_result EQUAL 0 AND NOT tsb_wsl_distros_raw STREQUAL "")
    string(REPLACE "\r\n" "\n" tsb_wsl_distros_raw "${tsb_wsl_distros_raw}")
    string(REPLACE "\n" ";" tsb_wsl_distros "${tsb_wsl_distros_raw}")

    foreach(tsb_wsl_candidate IN LISTS tsb_wsl_distros)
      string(STRIP "${tsb_wsl_candidate}" tsb_wsl_candidate)
      if(tsb_wsl_candidate STREQUAL "")
        continue()
      endif()

      execute_process(
        COMMAND wsl -d ${tsb_wsl_candidate} -- docker version
        RESULT_VARIABLE tsb_wsl_docker_result
        OUTPUT_QUIET
        ERROR_QUIET
      )

      if(tsb_wsl_docker_result EQUAL 0)
        set(TSB_WSL_DISTRO "${tsb_wsl_candidate}" CACHE STRING "WSL distro used to run Docker for Linux-based builds on Windows hosts" FORCE)
        message(STATUS "Using Docker via WSL distro: ${TSB_WSL_DISTRO}")
        break()
      endif()
    endforeach()
  endif()

  if(TSB_WSL_DISTRO STREQUAL "")
    message(WARNING "No WSL distro with a working docker CLI was detected. Linux-based dockcross builds may fail until Docker is switched to Linux containers or TSB_WSL_DISTRO is set manually.")
  endif()
endif()

include("${CMAKE_SOURCE_DIR}/cmake/StaticBuild.cmake")
include("${CMAKE_SOURCE_DIR}/cmake/TargetMatrix.cmake")

add_custom_target(all-static ALL COMMAND "${CMAKE_COMMAND}" -E echo_append "")
add_custom_target(full-matrix COMMAND "${CMAKE_COMMAND}" -E echo_append "")

tsb_add_standard_tool(
  TOOL busybox
  TARGET_GROUPS LINUX ANDROID
)

tsb_add_standard_tool(
  TOOL curl
  TARGET_GROUPS LINUX ANDROID WINDOWS
)

tsb_add_standard_tool(
  TOOL gdb
  TARGET_GROUPS LINUX ANDROID WINDOWS
)

tsb_add_standard_tool(
  TOOL lstrace
  TARGET_GROUPS LINUX_HOSTED
)

tsb_add_standard_tool(
  TOOL nc
  TARGET_GROUPS LINUX ANDROID
)

tsb_add_standard_tool(
  TOOL ncat
  TARGET_GROUPS WINDOWS_X64_X86
)

tsb_add_standard_tool(
  TOOL nmap
  TARGET_GROUPS LINUX_X64_X86
)

tsb_add_standard_tool(
  TOOL socat
  TARGET_GROUPS LINUX ANDROID
)

tsb_add_standard_tool(
  TOOL strace
  TARGET_GROUPS LINUX
)

tsb_add_standard_tool(
  TOOL tcpdump
  TARGET_GROUPS LINUX ANDROID
)

tsb_add_standard_tool(
  TOOL toybox
  TARGET_GROUPS LINUX ANDROID
)

tsb_add_standard_tool(
  TOOL wget
  TARGET_GROUPS LINUX ANDROID WINDOWS
)

foreach(target_spec IN LISTS TSB_TARGETS_WINDOWS_MSVC_X86)
  tsb_parse_target_spec(
    "${target_spec}"
    target_id
    base_image
    target_os
    target_arch
    target_libc
  )

  tsb_add_docker_build_target(
    TOOL ncat
    TARGET_ID ${target_id}
    BASE_IMAGE ${base_image}
    TARGET_OS ${target_os}
    TARGET_ARCH ${target_arch}
    TARGET_LIBC ${target_libc}
    DOCKERFILE "${CMAKE_SOURCE_DIR}/docker/ncat/Dockerfile.msvc"
  )
  add_dependencies(ncat "ncat-${target_id}")

  tsb_add_docker_build_target(
    TOOL nmap
    TARGET_ID ${target_id}
    BASE_IMAGE ${base_image}
    TARGET_OS ${target_os}
    TARGET_ARCH ${target_arch}
    TARGET_LIBC ${target_libc}
    DOCKERFILE "${CMAKE_SOURCE_DIR}/docker/nmap/Dockerfile.msvc"
  )
  add_dependencies(nmap "nmap-${target_id}")
endforeach()

tsb_add_verified_target(busybox-linux-glibc-x64)
tsb_add_verified_target(busybox-linux-musl-armv7)
tsb_add_verified_target(busybox-linux-uclibc-mips)
tsb_add_verified_target(busybox-android-bionic-aarch64)
tsb_add_verified_target(curl-linux-glibc-x64)
tsb_add_verified_target(curl-android-bionic-aarch64)
tsb_add_verified_target(curl-windows-mingw-x64)
tsb_add_verified_target(curl-windows-mingw-x86)
tsb_add_verified_target(curl-windows-mingw-aarch64)
tsb_add_verified_target(lstrace-linux-glibc-x64)
tsb_add_verified_target(nc-linux-glibc-x64)
tsb_add_verified_target(nc-linux-musl-armv7)
tsb_add_verified_target(nc-linux-uclibc-mips)
tsb_add_verified_target(nmap-linux-glibc-x64)
tsb_add_verified_target(nmap-linux-glibc-x86)
tsb_add_verified_target(socat-linux-glibc-x64)
tsb_add_verified_target(socat-linux-uclibc-mips)
tsb_add_verified_target(socat-android-bionic-x64)
tsb_add_verified_target(strace-linux-glibc-x64)
tsb_add_verified_target(tcpdump-linux-glibc-x64)
tsb_add_verified_target(toybox-linux-glibc-x64)
tsb_add_verified_target(toybox-android-bionic-aarch64)
tsb_add_verified_target(wget-linux-glibc-x64)
tsb_add_verified_target(wget-windows-mingw-x64)
tsb_add_verified_target(wget-windows-mingw-x86)
tsb_add_verified_target(wget-windows-mingw-aarch64)

tsb_finalize_validation_targets()
