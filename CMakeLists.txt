cmake_minimum_required(VERSION 3.20)

if(DEFINED ENV{VCPKG_ROOT} AND NOT DEFINED CMAKE_TOOLCHAIN_FILE)
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
        CACHE STRING "")
endif()
# Name of the project
project (pc-ble-driver-py)
if(WIN32)
    # Hack for building with Python limited API
    # scikit-build links with python3x.lib, but setting PY_LIMITED_API will request python3.lib through a #pragma comment(lib,"python3.lib") in pyconfig.h
    # since only the .lib path is passed (and not a library search dir), the build will fail because the linker won't know where to find python3.lib
    cmake_path(REPLACE_FILENAME PYTHON_LIBRARY python3.lib)
endif()
# PYTHON_LIBRARY is changed by the PythonExtensions package, so a different variable is required to keep the original user flag
set(PYTHON_LIBRARY_FROM_USER_FLAGS "${PYTHON_LIBRARY}")

# CRITICAL: If PYTHON_EXECUTABLE is provided, determine the correct Python library from it
# This overrides PYTHON_LIBRARY_FROM_USER_FLAGS which might point to the wrong Python version
# (e.g., Python 3.13 when building for Python 3.8)
if(PYTHON_EXECUTABLE AND APPLE)
    execute_process(
        COMMAND ${PYTHON_EXECUTABLE} -c "import sysconfig; libdir = sysconfig.get_config_var('LIBDIR'); libfile = sysconfig.get_config_var('LIBRARY'); libpath = f'{libdir}/{libfile}' if libfile else libdir; print(libpath)"
        OUTPUT_VARIABLE PYTHON_LIB_FROM_EXE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(PYTHON_LIB_FROM_EXE AND EXISTS "${PYTHON_LIB_FROM_EXE}")
        # Override PYTHON_LIBRARY_FROM_USER_FLAGS with the correct library from PYTHON_EXECUTABLE
        set(PYTHON_LIBRARY_FROM_USER_FLAGS "${PYTHON_LIB_FROM_EXE}")
        message(STATUS "Overriding PYTHON_LIBRARY_FROM_USER_FLAGS with library from PYTHON_EXECUTABLE: ${PYTHON_LIBRARY_FROM_USER_FLAGS}")
    endif()
endif()

# Use non-debug version of python, even when building a debug version 
add_definitions(-DSWIG_PYTHON_INTERPRETER_NO_DEBUG)
message(VERBOSE "CMAKE executable path ${CMAKE_COMMAND}")
message(VERBOSE "CMAKE generator name: ${CMAKE_GENERATOR}")
message(VERBOSE "CMAKE generator path ${CMAKE_MAKE_PROGRAM}")
message(VERBOSE "CMAKE_MODULE_PATH before most other commands : ${CMAKE_MODULE_PATH}")
message(VERBOSE "The include directories are (before PythonExtensions): ${PYTHON_INCLUDE_DIR}")
find_package(PythonExtensions REQUIRED)
message(VERBOSE "The include directories are (after PythonExtensions): ${PYTHON_INCLUDE_DIR}")
message(VERBOSE "PythonExtension parameters")
message(VERBOSE "PYTHON_PREFIX                    :   ${PYTHON_PREFIX}                     ")
message(VERBOSE "PYTHON_SITE_PACKAGES_DIR         :   ${PYTHON_SITE_PACKAGES_DIR}          ")
message(VERBOSE "PYTHON_RELATIVE_SITE_PACKAGES_DIR:   ${PYTHON_RELATIVE_SITE_PACKAGES_DIR} ")
message(VERBOSE "PYTHON_SEPARATOR                 :   ${PYTHON_SEPARATOR}                  ")
message(VERBOSE "PYTHON_PATH_SEPARATOR            :   ${PYTHON_PATH_SEPARATOR}             ")
message(VERBOSE "PYTHON_EXTENSION_MODULE_SUFFIX   :   ${PYTHON_EXTENSION_MODULE_SUFFIX}    ")
message(VERBOSE "PYTHON_EXTENSION_MODULE_SUFFIX   :   ${PYTHON_EXTENSION_MODULE_SUFFIX}    ")
message(VERBOSE "CMAKE_MODULE_PATH after most other commands : ${CMAKE_MODULE_PATH}")

if(WIN32)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_hypot=hypot")
endif()

# Configure rpath for macOS to support different Python installations (Homebrew, pyenv, framework)
if(APPLE)
    set(CMAKE_MACOSX_RPATH ON)
    # Initialize CMAKE_INSTALL_RPATH
    set(CMAKE_INSTALL_RPATH "")
    # Get Python library directory for rpath
    if(PYTHON_LIBRARY)
        get_filename_component(PYTHON_LIBRARY_DIR ${PYTHON_LIBRARY} DIRECTORY)
        # Add Python library directory to install rpath
        set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_RPATH};${PYTHON_LIBRARY_DIR}")
        # Also add @loader_path for relative loading
        set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_RPATH};@loader_path")
        message(VERBOSE "Python library directory for rpath: ${PYTHON_LIBRARY_DIR}")
    endif()
    # Add vcpkg library path to rpath if available (for nrf-ble-driver dependencies)
    # Check both CMake variable and environment variable
    if(CMAKE_PREFIX_PATH)
        set(VCPKG_PREFIX "${CMAKE_PREFIX_PATH}")
    elseif(DEFINED ENV{CMAKE_PREFIX_PATH})
        set(VCPKG_PREFIX "$ENV{CMAKE_PREFIX_PATH}")
    elseif(DEFINED ENV{VCPKG_ROOT})
        # Fallback: derive from VCPKG_ROOT
        set(VCPKG_PREFIX "$ENV{VCPKG_ROOT}/installed/arm64-osx")
    endif()
    
    if(VCPKG_PREFIX)
        # VCPKG_PREFIX might be something like /path/to/vcpkg/installed/arm64-osx
        # We need the lib subdirectory
        set(VCPKG_LIB_DIR "${VCPKG_PREFIX}/lib")
        if(EXISTS "${VCPKG_LIB_DIR}")
            if(CMAKE_INSTALL_RPATH)
                set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_RPATH};${VCPKG_LIB_DIR}")
            else()
                set(CMAKE_INSTALL_RPATH "${VCPKG_LIB_DIR}")
            endif()
            message(STATUS "Added vcpkg library directory to rpath: ${VCPKG_LIB_DIR}")
        else()
            message(VERBOSE "VCPKG_LIB_DIR not found: ${VCPKG_LIB_DIR}")
        endif()
    else()
        message(VERBOSE "CMAKE_PREFIX_PATH not set, skipping vcpkg rpath")
    endif()
    # Enable @rpath in build rpath as well
    set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
    message(VERBOSE "CMAKE_INSTALL_RPATH: ${CMAKE_INSTALL_RPATH}")
