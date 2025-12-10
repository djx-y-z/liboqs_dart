# liboqs_dart - Windows FFI Plugin with pre-built native library
# Uses pre-built oqs.dll from bin/windows/
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "liboqs")
project(${PROJECT_NAME} LANGUAGES CXX)

# Use pre-built library instead of building from source
set(liboqs_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../bin/windows/oqs.dll"
  PARENT_SCOPE
)
