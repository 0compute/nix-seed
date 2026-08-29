cmake_minimum_required(VERSION 3.20)
project(cpp-boost-example LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Boost REQUIRED)

add_executable(cpp-boost-example main.cpp)
target_link_libraries(cpp-boost-example PRIVATE Boost::boost)

install(TARGETS cpp-boost-example)
