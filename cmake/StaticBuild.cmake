function(tsb_register_tool tool_name)
  get_property(registered_tools GLOBAL PROPERTY TSB_REGISTERED_TOOLS)

  if(NOT tool_name IN_LIST registered_tools)
    set_property(GLOBAL APPEND PROPERTY TSB_REGISTERED_TOOLS "${tool_name}")
  endif()
endfunction()

function(tsb_register_expected_stamp tool_name stamp_file)
  tsb_register_tool("${tool_name}")
  set_property(GLOBAL APPEND PROPERTY "TSB_EXPECTED_STAMPS_${tool_name}" "${stamp_file}")
  set_property(GLOBAL APPEND PROPERTY TSB_EXPECTED_STAMPS_FULL_MATRIX "${stamp_file}")
endfunction()

function(tsb_register_expected_stamp_from_target property_name build_target)
  if(NOT build_target MATCHES "^([^-]+)-(.+)$")
    message(FATAL_ERROR "Cannot derive tool and target id from build target ${build_target}")
  endif()

  set(tool_name "${CMAKE_MATCH_1}")
  set(target_id "${CMAKE_MATCH_2}")
  set(stamp_file "${TSB_OUTPUT_DIR}/${tool_name}/${target_id}/.complete")

  set_property(GLOBAL APPEND PROPERTY "${property_name}" "${stamp_file}")
endfunction()

function(tsb_add_verified_target build_target)
  add_dependencies(all-static "${build_target}")
  tsb_register_expected_stamp_from_target(TSB_EXPECTED_STAMPS_ALL_STATIC "${build_target}")
endfunction()

function(tsb_write_validation_manifest manifest_file)
  cmake_parse_arguments(TSB "" "" "STAMPS" ${ARGN})

  if(NOT DEFINED TSB_STAMPS)
    message(FATAL_ERROR "Missing required argument STAMPS")
  endif()

  list(REMOVE_DUPLICATES TSB_STAMPS)
  get_filename_component(manifest_dir "${manifest_file}" DIRECTORY)
  file(MAKE_DIRECTORY "${manifest_dir}")

  string(JOIN "\n" manifest_contents ${TSB_STAMPS})
  if(NOT manifest_contents STREQUAL "")
    string(APPEND manifest_contents "\n")
  endif()

  file(WRITE "${manifest_file}" "${manifest_contents}")
endfunction()

function(tsb_add_validation_target)
  cmake_parse_arguments(TSB "" "TARGET_NAME;LABEL;MANIFEST" "" ${ARGN})

  foreach(required_arg TARGET_NAME LABEL MANIFEST)
    if(NOT TSB_${required_arg})
      message(FATAL_ERROR "Missing required argument ${required_arg}")
    endif()
  endforeach()

  add_custom_target(
    "${TSB_TARGET_NAME}"
    COMMAND
      "${CMAKE_COMMAND}"
      -DVALIDATION_LABEL=${TSB_LABEL}
      -DVALIDATION_MANIFEST=${TSB_MANIFEST}
      -P "${CMAKE_SOURCE_DIR}/cmake/ValidateStamps.cmake"
    USES_TERMINAL
    VERBATIM
  )
endfunction()

function(tsb_finalize_validation_targets)
  get_property(registered_tools GLOBAL PROPERTY TSB_REGISTERED_TOOLS)

  if(registered_tools)
    list(REMOVE_DUPLICATES registered_tools)

    foreach(tool_name IN LISTS registered_tools)
      get_property(tool_stamps GLOBAL PROPERTY "TSB_EXPECTED_STAMPS_${tool_name}")

      if(NOT tool_stamps)
        continue()
      endif()

      list(REMOVE_DUPLICATES tool_stamps)
      set(manifest_file "${CMAKE_BINARY_DIR}/validation/${tool_name}.stamps")
      tsb_write_validation_manifest("${manifest_file}" STAMPS ${tool_stamps})
      tsb_add_validation_target(
        TARGET_NAME "validate-${tool_name}"
        LABEL "${tool_name}"
        MANIFEST "${manifest_file}"
      )
    endforeach()
  endif()

  get_property(all_static_stamps GLOBAL PROPERTY TSB_EXPECTED_STAMPS_ALL_STATIC)
  if(all_static_stamps)
    list(REMOVE_DUPLICATES all_static_stamps)
    set(all_static_manifest "${CMAKE_BINARY_DIR}/validation/all-static.stamps")
    tsb_write_validation_manifest("${all_static_manifest}" STAMPS ${all_static_stamps})
    tsb_add_validation_target(
      TARGET_NAME validate-all-static
      LABEL all-static
      MANIFEST "${all_static_manifest}"
    )
  endif()

  get_property(full_matrix_stamps GLOBAL PROPERTY TSB_EXPECTED_STAMPS_FULL_MATRIX)
  if(full_matrix_stamps)
    list(REMOVE_DUPLICATES full_matrix_stamps)
    set(full_matrix_manifest "${CMAKE_BINARY_DIR}/validation/full-matrix.stamps")
    tsb_write_validation_manifest("${full_matrix_manifest}" STAMPS ${full_matrix_stamps})
    tsb_add_validation_target(
      TARGET_NAME validate-full-matrix
      LABEL full-matrix
      MANIFEST "${full_matrix_manifest}"
    )
  endif()
endfunction()

