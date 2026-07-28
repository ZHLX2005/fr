cmake_minimum_required(VERSION 3.22.1)

project(metronome)

add_library(
    metronome
    SHARED
    metronome.cpp
    metronome.h
)

find_package(oboe REQUIRED CONFIG)

target_link_libraries(
    metronome
    oboe::oboe
    log
)