endif()

set(PC_BLE_DRIVER_PY_OUTDIR ${CMAKE_BINARY_DIR}/outdir)
set(NRF_BLE_DRIVER_VERSION "4.1.100")

# There is no reason to compile more than two SoftDevice API versions
# The Python module only supports one SoftDevice API
# version for NRF51 and one for NRF52
set(SD_API_VERS "2;5")

# SWIG
find_package(SWIG 4.2.0 REQUIRED)
include(${SWIG_USE_FILE})

# nrf-ble-driver
# Try to find with exact version first, fall back to any version if using vcpkg
# Note: vcpkg may install a different version (e.g., 4.1.4 instead of 4.1.100)
# So we accept any version when using vcpkg
# Check multiple ways to detect vcpkg usage:
# 1. VCPKG_ROOT environment variable
# 2. CMAKE_TOOLCHAIN_FILE pointing to vcpkg
# 3. CMAKE_PREFIX_PATH pointing to vcpkg installed directory
set(USING_VCPKG FALSE)
if(DEFINED ENV{VCPKG_ROOT} OR DEFINED VCPKG_ROOT)
    set(USING_VCPKG TRUE)
    message(STATUS "Detected vcpkg via VCPKG_ROOT")
elseif(CMAKE_TOOLCHAIN_FILE AND CMAKE_TOOLCHAIN_FILE MATCHES "vcpkg")
    set(USING_VCPKG TRUE)
    message(STATUS "Detected vcpkg via CMAKE_TOOLCHAIN_FILE: ${CMAKE_TOOLCHAIN_FILE}")
elseif(CMAKE_PREFIX_PATH)
    foreach(prefix_path ${CMAKE_PREFIX_PATH})
        if(prefix_path MATCHES "vcpkg" OR prefix_path MATCHES "installed")
            set(USING_VCPKG TRUE)
            message(STATUS "Detected vcpkg via CMAKE_PREFIX_PATH: ${prefix_path}")
            break()
        endif()
    endforeach()
