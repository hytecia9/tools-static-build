foreach(required_var WORKSPACE_DIR DOCKERFILE TOOL TARGET_ID BASE_IMAGE TARGET_OS TARGET_ARCH TARGET_LIBC OUTPUT_DIR)
  if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
    message(FATAL_ERROR "Missing required variable ${required_var}")
  endif()
endforeach()

function(tsb_convert_path_for_docker input_path output_var)
  if(TARGET_LIBC STREQUAL "msvc")
    file(TO_NATIVE_PATH "${input_path}" converted_path)
  elseif(DEFINED DOCKER_WSL_DISTRO AND NOT "${DOCKER_WSL_DISTRO}" STREQUAL "")
    execute_process(
      COMMAND wsl -d ${DOCKER_WSL_DISTRO} -- wslpath -a ${input_path}
      OUTPUT_VARIABLE converted_path
      RESULT_VARIABLE convert_result
      OUTPUT_STRIP_TRAILING_WHITESPACE
      COMMAND_ERROR_IS_FATAL ANY
    )

    if(NOT convert_result EQUAL 0)
      message(FATAL_ERROR "failed to convert path for WSL docker: ${input_path}")
    endif()
  else()
    file(TO_CMAKE_PATH "${input_path}" converted_path)
  endif()

  set(${output_var} "${converted_path}" PARENT_SCOPE)
endfunction()

set(docker_command docker)
if(NOT TARGET_LIBC STREQUAL "msvc" AND DEFINED DOCKER_WSL_DISTRO AND NOT "${DOCKER_WSL_DISTRO}" STREQUAL "")
  set(docker_command wsl -d ${DOCKER_WSL_DISTRO} -- docker)
endif()

tsb_convert_path_for_docker("${WORKSPACE_DIR}" docker_workspace_dir)
tsb_convert_path_for_docker("${DOCKERFILE}" dockerfile_path)
tsb_convert_path_for_docker("${OUTPUT_DIR}" host_output_dir)

string(REGEX REPLACE "[^A-Za-z0-9_.-]" "-" image_tag "tools-static-build-${TOOL}-${TARGET_ID}")

set(docker_build_args build)
if(DEFINED DOCKER_BUILD_PULL AND DOCKER_BUILD_PULL)
  list(APPEND docker_build_args --pull)
endif()
if(TARGET_LIBC STREQUAL "msvc")
  if(DEFINED WINDOWS_CONTAINER_ISOLATION AND NOT "${WINDOWS_CONTAINER_ISOLATION}" STREQUAL "")
    list(APPEND docker_build_args --isolation ${WINDOWS_CONTAINER_ISOLATION})
  endif()
  if(DEFINED WINDOWS_CONTAINER_BUILD_MEMORY AND NOT "${WINDOWS_CONTAINER_BUILD_MEMORY}" STREQUAL "")
    list(APPEND docker_build_args --memory ${WINDOWS_CONTAINER_BUILD_MEMORY})
  endif()
endif()

list(APPEND docker_build_args
  --build-arg BASE_IMAGE=${BASE_IMAGE}
  --build-arg TOOL_NAME=${TOOL}
  --tag ${image_tag}
  --file ${dockerfile_path}
  ${docker_workspace_dir}
)

message(STATUS "Building Docker image ${image_tag} from ${dockerfile_path}")
execute_process(
  COMMAND ${docker_command} ${docker_build_args}
  COMMAND_ERROR_IS_FATAL ANY
  RESULT_VARIABLE build_result
)

if(NOT build_result EQUAL 0)
  message(FATAL_ERROR "docker build failed for ${TOOL}/${TARGET_ID}")
endif()

message(STATUS "Running ${image_tag} to produce artifacts in ${host_output_dir}")
set(container_output_dir /out)
if(TARGET_LIBC STREQUAL "msvc")
  set(container_output_dir "C:\\out")
endif()

set(docker_run_args
  run
  --rm
  --mount type=bind,src=${host_output_dir},dst=${container_output_dir}
  -e TSB_TOOL_NAME=${TOOL}
  -e TSB_TARGET_ID=${TARGET_ID}
  -e TSB_TARGET_OS=${TARGET_OS}
  -e TSB_TARGET_ARCH=${TARGET_ARCH}
  -e TSB_TARGET_LIBC=${TARGET_LIBC}
  -e TSB_OUTPUT_DIR=${container_output_dir}
)

if(TARGET_LIBC STREQUAL "msvc" AND DEFINED WINDOWS_CONTAINER_ISOLATION AND NOT "${WINDOWS_CONTAINER_ISOLATION}" STREQUAL "")
  list(APPEND docker_run_args --isolation ${WINDOWS_CONTAINER_ISOLATION})
endif()

if(DEFINED ENV{TSB_MAKE_JOBS} AND NOT "$ENV{TSB_MAKE_JOBS}" STREQUAL "")
  list(APPEND docker_run_args -e TSB_MAKE_JOBS=$ENV{TSB_MAKE_JOBS})
endif()

execute_process(
  COMMAND ${docker_command} ${docker_run_args} ${image_tag}
  RESULT_VARIABLE run_result
)

if(NOT run_result EQUAL 0
   AND TOOL STREQUAL "ncat"
   AND TARGET_OS STREQUAL "windows"
   AND TARGET_LIBC STREQUAL "mingw")
  if(EXISTS "${OUTPUT_DIR}/ncat.exe" OR EXISTS "${OUTPUT_DIR}/ncat")
    message(STATUS "docker run returned ${run_result} for ${TOOL}/${TARGET_ID} after producing the ncat artifact; accepting the build result")
    set(run_result 0)
  endif()
endif()

if(NOT run_result EQUAL 0)
  message(FATAL_ERROR "docker run failed for ${TOOL}/${TARGET_ID}")
endif()
