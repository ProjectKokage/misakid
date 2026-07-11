# Copyright 2026 the misakid contributors.
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20)
project(misakid_mecab_ko LANGUAGES C CXX)

if(NOT APPLE)
  message(FATAL_ERROR "misakid_mecab_ko v1 is supported only on macOS arm64")
endif()

if(NOT DEFINED MISAKID_MECAB_KO_SOURCE_DIR)
  message(FATAL_ERROR "MISAKID_MECAB_KO_SOURCE_DIR must name the verified staged MeCab-ko source")
endif()

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported architecture" FORCE)
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Minimum macOS version" FORCE)
endif()

set(MECAB_ROOT "${MISAKID_MECAB_KO_SOURCE_DIR}")
set(MECAB_SRC "${MECAB_ROOT}/src")
set(GENERATED_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_INCLUDE_DIR}")

# Independently verify every post-patch staged file so direct CMake invocation
# cannot claim the reviewed safety identity for untouched or modified sources.
file(GLOB_RECURSE MECAB_VERIFIED_FILES
  LIST_DIRECTORIES false
  RELATIVE "${MECAB_ROOT}"
  "${MECAB_ROOT}/*"
)
list(SORT MECAB_VERIFIED_FILES)
list(LENGTH MECAB_VERIFIED_FILES MECAB_VERIFIED_FILE_COUNT)
set(MECAB_VERIFIED_BYTES 0)
set(MECAB_VERIFIED_RECORDS "")
foreach(RELATIVE_SOURCE IN LISTS MECAB_VERIFIED_FILES)
  set(ABSOLUTE_SOURCE "${MECAB_ROOT}/${RELATIVE_SOURCE}")
  file(SIZE "${ABSOLUTE_SOURCE}" SOURCE_SIZE)
  file(SHA256 "${ABSOLUTE_SOURCE}" SOURCE_SHA256)
  math(EXPR MECAB_VERIFIED_BYTES "${MECAB_VERIFIED_BYTES} + ${SOURCE_SIZE}")
  string(APPEND MECAB_VERIFIED_RECORDS
    "${RELATIVE_SOURCE}\t${SOURCE_SHA256}\n")
endforeach()
string(SHA256 MECAB_VERIFIED_TREE_SHA256 "${MECAB_VERIFIED_RECORDS}")
if(NOT MECAB_VERIFIED_FILE_COUNT EQUAL 236 OR
   NOT MECAB_VERIFIED_BYTES EQUAL 7840991 OR
   NOT MECAB_VERIFIED_TREE_SHA256 STREQUAL
     "f12784924ac4a55296520308472d55e433a50e708f338fd52a9106ece5997691")
  message(FATAL_ERROR
    "MeCab-ko staged source does not match misakid-mecab-ko-safety-v1: "
    "${MECAB_VERIFIED_FILE_COUNT} files, ${MECAB_VERIFIED_BYTES} bytes, "
    "${MECAB_VERIFIED_TREE_SHA256}")
endif()

set(PACKAGE "mecab")
set(PACKAGE_BUGREPORT "")
set(PACKAGE_NAME "mecab")
set(PACKAGE_STRING "mecab 0.996/ko-0.9.2")
set(PACKAGE_TARNAME "mecab")
set(PACKAGE_URL "")
set(PACKAGE_VERSION "0.996/ko-0.9.2")
set(VERSION "0.996/ko-0.9.2")
set(HAVE_GCC_ATOMIC_OPS 1)
set(HAVE_OSX_ATOMIC_OPS 1)
set(HAVE_TLS_KEYWORD 1)
set(STDC_HEADERS 1)
set(HAVE_ICONV 1)
set(HAVE_LIBPTHREAD 1)
set(HAVE_UNSIGNED_LONG_LONG_INT 1)
set(ICONV_CONST "")
set(LT_OBJDIR ".libs/")