endif()

if(USING_VCPKG)
    # When using vcpkg, accept any version (vcpkg may have a different version)
    # Don't specify version to allow any installed version
    find_package(nrf-ble-driver CONFIG REQUIRED)
    # Log the version found for debugging
    if(nrf-ble-driver_VERSION)
        message(STATUS "Found nrf-ble-driver version: ${nrf-ble-driver_VERSION} (via vcpkg)")
    else()
        message(STATUS "Found nrf-ble-driver (version unknown, via vcpkg)")
    endif()
else()
    # When not using vcpkg, require exact version
    message(STATUS "Not using vcpkg, requiring exact nrf-ble-driver version: ${NRF_BLE_DRIVER_VERSION}")
    find_package(nrf-ble-driver ${NRF_BLE_DRIVER_VERSION} EXACT CONFIG REQUIRED)
endif()

# PYTHON_INCLUDE_DIR provided by scikit-build
include_directories(${PYTHON_INCLUDE_DIR})
message(VERBOSE "The Python include directories are: ${PYTHON_INCLUDE_DIR}")

set(SWIG_I_FILE ${CMAKE_CURRENT_LIST_DIR}/swig/pc_ble_driver.i.in)

# Avoid warning on Windows
if(WIN32)
    add_definitions(-DHAVE_ROUND)
endif()

# Copy .i file into N variant files
foreach(SD_API_VER ${SD_API_VERS})
    set(PYTHON_MODULE_${SD_API_VER} nrf_ble_driver_sd_api_v${SD_API_VER})
    # Copy SWIG-generated wrapper
    set(SWIG_I_FILE_${SD_API_VER} ${PC_BLE_DRIVER_PY_OUTDIR}/${PYTHON_MODULE_${SD_API_VER}}.i)
    set(SWIG_MODULE_NAME ${PYTHON_MODULE_${SD_API_VER}})
    # Use release lib of Python even when building with DEBUG
    add_definitions(-DSWIG_PYTHON_INTERPRETER_NO_DEBUG)
    configure_file(${SWIG_I_FILE} ${SWIG_I_FILE_${SD_API_VER}})
    set_property(SOURCE ${SWIG_I_FILE_${SD_API_VER}} APPEND PROPERTY SWIG_FLAGS "-threads")
    set_property(SOURCE ${SWIG_I_FILE_${SD_API_VER}} APPEND PROPERTY SWIG_FLAGS "-Wall")
    # Builtin is not supported in the customized wrappers for callbacks yet
    # set_property(SOURCE ${SWIG_I_FILE_${SD_API_VER}} APPEND PROPERTY SWIG_FLAGS "-builtin")
endforeach()

set(NRF_BLE_DRIVER_LINKAGE_TYPE "static")

if(WIN32)
    set(NRF_BLE_DRIVER_LINKAGE_TYPE "shared")
endif()

