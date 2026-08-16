cmake_minimum_required(VERSION 3.22.1)

project(police_dog_inference LANGUAGES CXX)

add_library(
    police_dog_inference
    SHARED
    action_classifier.cpp
    dog_detector.cpp
    inference_engine.cpp
    native_bridge.cpp
    pose_estimator.cpp
    postprocess.cpp
)

target_compile_features(police_dog_inference PRIVATE cxx_std_17)
target_include_directories(police_dog_inference PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

find_library(android-lib android REQUIRED)
find_library(jnigraphics-lib jnigraphics REQUIRED)
find_library(log-lib log REQUIRED)

set(NCNN_PACKAGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ncnn/${ANDROID_ABI}")
if(NOT EXISTS "${NCNN_PACKAGE_ROOT}/lib/cmake/ncnn/ncnnConfig.cmake")
    message(FATAL_ERROR
        "ncnn Android package is missing for ${ANDROID_ABI}. "
        "Run tooling/setup_ncnn.ps1 from the repository root before building.")
endif()
find_package(ncnn 20260526 REQUIRED CONFIG
    PATHS "${NCNN_PACKAGE_ROOT}/lib/cmake/ncnn"
    NO_DEFAULT_PATH)

target_link_libraries(
    police_dog_inference
    PRIVATE
    ${android-lib}
    ${jnigraphics-lib}
    ${log-lib}
    ncnn
)
