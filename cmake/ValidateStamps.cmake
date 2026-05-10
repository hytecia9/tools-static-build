foreach(required_var VALIDATION_LABEL VALIDATION_MANIFEST)
  if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
    message(FATAL_ERROR "Missing required variable ${required_var}")
  endif()
endforeach()

if(NOT EXISTS "${VALIDATION_MANIFEST}")
  message(FATAL_ERROR "Missing validation manifest: ${VALIDATION_MANIFEST}")
endif()

file(STRINGS "${VALIDATION_MANIFEST}" expected_stamps)
list(FILTER expected_stamps EXCLUDE REGEX "^$")

set(missing_stamps)
foreach(expected_stamp IN LISTS expected_stamps)
  if(NOT EXISTS "${expected_stamp}")
    list(APPEND missing_stamps "${expected_stamp}")
  endif()
endforeach()

if(missing_stamps)
  list(JOIN missing_stamps "\n  " missing_stamp_output)
  message(FATAL_ERROR "Missing completion stamps for ${VALIDATION_LABEL}:\n  ${missing_stamp_output}")
endif()

message(STATUS "All expected completion stamps are present for ${VALIDATION_LABEL}")