foreach(SD_API_VER ${SD_API_VERS})
    set_property(
        SOURCE ${SWIG_I_FILE_${SD_API_VER}}
        # C++ must be off since SWIG C++ parser does not handle nested structs/classes
        # Warning 312. Unnamed nested class not currently supported (ignored)
        PROPERTY CPLUSPLUS OFF
    )

    set_property(
        SOURCE ${SWIG_I_FILE_${SD_API_VER}}
        PROPERTY INCLUDE_DIRECTORIES ${nrf-ble-driver_SD_API_V${SD_API_VER}_INCLUDE_DIR} ${PC_BLE_DRIVER_PY_OUTDIR}
    )

    set_property(
        SOURCE ${SWIG_I_FILE_${SD_API_VER}}
        PROPERTY COMPILE_DEFINITIONS "NRF_SD_BLE_API_VERSION=${SD_API_VER}" "SUPPRESS_INLINE_IMPLEMENTATION" "PC_BLE_DRIVER_STATIC"
    )

    swig_add_library(
        ${PYTHON_MODULE_${SD_API_VER}}
        TYPE SHARED
        LANGUAGE python
        SOURCES ${SWIG_I_FILE_${SD_API_VER}}
        OUTPUT_DIR ${PC_BLE_DRIVER_PY_OUTDIR}
    )

    set_property(TARGET ${PYTHON_MODULE_${SD_API_VER}} PROPERTY CXX_STANDARD 14)
    set_property(TARGET ${PYTHON_MODULE_${SD_API_VER}} PROPERTY CXX_STANDARD_REQUIRED TRUE)

    set_source_files_properties(${PC_BLE_DRIVER_PY_OUTDIR}/${PYTHON_MODULE_${SD_API_VER}}PYTHON_wrap.c PROPERTIES LANGUAGE CXX)

    if(MSFT_NON_STANDARD_COMPILER)
        target_include_directories(${PYTHON_MODULE_${SD_API_VER}} PRIVATE ${PC_BLE_DRIVER_PY_OUTDIR})
    endif()
    
    # CRITICAL: For SWIG 4.4.0 compatibility, force include moduleobject.h in generated wrapper code
    # SWIG 4.4.0 generates code using Py_mod_exec, PyModuleDef_Slot, PyModuleDef_Init
    # These require moduleobject.h. Use -include compiler flag to force it at compile time.
    if(APPLE)
        # Find moduleobject.h - it should be in PYTHON_INCLUDE_DIR
        find_file(MODULEOBJECT_H moduleobject.h 
            PATHS ${PYTHON_INCLUDE_DIR} 
            NO_DEFAULT_PATH
            NO_CMAKE_FIND_ROOT_PATH
        )
        if(MODULEOBJECT_H)
            # Force include moduleobject.h in the generated wrapper code compilation
            target_compile_options(${PYTHON_MODULE_${SD_API_VER}} PRIVATE "-include${MODULEOBJECT_H}")
            message(STATUS "Added -include for moduleobject.h: ${MODULEOBJECT_H}")
        else()
            # Fallback: try to construct path
            set(MODULEOBJECT_H_FALLBACK "${PYTHON_INCLUDE_DIR}/moduleobject.h")
            if(EXISTS "${MODULEOBJECT_H_FALLBACK}")
                target_compile_options(${PYTHON_MODULE_${SD_API_VER}} PRIVATE "-include${MODULEOBJECT_H_FALLBACK}")
                message(STATUS "Added -include for moduleobject.h (fallback): ${MODULEOBJECT_H_FALLBACK}")
            else()
                message(WARNING "Could not find moduleobject.h in ${PYTHON_INCLUDE_DIR} - SWIG 4.4.0 builds may fail")
            endif()
        endif()
    endif()

    set(LINK_LIBRARIES nrf::nrf_ble_driver_sd_api_v${SD_API_VER}_${NRF_BLE_DRIVER_LINKAGE_TYPE})
    if (WIN32 OR APPLE)
        set(LINK_LIBRARIES ${LINK_LIBRARIES} ${PYTHON_LIBRARY_FROM_USER_FLAGS})
        message(VERBOSE "Python library from the user flags is : ${PYTHON_LIBRARY_FROM_USER_FLAGS}")
    endif()

    message(VERBOSE STATUS "LINK_LIBRARIES are ${LINK_LIBRARIES}")

    target_link_libraries(${PYTHON_MODULE_${SD_API_VER}} PRIVATE ${LINK_LIBRARIES})
    
    # For macOS, fix the Python library path to use @rpath after linking
    if(APPLE)
        # Determine Python library path from PYTHON_EXECUTABLE to ensure we use the correct Python
        # This is critical because PYTHON_LIBRARY_FROM_USER_FLAGS might point to the wrong Python version
        set(PYTHON_LIB_TO_FIX "")
        set(PYTHON_LIB_RPATH_NAME "")
        set(PYTHON_FRAMEWORK_PATH "")
        
        if(PYTHON_EXECUTABLE)
            # Use Python to determine its own library path and version
            execute_process(
                COMMAND ${PYTHON_EXECUTABLE} -c "import sysconfig; import sys; libdir = sysconfig.get_config_var('LIBDIR'); libfile = sysconfig.get_config_var('LIBRARY'); libpath = f'{libdir}/{libfile}' if libfile else libdir; print(libpath); print(f'{sys.version_info.major}.{sys.version_info.minor}')"
                OUTPUT_VARIABLE PYTHON_LIB_INFO
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            if(PYTHON_LIB_INFO)
                # Parse output: first line is library path, second line is version
                string(REPLACE "\n" ";" PYTHON_LIB_INFO_LIST "${PYTHON_LIB_INFO}")
                list(GET PYTHON_LIB_INFO_LIST 0 PYTHON_LIB_PATH_FROM_EXE)
                list(GET PYTHON_LIB_INFO_LIST 1 PYTHON_VERSION_MAJOR_MINOR)
                
                if(EXISTS "${PYTHON_LIB_PATH_FROM_EXE}")
                    set(PYTHON_LIB_TO_FIX "${PYTHON_LIB_PATH_FROM_EXE}")
                    # Determine @rpath name based on library type
                    get_filename_component(PYTHON_LIB_NAME ${PYTHON_LIB_PATH_FROM_EXE} NAME)
                    if(PYTHON_LIB_NAME MATCHES "libpython([0-9]+\\.[0-9]+)\\.dylib")
                        set(PYTHON_LIB_RPATH_NAME "@rpath/libpython${PYTHON_VERSION_MAJOR_MINOR}.dylib")
                    elseif(PYTHON_LIB_NAME STREQUAL "Python" OR PYTHON_LIB_PATH_FROM_EXE MATCHES "Python.framework")
                        set(PYTHON_LIB_RPATH_NAME "@rpath/Python")
                        # Extract framework path
                        string(REGEX REPLACE "/lib/.*" "/Python" PYTHON_FRAMEWORK_PATH "${PYTHON_LIB_PATH_FROM_EXE}")
                    else()
                        set(PYTHON_LIB_RPATH_NAME "@rpath/${PYTHON_LIB_NAME}")
                    endif()
                    message(STATUS "Determined Python library from PYTHON_EXECUTABLE: ${PYTHON_LIB_TO_FIX} -> ${PYTHON_LIB_RPATH_NAME}")
                endif()
            endif()
        endif()
        
        # Fallback to PYTHON_LIBRARY_FROM_USER_FLAGS if we couldn't determine from PYTHON_EXECUTABLE
        if(NOT PYTHON_LIB_TO_FIX AND PYTHON_LIBRARY_FROM_USER_FLAGS)
            set(PYTHON_LIB_TO_FIX "${PYTHON_LIBRARY_FROM_USER_FLAGS}")
            get_filename_component(PYTHON_LIB_NAME ${PYTHON_LIBRARY_FROM_USER_FLAGS} NAME)
            get_filename_component(PYTHON_LIB_DIR ${PYTHON_LIBRARY_FROM_USER_FLAGS} DIRECTORY)
            
            if(PYTHON_LIB_NAME MATCHES "libpython([0-9]+\\.[0-9]+)\\.dylib")
                set(PYTHON_VERSION_MAJOR_MINOR ${CMAKE_MATCH_1})
                set(PYTHON_LIB_RPATH_NAME "@rpath/libpython${PYTHON_VERSION_MAJOR_MINOR}.dylib")
            elseif(PYTHON_LIB_NAME STREQUAL "Python")
                set(PYTHON_LIB_RPATH_NAME "@rpath/Python")
            else()
                set(PYTHON_LIB_RPATH_NAME "@rpath/${PYTHON_LIB_NAME}")
            endif()
            
            if(PYTHON_LIB_DIR MATCHES "Python.framework")
                string(REGEX REPLACE "/lib/.*" "/Python" PYTHON_FRAMEWORK_PATH "${PYTHON_LIBRARY_FROM_USER_FLAGS}")
            endif()
            message(STATUS "Using Python library from PYTHON_LIBRARY_FROM_USER_FLAGS: ${PYTHON_LIB_TO_FIX} -> ${PYTHON_LIB_RPATH_NAME}")
        endif()
        
        if(PYTHON_LIB_TO_FIX AND PYTHON_LIB_RPATH_NAME)
            message(VERBOSE "Fixing Python library path: ${PYTHON_LIB_TO_FIX} -> ${PYTHON_LIB_RPATH_NAME}")
            
            # Add a post-build step to change the install name using install_name_tool
            # This changes the hardcoded absolute path to @rpath, which Python will resolve
            # using its own rpath configuration at runtime
            # Also ensure Python library directory is in rpath
            if(PYTHON_FRAMEWORK_PATH AND NOT PYTHON_FRAMEWORK_PATH STREQUAL PYTHON_LIB_TO_FIX)
                add_custom_command(TARGET ${PYTHON_MODULE_${SD_API_VER}} POST_BUILD
                    COMMAND install_name_tool -change "${PYTHON_LIB_TO_FIX}" "${PYTHON_LIB_RPATH_NAME}" "$<TARGET_FILE:${PYTHON_MODULE_${SD_API_VER}}>" || true
                    COMMAND install_name_tool -change "${PYTHON_FRAMEWORK_PATH}" "${PYTHON_LIB_RPATH_NAME}" "$<TARGET_FILE:${PYTHON_MODULE_${SD_API_VER}}>" || true
                    COMMAND sh -c "if ! otool -l \"$<TARGET_FILE:${PYTHON_MODULE_${SD_API_VER}}>\" 2>/dev/null | grep -q \"path ${PYTHON_LIBRARY_DIR}\"; then install_name_tool -add_rpath \"${PYTHON_LIBRARY_DIR}\" \"$<TARGET_FILE:${PYTHON_MODULE_${SD_API_VER}}>\" 2>/dev/null || true; fi"
                    COMMENT "Fixing Python library path to use @rpath and ensuring Python lib dir is in rpath"
                    VERBATIM
                )
            else()
                add_custom_command(TARGET ${PYTHON_MODULE_${SD_API_VER}} POST_BUILD
                    COMMAND install_name_tool -change "${PYTHON_LIB_TO_FIX}" "${PYTHON_LIB_RPATH_NAME}" "$<TARGET_FILE:${PYTHON_MODULE_${SD_API_VER}}>" || true
                    COMMAND sh -c "if ! otool -l \"$<TARGET_FILE:${PYTHON_MODULE_${SD_API_VER}}>\" 2>/dev/null | grep -q \"path ${PYTHON_LIBRARY_DIR}\"; then install_name_tool -add_rpath \"${PYTHON_LIBRARY_DIR}\" \"$<TARGET_FILE:${PYTHON_MODULE_${SD_API_VER}}>\" 2>/dev/null || true; fi"
                    COMMENT "Fixing Python library path to use @rpath and ensuring Python lib dir is in rpath"
                    VERBATIM
                )
            endif()
        endif()
    endif()
    
    target_compile_definitions(${PYTHON_MODULE_${SD_API_VER}} PRIVATE NRF_SD_BLE_API_VERSION=${SD_API_VER})

    get_target_property(CONNECTIVITY_SD_API_V${SD_API_VER}_PATH nrf::nrf_ble_driver_sd_api_v${SD_API_VER}_${NRF_BLE_DRIVER_LINKAGE_TYPE} INTERFACE_INCLUDE_DIRECTORIES)
    set(CONNECTIVITY_SD_API_V${SD_API_VER}_PATH ${CONNECTIVITY_SD_API_V${SD_API_VER}_PATH}/../../share/nrf-ble-driver/hex/sd_api_v${SD_API_VER})
    file(GLOB_RECURSE CONNECTIVITY_SD_API_V${SD_API_VER}_FILES "${CONNECTIVITY_SD_API_V${SD_API_VER}_PATH}/*.hex" "${CONNECTIVITY_SD_API_V${SD_API_VER}_PATH}/*.zip")

    set_property(
        TARGET ${PYTHON_MODULE_${SD_API_VER}}
        PROPERTY RESOURCE "${CONNECTIVITY_SD_API_V${SD_API_VER}_FILES}"
    )
    if(APPLE)
        set_property(TARGET ${PYTHON_MODULE_${SD_API_VER}} PROPERTY SUFFIX ".so")
    endif()
endforeach()

set(BUILD_OUTPUT_LIB_DIR "pc_ble_driver_py/lib")
set(BUILD_OUTPUT_HEX_DIR "pc_ble_driver_py/hex")

foreach(SD_API_VER ${SD_API_VERS})
    install(
        TARGETS ${PYTHON_MODULE_${SD_API_VER}}
        RUNTIME DESTINATION ${BUILD_OUTPUT_LIB_DIR}
        LIBRARY DESTINATION ${BUILD_OUTPUT_LIB_DIR}
        ARCHIVE DESTINATION ${BUILD_OUTPUT_LIB_DIR}
        RESOURCE DESTINATION "${BUILD_OUTPUT_HEX_DIR}/sd_api_v${SD_API_VER}"
    )

    install(
        FILES ${PC_BLE_DRIVER_PY_OUTDIR}/nrf_ble_driver_sd_api_v${SD_API_VER}.py
        DESTINATION ${BUILD_OUTPUT_LIB_DIR}
    )

    if(NRF_BLE_DRIVER_LINKAGE_TYPE STREQUAL "shared")
        install(
            FILES $<TARGET_FILE:nrf::nrf_ble_driver_sd_api_v${SD_API_VER}_${NRF_BLE_DRIVER_LINKAGE_TYPE}>
            DESTINATION ${BUILD_OUTPUT_LIB_DIR}
        )
    endif()
endforeach()
