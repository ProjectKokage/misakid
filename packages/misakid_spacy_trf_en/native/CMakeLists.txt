# Copyright 2026 the misakid contributors.
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20)
project(misakid_spacy_trf_en LANGUAGES CXX)

if(NOT APPLE)
  message(FATAL_ERROR "misakid_spacy_trf_en v1 is supported only on macOS arm64")
endif()

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Minimum macOS version" FORCE)

find_package(Threads REQUIRED)
find_library(ACCELERATE_FRAMEWORK Accelerate REQUIRED)

add_library(misakid_spacy_trf_en SHARED src/misakid_spacy_trf_en.cpp)
target_compile_features(misakid_spacy_trf_en PRIVATE cxx_std_17)
target_compile_definitions(misakid_spacy_trf_en PRIVATE
  MISAKID_SPACY_TRF_EN_BUILD
)
target_compile_options(misakid_spacy_trf_en PRIVATE
  -Wall
  -Wextra
  -Wpedantic
  -Wno-deprecated-declarations
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=misakid_spacy_trf_en/native"
)
target_include_directories(misakid_spacy_trf_en PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(misakid_spacy_trf_en PRIVATE
  "${ACCELERATE_FRAMEWORK}"
  Threads::Threads
)
set_target_properties(misakid_spacy_trf_en PROPERTIES
  OUTPUT_NAME "misakid_spacy_trf_en"
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  MACOSX_RPATH YES
)

install(TARGETS misakid_spacy_trf_en LIBRARY DESTINATION lib)
install(FILES include/misakid_spacy_trf_en.h DESTINATION include)
install(FILES SOURCE_MANIFEST.md DESTINATION share/misakid_spacy_trf_en)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE"
  DESTINATION share/misakid_spacy_trf_en)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md")
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md"
    DESTINATION share/misakid_spacy_trf_en)
endif()
