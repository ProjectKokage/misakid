# Copyright 2026 the misakid contributors.
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20)
project(misakid_openjtalk LANGUAGES C CXX)

if(NOT APPLE)
  message(FATAL_ERROR "misakid_openjtalk v1 is supported only on macOS arm64")
endif()

if(NOT DEFINED MISAKID_OPENJTALK_SOURCE_DIR)
  message(FATAL_ERROR "MISAKID_OPENJTALK_SOURCE_DIR must name the verified staged Open JTalk source")
endif()

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported architecture" FORCE)
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Minimum macOS version" FORCE)
endif()

set(OPENJTALK_ROOT "${MISAKID_OPENJTALK_SOURCE_DIR}")
set(MECAB_ROOT "${OPENJTALK_ROOT}/mecab/src")
set(GENERATED_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_INCLUDE_DIR}")

# Do not let a direct CMake invocation claim the reviewed safety identity for
# untouched or locally modified upstream sources. This digest covers every
# post-patch file staged by tool/build_native.dart, not only compiled files.
file(GLOB_RECURSE OPENJTALK_VERIFIED_FILES
  LIST_DIRECTORIES false
  RELATIVE "${OPENJTALK_ROOT}"
  "${OPENJTALK_ROOT}/*"
)
list(SORT OPENJTALK_VERIFIED_FILES)
list(LENGTH OPENJTALK_VERIFIED_FILES OPENJTALK_VERIFIED_FILE_COUNT)
set(OPENJTALK_VERIFIED_BYTES 0)
set(OPENJTALK_VERIFIED_RECORDS "")
foreach(RELATIVE_SOURCE IN LISTS OPENJTALK_VERIFIED_FILES)
  set(ABSOLUTE_SOURCE "${OPENJTALK_ROOT}/${RELATIVE_SOURCE}")
  file(SIZE "${ABSOLUTE_SOURCE}" SOURCE_SIZE)
  file(SHA256 "${ABSOLUTE_SOURCE}" SOURCE_SHA256)
  math(EXPR OPENJTALK_VERIFIED_BYTES
    "${OPENJTALK_VERIFIED_BYTES} + ${SOURCE_SIZE}")
  string(APPEND OPENJTALK_VERIFIED_RECORDS
    "${RELATIVE_SOURCE}\t${SOURCE_SHA256}\n")
endforeach()
string(SHA256 OPENJTALK_VERIFIED_TREE_SHA256
  "${OPENJTALK_VERIFIED_RECORDS}")
if(NOT OPENJTALK_VERIFIED_FILE_COUNT EQUAL 139 OR
   NOT OPENJTALK_VERIFIED_BYTES EQUAL 5382103 OR
   NOT OPENJTALK_VERIFIED_TREE_SHA256 STREQUAL
     "8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb")
  message(FATAL_ERROR
    "Open JTalk staged source does not match misakid-openjtalk-safety-v1: "
    "${OPENJTALK_VERIFIED_FILE_COUNT} files, "
    "${OPENJTALK_VERIFIED_BYTES} bytes, "
    "${OPENJTALK_VERIFIED_TREE_SHA256}")
endif()

set(OPEN_JTALK_VERSION 1.11)
set(PACKAGE "open_jtalk")
set(PACKAGE_BUGREPORT "https://github.com/r9y9/open_jtalk/")
set(PACKAGE_NAME "open_jtalk")
set(PACKAGE_URL "")
set(PACKAGE_VERSION "${OPEN_JTALK_VERSION}")
set(PACKAGE_STRING "${PACKAGE_NAME} ${PACKAGE_VERSION}")

