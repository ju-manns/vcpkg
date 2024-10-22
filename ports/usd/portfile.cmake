# Don't file if the bin folder exists. We need exe and custom files.
set(VCPKG_POLICY_EMPTY_PACKAGE enabled)

string(REGEX REPLACE "^([0-9]+)[.]([0-9])\$" "\\1.0\\2" USD_VERSION "${VERSION}")

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO PixarAnimationStudios/OpenUSD
    REF "v${USD_VERSION}"
    SHA512 7d4404980579c4de3c155386184ca9d2eb96756ef6e090611bae7b4c21ad942c649f73a39b74ad84d0151ce6b9236c4b6c0c555e8e36fdd86304079e1c2e5cbe
    HEAD_REF master
    PATCHES
        fix_build-location.patch
)

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        monolithic          VCPKG_FEATURE_MONOLITHIC
        imaging             VCPKG_FEATURE_IMAGING
        commandline-tools   VCPKG_FEATURE_COMMANDLINE_TOOLS
        embree-support      VCPKG_FEATURE_EMBREE_SUPPORT
)

if (VCPKG_FEATURE_MONOLITHIC)
    set(USD_BUILD_MONOLITHIC ON)
else()
    set(USD_BUILD_MONOLITHIC OFF)
endif()

if (VCPKG_FEATURE_IMAGING)
    set(USD_BUILD_IMAGING ON)
    # install pip and then pyside6
    execute_process(
        COMMAND "${CURRENT_INSTALLED_DIR}/tools/python3/python3" -m ensurepip
        RESULT_VARIABLE ensurepip_result
    )
    if (NOT ensurepip_result EQUAL 0)
        message(FATAL_ERROR "Failed to install pip")
    endif()
    execute_process(
        COMMAND "${CURRENT_INSTALLED_DIR}/tools/python3/python3" -m pip install --upgrade pip
        RESULT_VARIABLE pyside6_result
    )
    execute_process(
        COMMAND "${CURRENT_INSTALLED_DIR}/tools/python3/python3" -m pip install PySide6 PyOpenGL jinja2
        RESULT_VARIABLE pyside6_result
    )
else()
    set(USD_BUILD_IMAGING OFF)
endif()

if (VCPKG_FEATURE_COMMANDLINE_TOOLS)
    set(USD_BUILD_TOOLS ON)
else()
    set(USD_BUILD_TOOLS OFF)
endif()

if(VCPKG_FEATURE_EMBREE_SUPPORT)
    set(USD_BUILD_EMBREE_PLUGIN ON)
else()
    set(USD_BUILD_EMBREE_PLUGIN OFF)
endif()

vcpkg_cmake_configure(
    SOURCE_PATH ${SOURCE_PATH}
    OPTIONS
        -DPXR_BUILD_ALEMBIC_PLUGIN:BOOL=OFF
        -DPXR_BUILD_EMBREE_PLUGIN:BOOL=${USD_BUILD_EMBREE_PLUGIN}
        -DPXR_BUILD_IMAGING:BOOL=${USD_BUILD_IMAGING}
        -DPXR_BUILD_MONOLITHIC:BOOL=${USD_BUILD_MONOLITHIC}
        -DPXR_BUILD_TESTS:BOOL=OFF
        -DPXR_BUILD_USD_IMAGING:BOOL=${USD_BUILD_IMAGING}
        -DPXR_ENABLE_PYTHON_SUPPORT:BOOL=${USD_BUILD_IMAGING}
        -DPXR_BUILD_EXAMPLES:BOOL=OFF
        -DPXR_BUILD_TUTORIALS:BOOL=OFF
        -DPXR_BUILD_USD_TOOLS:BOOL=${USD_BUILD_TOOLS}
        -DPXR_ENABLE_GL_SUPPORT:BOOL=ON
)

vcpkg_cmake_install()

# The CMake files installation is not standard in USD and will install pxrConfig.cmake in the prefix root and
# pxrTargets.cmake in "cmake" so we are moving pxrConfig.cmake in the same folder and patch the path to pxrTargets.cmake
vcpkg_replace_string(${CURRENT_PACKAGES_DIR}/pxrConfig.cmake "/cmake/pxrTargets.cmake" "/pxrTargets.cmake")
vcpkg_replace_string(${CURRENT_PACKAGES_DIR}/pxrConfig.cmake "PXR_CMAKE_DIR}/include" "VCPKG_IMPORT_PREFIX}/include")

file(
    RENAME
        "${CURRENT_PACKAGES_DIR}/pxrConfig.cmake"
        "${CURRENT_PACKAGES_DIR}/cmake/pxrConfig.cmake")

vcpkg_cmake_config_fixup(CONFIG_PATH cmake PACKAGE_NAME pxr)

# Remove duplicates in debug folder
file(REMOVE ${CURRENT_PACKAGES_DIR}/debug/pxrConfig.cmake)
file(REMOVE_RECURSE ${CURRENT_PACKAGES_DIR}/debug/include)

# Handle copyright
vcpkg_install_copyright(FILE_LIST ${SOURCE_PATH}/LICENSE.txt)

if(VCPKG_TARGET_IS_WINDOWS)
    # Move all dlls to bin
    file(GLOB RELEASE_DLL ${CURRENT_PACKAGES_DIR}/lib/*.dll)
    file(MAKE_DIRECTORY ${CURRENT_PACKAGES_DIR}/bin)
    file(GLOB DEBUG_DLL ${CURRENT_PACKAGES_DIR}/debug/lib/*.dll)
    file(MAKE_DIRECTORY ${CURRENT_PACKAGES_DIR}/debug/bin)
    foreach(CURRENT_FROM ${RELEASE_DLL} ${DEBUG_DLL})
        string(REPLACE "/lib/" "/bin/" CURRENT_TO ${CURRENT_FROM})
        file(RENAME ${CURRENT_FROM} ${CURRENT_TO})
    endforeach()

    vcpkg_copy_pdbs()

    function(file_replace_regex filename match_string replace_string)
        file(READ ${filename} _contents)
        string(REGEX REPLACE "${match_string}" "${replace_string}" _contents "${_contents}")
        file(WRITE ${filename} "${_contents}")
    endfunction()

    # fix dll path for cmake
    file_replace_regex(${CURRENT_PACKAGES_DIR}/share/pxr/pxrTargets-debug.cmake "debug/lib/([a-zA-Z0-9_]+)\\.dll" "debug/bin/\\1.dll")
    file_replace_regex(${CURRENT_PACKAGES_DIR}/share/pxr/pxrTargets-release.cmake "lib/([a-zA-Z0-9_]+)\\.dll" "bin/\\1.dll")

    # fix plugInfo.json for runtime
    file(GLOB_RECURSE PLUGINFO_FILES ${CURRENT_PACKAGES_DIR}/lib/usd/*/resources/plugInfo.json)
    file(GLOB_RECURSE PLUGINFO_FILES_DEBUG ${CURRENT_PACKAGES_DIR}/debug/lib/usd/*/resources/plugInfo.json)
    foreach(PLUGINFO ${PLUGINFO_FILES} ${PLUGINFO_FILES_DEBUG})
        file_replace_regex(${PLUGINFO} [=["LibraryPath": "../../([a-zA-Z0-9_]+).dll"]=] [=["LibraryPath": "../../../bin/\1.dll"]=])
    endforeach()
endif()