include(CheckIncludeFiles)
include(CheckFunctionExists)
include(CheckTypeSize)
check_include_files(ctype.h HAVE_CTYPE_H)
check_include_files(dirent.h HAVE_DIRENT_H)
check_include_files(dlfcn.h HAVE_DLFCN_H)
check_include_files(fcntl.h HAVE_FCNTL_H)
check_include_files(inttypes.h HAVE_INTTYPES_H)
check_include_files(memory.h HAVE_MEMORY_H)
check_include_files(pthread.h HAVE_PTHREAD_H)
check_include_files(stdint.h HAVE_STDINT_H)
check_include_files(stdlib.h HAVE_STDLIB_H)
check_include_files(strings.h HAVE_STRINGS_H)
check_include_files(string.h HAVE_STRING_H)
check_include_files(sys/mman.h HAVE_SYS_MMAN_H)
check_include_files(sys/param.h HAVE_SYS_PARAM_H)
check_include_files(sys/stat.h HAVE_SYS_STAT_H)
check_include_files(sys/times.h HAVE_SYS_TIMES_H)
check_include_files(sys/types.h HAVE_SYS_TYPES_H)
check_include_files(unistd.h HAVE_UNISTD_H)
check_function_exists(getenv HAVE_GETENV)
check_function_exists(getpagesize HAVE_GETPAGESIZE)
check_function_exists(mmap HAVE_MMAP)
check_function_exists(opendir HAVE_OPENDIR)
check_type_size(char SIZEOF_CHAR)
check_type_size(int SIZEOF_INT)
check_type_size(long SIZEOF_LONG)
check_type_size("long long" SIZEOF_LONG_LONG)
check_type_size(short SIZEOF_SHORT)
check_type_size(size_t SIZEOF_SIZE_T)

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/config.h.in"
  "${GENERATED_INCLUDE_DIR}/config.h"
)

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

find_package(Iconv REQUIRED)
find_package(Threads REQUIRED)
add_library(misakid_mecab_ko SHARED
  "src/misakid_mecab_ko.cpp"
  ${MECAB_RUNTIME_SOURCES}
)
target_compile_features(misakid_mecab_ko PRIVATE cxx_std_14)
target_compile_definitions(misakid_mecab_ko PRIVATE
  MISAKID_MECAB_KO_BUILD
  HAVE_CONFIG_H
  DIC_VERSION=102
  MECAB_DEFAULT_RC="/dev/null"
  MECAB_USE_UTF8_ONLY
)
target_compile_options(misakid_mecab_ko PRIVATE
  -finput-charset=UTF-8
  -fexec-charset=UTF-8
  -ffunction-sections
  -fdata-sections
  "-ffile-prefix-map=${MECAB_ROOT}=mecab-ko-0.996-ko-0.9.2"
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=misakid_mecab_ko/native"
  -Wno-deprecated-declarations
  -Wno-deprecated-register
  -Wno-string-plus-int
)
target_link_options(misakid_mecab_ko PRIVATE "LINKER:-dead_strip")
target_include_directories(misakid_mecab_ko PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${GENERATED_INCLUDE_DIR}"
  "${MECAB_SRC}"
)
target_link_libraries(misakid_mecab_ko PRIVATE Iconv::Iconv Threads::Threads)
set_target_properties(misakid_mecab_ko PROPERTIES
  OUTPUT_NAME "misakid_mecab_ko"
  CXX_STANDARD 14
  CXX_STANDARD_REQUIRED YES
  CXX_EXTENSIONS NO
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  MACOSX_RPATH YES
)

install(TARGETS misakid_mecab_ko LIBRARY DESTINATION lib)
install(FILES "include/misakid_mecab_ko.h" DESTINATION include)
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE"
  "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md"
  "${CMAKE_CURRENT_SOURCE_DIR}/SOURCE_MANIFEST.md"
  DESTINATION share/misakid_mecab_ko
)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/licenses/"
  DESTINATION share/misakid_mecab_ko/licenses
)