include(CheckIncludeFiles)
include(CheckFunctionExists)
include(CheckLibraryExists)
include(CheckTypeSize)
check_include_files(ctype.h HAVE_CTYPE_H)
check_include_files(dirent.h HAVE_DIRENT_H)
check_include_files(fcntl.h HAVE_FCNTL_H)
check_include_files(inttypes.h HAVE_INTTYPES_H)
check_include_files(io.h HAVE_IO_H)
check_include_files(memory.h HAVE_MEMORY_H)
check_include_files(setjmp.h HAVE_SETJMP_H)
check_include_files(stdint.h HAVE_STDINT_H)
check_include_files(stdlib.h HAVE_STDLIB_H)
check_include_files(strings.h HAVE_STRINGS_H)
check_include_files(string.h HAVE_STRING_H)
check_include_files(sys/mman.h HAVE_SYS_MMAN_H)
check_include_files(sys/stat.h HAVE_SYS_STAT_H)
check_include_files(sys/times.h HAVE_SYS_TIMES_H)
check_include_files(sys/types.h HAVE_SYS_TYPES_H)
check_include_files(unistd.h HAVE_UNISTD_H)
check_include_files(windows.h HAVE_WINDOWS_H)
check_function_exists(getenv HAVE_GETENV)
check_function_exists(getpagesize HAVE_GETPAGESIZE)
check_function_exists(mmap HAVE_MMAP)
check_function_exists(opendir HAVE_OPENDIR)
check_function_exists(setjmp HAVE_SETJMP)
check_function_exists(sqrt HAVE_SQRT)
check_function_exists(strstr HAVE_STRSTR)
check_library_exists(iconv iconv_open "" ICONV_CONST)
check_library_exists(m sqrt "" HAVE_LIBM)
check_type_size(char SIZEOF_CHAR)
check_type_size(int SIZEOF_INT)
check_type_size(long SIZEOF_LONG)
check_type_size("long long" SIZEOF_LONG_LONG)
check_type_size(short SIZEOF_SHORT)
check_type_size(size_t SIZEOF_SIZE_T)

configure_file(
  "${OPENJTALK_ROOT}/mecab/config.h.in"
  "${GENERATED_INCLUDE_DIR}/config.h"
)

set(MECAB_RUNTIME_SOURCES
  "${MECAB_ROOT}/char_property.cpp"
  "${MECAB_ROOT}/connector.cpp"
  "${MECAB_ROOT}/context_id.cpp"
  "${MECAB_ROOT}/dictionary.cpp"
  "${MECAB_ROOT}/dictionary_rewriter.cpp"
  "${MECAB_ROOT}/feature_index.cpp"
  "${MECAB_ROOT}/iconv_utils.cpp"
  "${MECAB_ROOT}/libmecab.cpp"
  "${MECAB_ROOT}/mecab.cpp"
  "${MECAB_ROOT}/nbest_generator.cpp"
  "${MECAB_ROOT}/param.cpp"
  "${MECAB_ROOT}/string_buffer.cpp"
  "${MECAB_ROOT}/tagger.cpp"
  "${MECAB_ROOT}/tokenizer.cpp"
  "${MECAB_ROOT}/utils.cpp"
  "${MECAB_ROOT}/viterbi.cpp"
  "${MECAB_ROOT}/writer.cpp"
)

set(OPENJTALK_FRONTEND_SOURCES
  ${MECAB_RUNTIME_SOURCES}
  "${OPENJTALK_ROOT}/mecab2njd/mecab2njd.c"
  "${OPENJTALK_ROOT}/njd/njd.c"
  "${OPENJTALK_ROOT}/njd/njd_node.c"
  "${OPENJTALK_ROOT}/njd_set_accent_phrase/njd_set_accent_phrase.c"
  "${OPENJTALK_ROOT}/njd_set_accent_type/njd_set_accent_type.c"
  "${OPENJTALK_ROOT}/njd_set_digit/njd_set_digit.c"
  "${OPENJTALK_ROOT}/njd_set_long_vowel/njd_set_long_vowel.c"
  "${OPENJTALK_ROOT}/njd_set_pronunciation/njd_set_pronunciation.c"
  "${OPENJTALK_ROOT}/njd_set_unvoiced_vowel/njd_set_unvoiced_vowel.c"
  "${OPENJTALK_ROOT}/text2mecab/text2mecab.c"
)

