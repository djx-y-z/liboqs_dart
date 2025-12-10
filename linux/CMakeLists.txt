# liboqs_dart - Linux FFI Plugin with pre-built native library
# Uses pre-built liboqs.so from bin/linux/
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "liboqs")
project(${PROJECT_NAME} LANGUAGES CXX)

# Use pre-built library instead of building from source
set(liboqs_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../bin/linux/liboqs.so"
  PARENT_SCOPE
)
