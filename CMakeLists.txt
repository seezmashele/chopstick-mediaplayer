cmake_minimum_required(VERSION 3.21)

project(chopstick
    VERSION 0.1.0
    DESCRIPTION "Chopstick Media Player"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick)
qt_standard_project_setup(REQUIRES 6.5)

find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)

qt_add_executable(chopstick
    src/main.cpp
    src/mpvitem.cpp
)

qt_add_qml_module(chopstick
    URI Chopstick
    VERSION 1.0
    QML_FILES
        qml/Main.qml
    SOURCES
        src/mpvitem.h
        src/mpvitem.cpp
)

target_include_directories(chopstick PRIVATE src)

target_link_libraries(chopstick PRIVATE
    Qt6::Quick
    PkgConfig::MPV
)
