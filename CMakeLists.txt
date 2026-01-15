cmake_minimum_required(VERSION 3.5)
project(harbour-fivinarow LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SAILFISHAPP REQUIRED sailfishapp)
find_package(Qt5 REQUIRED COMPONENTS Qml Quick)

include_directories(${SAILFISHAPP_INCLUDE_DIRS})
link_directories(${SAILFISHAPP_LIBRARY_DIRS})
add_definitions(${SAILFISHAPP_CFLAGS_OTHER})

add_executable(harbour-fivinarow main.cpp)

target_link_libraries(harbour-fivinarow
    ${SAILFISHAPP_LIBRARIES}
    Qt5::Qml
    Qt5::Quick
)