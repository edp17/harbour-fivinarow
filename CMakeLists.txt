cmake_minimum_required(VERSION 3.5)
project(harbour-fivinarow LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SAILFISHAPP REQUIRED sailfishapp)
find_package(Qt5 REQUIRED COMPONENTS Concurrent Core LinguistTools Qml Quick)

include_directories(${SAILFISHAPP_INCLUDE_DIRS})
link_directories(${SAILFISHAPP_LIBRARY_DIRS})
add_definitions(${SAILFISHAPP_CFLAGS_OTHER})

add_executable(harbour-fivinarow
    main.cpp
    src/GomokuAI.cpp
    src/GomokuAI.h
    src/GomokuCore.cpp
    src/GomokuCore.h
)

target_include_directories(harbour-fivinarow PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

set(FIVINAROW_TRANSLATIONS
    translations/harbour-fivinarow-hu.ts
)
qt5_add_translation(FIVINAROW_QM_FILES ${FIVINAROW_TRANSLATIONS})
add_custom_target(harbour-fivinarow-translations ALL DEPENDS ${FIVINAROW_QM_FILES})
add_dependencies(harbour-fivinarow harbour-fivinarow-translations)

target_link_libraries(harbour-fivinarow
    ${SAILFISHAPP_LIBRARIES}
    Qt5::Concurrent
    Qt5::Core
    Qt5::Qml
    Qt5::Quick
)
