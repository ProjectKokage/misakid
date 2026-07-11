# Copyright 2026 the misakid contributors.
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20)
project(misakid_espeak_en LANGUAGES CXX)

if(NOT APPLE)
  message(FATAL_ERROR "misakid_espeak_en v1 is supported only on macOS arm64")
endif()

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Minimum macOS version" FORCE)

find_package(Threads REQUIRED)
add_library(misakid_espeak_en SHARED src/misakid_espeak_en.cpp)
target_compile_features(misakid_espeak_en PRIVATE cxx_std_17)
target_compile_definitions(misakid_espeak_en PRIVATE MISAKID_ESPEAK_EN_BUILD)
target_compile_options(misakid_espeak_en PRIVATE
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=misakid_espeak_en/native"
)
target_include_directories(misakid_espeak_en PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(misakid_espeak_en PRIVATE Threads::Threads)
set_target_properties(misakid_espeak_en PROPERTIES
  OUTPUT_NAME "misakid_espeak_en"
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  MACOSX_RPATH YES
)

install(TARGETS misakid_espeak_en LIBRARY DESTINATION lib)
install(FILES include/misakid_espeak_en.h DESTINATION include)
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE"
  "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md"
  "${CMAKE_CURRENT_SOURCE_DIR}/SOURCE_MANIFEST.md"
  DESTINATION share/misakid_espeak_en
)
