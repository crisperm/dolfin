# - Try to find PETSc
# Once done this will define
#
#  PETSC_FOUND        - system has PETSc
#  PETSC_INCLUDE_DIRS - include directories for PETSc
#  PETSC_LIBRARIES    - libraries for PETSc
#  PETSC_DIR          - directory where PETSc is built
#  PETSC_ARCH         - architecture for which PETSc is built
#
# This config script is (very loosley) based on a PETSc CMake script by Jed Brown.

# NOTE: The PETSc Makefile returns a bunch of libraries with '-L' and '-l',
# wheres we would prefer complete paths. For a discussion, see
# http://www.cmake.org/Wiki/CMake:Improving_Find*_Modules#Current_workarounds

message(STATUS "Checking for package 'PETSc'")

# Set debian_arches (PETSC_ARCH for Debian-style installations)
foreach (debian_arches linux kfreebsd)
  if ("${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
    set(DEBIAN_FLAVORS ${debian_arches}-gnu-c-debug ${debian_arches}-gnu-c-opt ${DEBIAN_FLAVORS})
  else()
    set(DEBIAN_FLAVORS ${debian_arches}-gnu-c-opt ${debian_arches}-gnu-c-debug ${DEBIAN_FLAVORS})
  endif()
endforeach()

# List of possible locations for PETSC_DIR
set(petsc_dir_locations "")
list(APPEND petsc_dir_locations "/usr/lib/petscdir/3.1")    # Debian location
list(APPEND petsc_dir_locations "/usr/lib/petscdir/3.0.0")  # Debian location
list(APPEND petsc_dir_locations "/usr/local/lib/petsc")     # User location
list(APPEND petsc_dir_locations "$ENV{HOME}/petsc")         # User location

# Add other possible locations for PETSC_DIR
set(_SYSTEM_LIB_PATHS "${CMAKE_SYSTEM_LIBRARY_PATH};${CMAKE_PLATFORM_IMPLICIT_LINK_DIRECTORIES}")
string(REGEX REPLACE ":" ";" libdirs ${_SYSTEM_LIB_PATHS})
foreach (libdir ${libdirs})
  get_filename_component(petsc_dir_location "${libdir}/" PATH)
  list(APPEND petsc_dir_locations ${petsc_dir_location})
endforeach()

# Try to figure out PETSC_DIR by finding petsc.h
find_path(PETSC_DIR include/petsc.h
  PATHS ENV PETSC_DIR ${petsc_dir_locations}
  DOC "PETSc directory")

# Report result of search for PETSC_DIR
if (DEFINED PETSC_DIR)
  message(STATUS "PETSC_DIR is ${PETSC_DIR}")
else()
  message(STATUS "PETSC_DIR is empty")
endif()

# Try to figure out PETSC_ARCH if not set
if (PETSC_DIR AND NOT PETSC_ARCH)
  set(_petsc_arches
    $ENV{PETSC_ARCH}   # If set, use environment variable first
    ${DEBIAN_FLAVORS}  # Debian defaults
    x86_64-unknown-linux-gnu i386-unknown-linux-gnu)
  set(petscconf "NOTFOUND" CACHE FILEPATH "Cleared" FORCE)
  foreach (arch ${_petsc_arches})
    if (NOT PETSC_ARCH)
      find_path(petscconf petscconf.h
      PATHS ${PETSC_DIR}
      PATH_SUFFIXES ${arch}/include bmake/${arch}
      NO_DEFAULT_PATH)
      if (petscconf)
        set(PETSC_ARCH "${arch}" CACHE STRING "PETSc build architecture")
      endif()
    endif()
  endforeach()
  set(petscconf "NOTFOUND" CACHE INTERNAL "Scratch variable" FORCE)
endif()

# Report result of search for PETSC_ARCH
if (DEFINED PETSC_ARCH)
  message(STATUS "PETSC_ARCH is ${PETSC_ARCH}")
else()
  message(STATUS "PETSC_ARCH is empty")
endif()

# Look for petscconf.h
if (EXISTS ${PETSC_DIR}/${PETSC_ARCH}/include/petscconf.h)
  message(STATUS "Found petscconf.h")
  set(FOUND_PETSC_CONF 1)
else()
  message(STATUS "Unable to find petscconf.h")
endif()

# Get variables from PETSc configuration
if (FOUND_PETSC_CONF)

  # Create a temporary Makefile to probe the PETSc configuration
  set(petsc_config_makefile ${PROJECT_BINARY_DIR}/Makefile.petsc)
  file(WRITE ${petsc_config_makefile}
"# This file was autogenerated by FindPETSc.cmake
PETSC_DIR  = ${PETSC_DIR}
PETSC_ARCH = ${PETSC_ARCH}
include ${PETSC_DIR}/conf/variables
show :
	-@echo -n \${\${VARIABLE}}
")

  # Define macro for getting PETSc variables from Makefile
  macro(PETSC_GET_VARIABLE var name)
    set(${var} "NOTFOUND" CACHE INTERNAL "Cleared" FORCE)
    execute_process(COMMAND ${CMAKE_MAKE_PROGRAM} -f ${petsc_config_makefile} show VARIABLE=${name}
      OUTPUT_VARIABLE ${var}
      RESULT_VARIABLE petsc_return)
  endmacro()

  # Call macro to get the PETSc variables
  petsc_get_variable(PETSC_INCLUDE_DIRS PETSC_INCLUDE)
  petsc_get_variable(PETSC_LIBRARIES    PETSC_LIB)

  # Remove temporary Makefile
  file(REMOVE ${petsc_config_makefile})

  # Turn PETSC_INCLUDE_DIRS into a semi-colon separated list
  string(REPLACE "-I" "" PETSC_INCLUDE_DIRS ${PETSC_INCLUDE_DIRS})
  separate_arguments(PETSC_INCLUDE_DIRS)

endif()

# Build PETSc test program
if (FOUND_PETSC_CONF)

  # Set flags for building test program
  set(CMAKE_REQUIRED_INCLUDES ${PETSC_INCLUDE_DIRS})
  set(CMAKE_REQUIRED_LIBRARIES ${PETSC_LIBRARIES})

  # Add MPI variables if MPI has been found
  if (MPI_FOUND)
    set(CMAKE_REQUIRED_INCLUDES  ${CMAKE_REQUIRED_INCLUDES} ${MPI_INCLUDE_PATH})
    set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES} ${MPI_LIBRARIES} ${MPI_LINK_FLAGS})
    set(CMAKE_REQUIRED_FLAGS     ${CMAKE_REQUIRED_FLAGS} ${MPI_COMPILE_FLAGS})
  endif()

  # Run PETSc test program
  include(CheckCXXSourceRuns)
  check_cxx_source_runs("
#include \"petscts.h\"
#include \"petsc.h\"
int main()
{
  PetscErrorCode ierr;
  TS ts;
  ierr = PetscInitializeNoArguments();CHKERRQ(ierr);
  ierr = TSCreate(PETSC_COMM_WORLD,&ts);CHKERRQ(ierr);
  ierr = TSSetFromOptions(ts);CHKERRQ(ierr);
  ierr = TSDestroy(ts);CHKERRQ(ierr);
  ierr = PetscFinalize();CHKERRQ(ierr);
  return 0;
}
" PETSC_TEST_RUNS)

  if (PETSC_TEST_RUNS)
    message(STATUS "PETSc test runs")
  else()
    message(STATUS "PETSc test failed")
  endif()

endif()

# Standard package handling
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(PETSc
  "PETSc could not be found. Be sure to set PETSC_DIR and PETSC_ARCH."
  PETSC_DIR PETSC_INCLUDE_DIRS PETSC_LIBRARIES PETSC_TEST_RUNS)
