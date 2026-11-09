# android/app/src/main/cpp/CMakeLists.txt
# 📱 جسر JNI لخادم واتساب على الهاتف. libnode.so (nodejs-mobile) يُنزَّل بـ tool\wa_android_setup.bat
# إلى android/app/libnode — بدونه لا يُبنى هذا الجزء أصلاً (build.gradle.kts).
cmake_minimum_required(VERSION 3.18.1)
project(wanode CXX)

set(LIBNODE_DIR ${CMAKE_SOURCE_DIR}/../../../libnode)

add_library(wanode SHARED native-lib.cpp)
set_target_properties(wanode PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
target_include_directories(wanode PRIVATE ${LIBNODE_DIR}/include/node)

add_library(libnode SHARED IMPORTED)
set_target_properties(libnode PROPERTIES IMPORTED_LOCATION ${LIBNODE_DIR}/bin/${ANDROID_ABI}/libnode.so)

find_library(log-lib log)
target_link_libraries(wanode libnode ${log-lib})