function(tsb_add_docker_build_target)
  cmake_parse_arguments(TSB "" "TOOL;TARGET_ID;BASE_IMAGE;TARGET_OS;TARGET_ARCH;TARGET_LIBC;DOCKERFILE" "" ${ARGN})

  foreach(required_arg TOOL TARGET_ID BASE_IMAGE TARGET_OS TARGET_ARCH TARGET_LIBC DOCKERFILE)
    if(NOT TSB_${required_arg})
      message(FATAL_ERROR "Missing required argument ${required_arg}")
    endif()
  endforeach()

  set(output_dir "${TSB_OUTPUT_DIR}/${TSB_TOOL}/${TSB_TARGET_ID}")
  set(stamp_file "${output_dir}/.complete")
  set(target_name "${TSB_TOOL}-${TSB_TARGET_ID}")
  tsb_register_expected_stamp("${TSB_TOOL}" "${stamp_file}")
  file(GLOB_RECURSE tsb_script_deps CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/scripts/*.sh" "${CMAKE_SOURCE_DIR}/scripts/*.ps1")

  add_custom_command(
    OUTPUT "${stamp_file}"
    DEPENDS
      "${TSB_DOCKERFILE}"
      "${CMAKE_SOURCE_DIR}/cmake/RunDockerBuild.cmake"
      ${tsb_script_deps}
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${output_dir}"
    COMMAND
      "${CMAKE_COMMAND}"
      -DWORKSPACE_DIR=${CMAKE_SOURCE_DIR}
      -DDOCKERFILE=${TSB_DOCKERFILE}
      -DDOCKER_WSL_DISTRO=${TSB_WSL_DISTRO}
      -DDOCKER_BUILD_PULL=${TSB_DOCKER_BUILD_PULL}
      -DWINDOWS_CONTAINER_ISOLATION=${TSB_WINDOWS_CONTAINER_ISOLATION}
      -DWINDOWS_CONTAINER_BUILD_MEMORY=${TSB_WINDOWS_CONTAINER_BUILD_MEMORY}
      -DTOOL=${TSB_TOOL}
      -DTARGET_ID=${TSB_TARGET_ID}
      -DBASE_IMAGE=${TSB_BASE_IMAGE}
      -DTARGET_OS=${TSB_TARGET_OS}
      -DTARGET_ARCH=${TSB_TARGET_ARCH}
      -DTARGET_LIBC=${TSB_TARGET_LIBC}
      -DOUTPUT_DIR=${output_dir}
      -P "${CMAKE_SOURCE_DIR}/cmake/RunDockerBuild.cmake"
    COMMAND "${CMAKE_COMMAND}" -E touch "${stamp_file}"
    USES_TERMINAL
    VERBATIM
  )

  add_custom_target(
    "${target_name}"
    COMMAND "${CMAKE_COMMAND}" -E echo_append ""
    DEPENDS "${stamp_file}"
  )
endfunction()

function(tsb_parse_target_spec spec target_id_var base_image_var target_os_var target_arch_var target_libc_var)
  string(REPLACE "|" ";" target_parts "${spec}")
  list(LENGTH target_parts target_part_count)

  if(NOT target_part_count EQUAL 5)
    message(FATAL_ERROR "Malformed target spec: ${spec}")
  endif()

  list(GET target_parts 0 target_id)
  list(GET target_parts 1 base_image)
  list(GET target_parts 2 target_os)
  list(GET target_parts 3 target_arch)
  list(GET target_parts 4 target_libc)

  set(${target_id_var} "${target_id}" PARENT_SCOPE)
  set(${base_image_var} "${base_image}" PARENT_SCOPE)
  set(${target_os_var} "${target_os}" PARENT_SCOPE)
  set(${target_arch_var} "${target_arch}" PARENT_SCOPE)
  set(${target_libc_var} "${target_libc}" PARENT_SCOPE)
endfunction()

function(tsb_add_standard_tool)
  cmake_parse_arguments(TSB "" "TOOL;DOCKERFILE" "TARGET_GROUPS" ${ARGN})

  if(NOT TSB_TOOL)
    message(FATAL_ERROR "Missing required argument TOOL")
  endif()

  if(NOT TSB_DOCKERFILE)
    set(TSB_DOCKERFILE "${CMAKE_SOURCE_DIR}/docker/${TSB_TOOL}/Dockerfile")
  endif()

  add_custom_target("${TSB_TOOL}" COMMAND "${CMAKE_COMMAND}" -E echo_append "")

  foreach(target_group IN LISTS TSB_TARGET_GROUPS)
    set(target_group_var "TSB_TARGETS_${target_group}")

    if(NOT DEFINED ${target_group_var})
      message(FATAL_ERROR "Unknown target group ${target_group}")
    endif()

    foreach(target_spec IN LISTS ${target_group_var})
      tsb_parse_target_spec(
        "${target_spec}"
        target_id
        base_image
        target_os
        target_arch
        target_libc
      )

      tsb_add_docker_build_target(
        TOOL ${TSB_TOOL}
        TARGET_ID ${target_id}
        BASE_IMAGE ${base_image}
        TARGET_OS ${target_os}
        TARGET_ARCH ${target_arch}
        TARGET_LIBC ${target_libc}
        DOCKERFILE "${TSB_DOCKERFILE}"
      )

      add_dependencies("${TSB_TOOL}" "${TSB_TOOL}-${target_id}")
    endforeach()
  endforeach()

  add_dependencies(full-matrix "${TSB_TOOL}")
endfunction()
