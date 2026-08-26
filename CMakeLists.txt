# The following lines of boilerplate have to be in your project's
# CMakeLists in this exact order for cmake to work correctly
cmake_minimum_required(VERSION 3.16)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Choose default type of build (Debug)" FORCE)
endif()
if(NOT WEB_BUILD_CMD)
    set(WEB_BUILD_CMD "npm" CACHE STRING "Choose web build command" FORCE)
endif()
project(zig-esp32-switch-controller)
