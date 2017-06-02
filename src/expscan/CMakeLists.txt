project(expscan)
cmake_minimum_required(VERSION 2.8.7)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

find_package(BISON 2.7 REQUIRED)
find_package(FLEX 2.5 REQUIRED)

set(EXPRESS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../express")
set(ARGPARSE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../auxlibs/argparse")

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
BISON_TARGET(P1Parser "${EXPRESS_SOURCE_DIR}/p1parser.y" "${CMAKE_CURRENT_BINARY_DIR}/p1parser.c"
             DEFINES_FILE "${CMAKE_CURRENT_BINARY_DIR}/p1parser.h"
             COMPILE_FLAGS "--debug --report=states --report-file=${CMAKE_CURRENT_BINARY_DIR}/p1parser.out"
)

FLEX_TARGET(P1Lexer "${EXPRESS_SOURCE_DIR}/p1lexer.l" "${CMAKE_CURRENT_BINARY_DIR}/p1lexer.c"
            DEFINES_FILE "${CMAKE_CURRENT_BINARY_DIR}/p1lexer.h"
            COMPILE_FLAGS "--debug"
)
    
else()
BISON_TARGET(P1Parser "${EXPRESS_SOURCE_DIR}/p1parser.y" "${CMAKE_CURRENT_BINARY_DIR}/p1parser.c"
             DEFINES_FILE "${CMAKE_CURRENT_BINARY_DIR}/p1parser.h"
)

FLEX_TARGET(P1Lexer "${EXPRESS_SOURCE_DIR}/p1lexer.l" "${CMAKE_CURRENT_BINARY_DIR}/p1lexer.c"
            DEFINES_FILE "${CMAKE_CURRENT_BINARY_DIR}/p1lexer.h"
)
endif()


ADD_FLEX_BISON_DEPENDENCY(P1Lexer P1Parser)

include_directories(${CMAKE_CURRENT_BINARY_DIR} ${ARGPARSE_SOURCE_DIR})
add_executable(expscan expscan.c ${BISON_P1Parser_OUTPUTS} ${FLEX_P1Lexer_OUTPUTS} ${ARGPARSE_SOURCE_DIR}/argparse.c)
target_link_libraries(expscan m)

