# Copyright 2026 the misakid contributors.
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20)
project(misakid_mecab_ja LANGUAGES C CXX)

if(NOT APPLE)
  message(FATAL_ERROR "The standalone misakid_mecab_ja build supports only macOS arm64")
endif()

if(NOT DEFINED MISAKID_MECAB_JA_SOURCE_DIR)
  message(FATAL_ERROR "MISAKID_MECAB_JA_SOURCE_DIR must name the verified staged pyopenjtalk source")
endif()

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Exact minimum macOS version" FORCE)

set(OPENJTALK_ROOT "${MISAKID_MECAB_JA_SOURCE_DIR}")
set(MECAB_SRC "${OPENJTALK_ROOT}/mecab/src")

# Independently prove the complete unmodified staged source identity. The build
# tool stages only files named by pyopenjtalk's source manifest.
file(GLOB_RECURSE VERIFIED_FILES
  LIST_DIRECTORIES false
  RELATIVE "${OPENJTALK_ROOT}"
  "${OPENJTALK_ROOT}/*"
)
list(SORT VERIFIED_FILES)
list(LENGTH VERIFIED_FILES VERIFIED_FILE_COUNT)
set(VERIFIED_BYTES 0)
set(VERIFIED_RECORDS "")
foreach(RELATIVE_SOURCE IN LISTS VERIFIED_FILES)
  set(ABSOLUTE_SOURCE "${OPENJTALK_ROOT}/${RELATIVE_SOURCE}")
  file(SIZE "${ABSOLUTE_SOURCE}" SOURCE_SIZE)
  file(SHA256 "${ABSOLUTE_SOURCE}" SOURCE_SHA256)
  math(EXPR VERIFIED_BYTES "${VERIFIED_BYTES} + ${SOURCE_SIZE}")
  string(APPEND VERIFIED_RECORDS "${RELATIVE_SOURCE}\t${SOURCE_SHA256}\n")
endforeach()
string(SHA256 VERIFIED_TREE_SHA256 "${VERIFIED_RECORDS}")
if(NOT VERIFIED_FILE_COUNT EQUAL 139 OR
   NOT VERIFIED_BYTES EQUAL 5381473 OR
   NOT VERIFIED_TREE_SHA256 STREQUAL
     "b963ef63d435e3bba884d5943ee60ac5621cdf1323195140757e1a5f37ca7dd4")
  message(FATAL_ERROR
    "Staged pyopenjtalk source does not match the pinned v2 portable source: "
    "${VERIFIED_FILE_COUNT} files, ${VERIFIED_BYTES} bytes, "
    "${VERIFIED_TREE_SHA256}")
endif()

set(MECAB_RUNTIME_SOURCES
  "${MECAB_SRC}/char_property.cpp"
  "${MECAB_SRC}/connector.cpp"
  "${MECAB_SRC}/context_id.cpp"
  "${MECAB_SRC}/dictionary.cpp"
  "${MECAB_SRC}/dictionary_rewriter.cpp"
  "${MECAB_SRC}/feature_index.cpp"
  "${MECAB_SRC}/iconv_utils.cpp"
  "${MECAB_SRC}/libmecab.cpp"
  "${MECAB_SRC}/nbest_generator.cpp"
  "${MECAB_SRC}/param.cpp"
  "${MECAB_SRC}/string_buffer.cpp"
  "${MECAB_SRC}/tagger.cpp"
  "${MECAB_SRC}/tokenizer.cpp"
  "${MECAB_SRC}/utils.cpp"
  "${MECAB_SRC}/viterbi.cpp"
  "${MECAB_SRC}/writer.cpp"
)

find_package(Threads REQUIRED)
add_library(misakid_mecab_ja SHARED
  "src/misakid_mecab_ja.cpp"
  ${MECAB_RUNTIME_SOURCES}
)
target_compile_features(misakid_mecab_ja PRIVATE cxx_std_17)
target_compile_definitions(misakid_mecab_ja PRIVATE
  MISAKID_MECAB_JA_BUILD
  HAVE_CONFIG_H
  DIC_VERSION=102
  MECAB_DEFAULT_RC="/dev/null"
  MECAB_USE_UTF8_ONLY
)
target_compile_options(misakid_mecab_ja PRIVATE
  -finput-charset=UTF-8
  -fexec-charset=UTF-8
  -ffunction-sections
  -fdata-sections
  "-ffile-prefix-map=${OPENJTALK_ROOT}=pyopenjtalk-0.4.1/open_jtalk"
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=misakid_mecab_ja/native"
  -Wno-deprecated-declarations
  -Wno-deprecated-register
  -Wno-string-plus-int
)
target_link_options(misakid_mecab_ja PRIVATE "LINKER:-dead_strip")
target_include_directories(misakid_mecab_ja PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/portable"
  "${MECAB_SRC}"
)
target_link_libraries(misakid_mecab_ja PRIVATE Threads::Threads)
set_target_properties(misakid_mecab_ja PROPERTIES
  OUTPUT_NAME "misakid_mecab_ja"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  CXX_EXTENSIONS NO
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  MACOSX_RPATH YES
)

install(TARGETS misakid_mecab_ja LIBRARY DESTINATION lib)
install(FILES "include/misakid_mecab_ja.h" DESTINATION include)
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE"
  "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md"
  "${CMAKE_CURRENT_SOURCE_DIR}/SOURCE_MANIFEST.md"
  DESTINATION share/misakid_mecab_ja
)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/licenses/"
  DESTINATION share/misakid_mecab_ja/licenses
)