add_library(openjtalk_frontend OBJECT ${OPENJTALK_FRONTEND_SOURCES})
set_target_properties(openjtalk_frontend PROPERTIES
  POSITION_INDEPENDENT_CODE ON
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
)
target_include_directories(openjtalk_frontend PRIVATE
  "${GENERATED_INCLUDE_DIR}"
  "${OPENJTALK_ROOT}/mecab/src"
  "${OPENJTALK_ROOT}/mecab2njd"
  "${OPENJTALK_ROOT}/njd"
  "${OPENJTALK_ROOT}/njd_set_accent_phrase"
  "${OPENJTALK_ROOT}/njd_set_accent_type"
  "${OPENJTALK_ROOT}/njd_set_digit"
  "${OPENJTALK_ROOT}/njd_set_long_vowel"
  "${OPENJTALK_ROOT}/njd_set_pronunciation"
  "${OPENJTALK_ROOT}/njd_set_unvoiced_vowel"
  "${OPENJTALK_ROOT}/text2mecab"
)
target_compile_definitions(openjtalk_frontend PRIVATE
  HAVE_CONFIG_H
  DIC_VERSION=102
  MECAB_DEFAULT_RC="dummy"
  MECAB_WITHOUT_SHARE_DIC
  PACKAGE="open_jtalk"
  VERSION="${OPEN_JTALK_VERSION}"
  CHARSET_UTF_8
  MECAB_CHARSET=utf-8
  MECAB_UTF8_USE_ONLY
)
target_compile_options(openjtalk_frontend PRIVATE
  -finput-charset=UTF-8
  -fexec-charset=UTF-8
  "-ffile-prefix-map=${OPENJTALK_ROOT}=open_jtalk"
  -Wno-deprecated-declarations
  -Wno-string-plus-int
  -include "${CMAKE_CURRENT_SOURCE_DIR}/src/silent_stdio.h"
)

find_package(Threads REQUIRED)
add_library(misakid_openjtalk SHARED
  "src/misakid_openjtalk.cpp"
  "src/silent_stdio.c"
  $<TARGET_OBJECTS:openjtalk_frontend>
)
target_compile_features(misakid_openjtalk PRIVATE cxx_std_17)
target_compile_definitions(misakid_openjtalk PRIVATE MISAKID_OPENJTALK_BUILD)
target_compile_options(misakid_openjtalk PRIVATE
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=misakid_openjtalk/native"
)
target_include_directories(misakid_openjtalk PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${GENERATED_INCLUDE_DIR}"
  "${OPENJTALK_ROOT}/mecab/src"
  "${OPENJTALK_ROOT}/mecab2njd"
  "${OPENJTALK_ROOT}/njd"
  "${OPENJTALK_ROOT}/njd_set_accent_phrase"
  "${OPENJTALK_ROOT}/njd_set_accent_type"
  "${OPENJTALK_ROOT}/njd_set_digit"
  "${OPENJTALK_ROOT}/njd_set_long_vowel"
  "${OPENJTALK_ROOT}/njd_set_pronunciation"
  "${OPENJTALK_ROOT}/njd_set_unvoiced_vowel"
  "${OPENJTALK_ROOT}/text2mecab"
)
target_link_libraries(misakid_openjtalk PRIVATE Threads::Threads)
if(HAVE_LIBM)
  target_link_libraries(misakid_openjtalk PRIVATE m)
endif()
set_target_properties(misakid_openjtalk PROPERTIES
  OUTPUT_NAME "misakid_openjtalk"
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  MACOSX_RPATH YES
)

install(TARGETS misakid_openjtalk LIBRARY DESTINATION lib)
install(FILES "include/misakid_openjtalk.h" DESTINATION include)
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE"
  "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md"
  "${CMAKE_CURRENT_SOURCE_DIR}/SOURCE_MANIFEST.md"
  DESTINATION share/misakid_openjtalk
)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/licenses/"
  DESTINATION share/misakid_openjtalk/licenses)
