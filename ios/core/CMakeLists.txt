# The iPhone app's C side: pd_ios.c over the 3DS port's session (3ds/host) and companion (3ds/core) on mGBA, the same
# sources the headless simulator builds (3ds/desktop/sim/CMakeLists.txt). On iOS this makes static libraries that the
# Xcode project links (ios/build_core.sh merges them into one); elsewhere it also builds pd_ios_smoke, which runs the
# bridge headless on the diagnostic ROMs (linux/make_diagnostic.py) and writes what the two panes would show.
cmake_minimum_required(VERSION 3.18)
project(pokedaisy_ios C CXX)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
get_filename_component(REPO "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

foreach(off BUILD_SHARED BUILD_GL BUILD_GLES2 BUILD_GLES3 BUILD_PERF BUILD_TEST BUILD_SUITE BUILD_LIBRETRO BUILD_PYTHON
            USE_DEBUGGERS USE_GDB_STUB USE_EDITLINE USE_FFMPEG USE_DISCORD_RPC USE_LZMA USE_LUA USE_ELF USE_SQLITE3
            USE_LIBZIP USE_MINIZIP USE_PNG USE_ZLIB BUILD_LTO USE_EPOXY USE_FREETYPE)
    set(${off} OFF CACHE BOOL "" FORCE)
endforeach()
foreach(on BUILD_STATIC DISABLE_FRONTENDS DISABLE_DEPS M_CORE_GBA M_CORE_GB SKIP_INSTALL_ALL)
    set(${on} ON CACHE BOOL "" FORCE)
endforeach()
set(SKIP_LIBRARY OFF CACHE BOOL "" FORCE)
add_subdirectory("${REPO}/third_party/mgba" mgba EXCLUDE_FROM_ALL)

# The session's dispatch (3ds/emu/pd_dispatch.c) picks armGBA, gpSP or mGBA per game. On iOS every game runs on mGBA's
# interpreter (no executable memory without JIT), so the other two are stubs that are never the running core.
set(PD_CORE_GLUE "${REPO}/3ds/emu/pd_dispatch.c" "${CMAKE_CURRENT_SOURCE_DIR}/pd_ios_nocores.c")
find_package(Threads REQUIRED)

file(GLOB CORE_SOURCES "${REPO}/3ds/core/*.c")
file(GLOB HOST_SOURCES "${REPO}/3ds/host/*.c")
set(APP_CPP "${REPO}/app/src/main/cpp")
add_library(pokedaisy_ios STATIC pd_ios.c ${HOST_SOURCES} ${CORE_SOURCES}
    "${APP_CPP}/pk_host.c" "${APP_CPP}/pk_call.c" "${APP_CPP}/pk_cheats.c" "${APP_CPP}/pk_gb_field.c" "${APP_CPP}/pk_gb_audio.c"
    "${APP_CPP}/pk_wide.c" "${APP_CPP}/pk_wide_gb.c" "${APP_CPP}/pk_flight.c"
    "${REPO}/linux/fly.c" "${REPO}/linux/flash.c" "${REPO}/linux/flight.c" "${REPO}/linux/tm_teach.c" "${REPO}/linux/field_items.c"
    "${REPO}/linux/gb_field.c" "${REPO}/linux/wild.c" "${REPO}/linux/hud.c" "${REPO}/linux/quick_menu.c"
    ${PD_CORE_GLUE})
target_include_directories(pokedaisy_ios PRIVATE "${REPO}/third_party/mgba/include" "${REPO}/third_party/mgba/src"
    "${CMAKE_CURRENT_BINARY_DIR}/mgba/include" "${REPO}/3ds/core" "${REPO}/linux" "${APP_CPP}")
target_include_directories(pokedaisy_ios PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(pokedaisy_ios PRIVATE M_CORE_GBA M_CORE_GB BUILD_STATIC PK_WIDE_CACHE
    PK_WIDE_MAX_VIEW_W=400 PK_WIDE_MAX_VIEW_H=240)
target_compile_options(pokedaisy_ios PRIVATE -std=gnu11 -O2 -Wall -Wno-unused-parameter -Wno-unused-function)
target_link_libraries(pokedaisy_ios PUBLIC mgba Threads::Threads)
# The app's pk_call.c / pk_host.c / pk_cheats.c entry points built as *_mgba, for pd_dispatch.c (3ds/emu/armgba.cmake's
# pd_mgba_renames, which this build doesn't include).
set_source_files_properties("${APP_CPP}/pk_call.c" PROPERTIES COMPILE_DEFINITIONS
    "pk_call=pk_call_mgba;pk_call_safe=pk_call_safe_mgba;pk_call_set_cap=pk_call_set_cap_mgba;pk_rest_note=pk_rest_note_mgba;pk_rest_reset=pk_rest_reset_mgba")
set_source_files_properties("${APP_CPP}/pk_host.c" PROPERTIES COMPILE_DEFINITIONS
    "pk_save_dirty=pk_save_dirty_mgba;pk_finish_save=pk_finish_save_mgba;pk_heal_rtc=pk_heal_rtc_mgba")
set_source_files_properties("${APP_CPP}/pk_cheats.c" PROPERTIES COMPILE_DEFINITIONS
    "pk_cheats_clear=pk_cheats_clear_mgba;pk_cheats_apply=pk_cheats_apply_mgba")

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_executable(pd_ios_smoke test/pd_ios_smoke.c "${REPO}/3ds/desktop/pd_png.c")
    target_include_directories(pd_ios_smoke PRIVATE "${REPO}/3ds/desktop")
    target_link_libraries(pd_ios_smoke pokedaisy_ios m)
endif()
