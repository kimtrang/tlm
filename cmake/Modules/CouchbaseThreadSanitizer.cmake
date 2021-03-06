# Support for building with ThreadSanitizer (tsan) -
# https://code.google.com/p/thread-sanitizer/

INCLUDE(CheckCCompilerFlag)
INCLUDE(CheckCXXCompilerFlag)
INCLUDE(CMakePushCheckState)

OPTION(CB_THREADSANITIZER "Enable ThreadSanitizer data race detector."
       OFF)

IF (CB_THREADSANITIZER)
    CMAKE_PUSH_CHECK_STATE(RESET)
    SET(CMAKE_REQUIRED_FLAGS "-fsanitize=thread") # Also needs to be a link flag for test to pass
    CHECK_C_COMPILER_FLAG("-fsanitize=thread" HAVE_FLAG_SANITIZE_THREAD_C)
    CHECK_CXX_COMPILER_FLAG("-fsanitize=thread" HAVE_FLAG_SANITIZE_THREAD_CXX)
    CMAKE_POP_CHECK_STATE()

    IF(HAVE_FLAG_SANITIZE_THREAD_C AND HAVE_FLAG_SANITIZE_THREAD_CXX)
        SET(THREAD_SANITIZER_FLAG "-fsanitize=thread")

        SET(THREAD_SANITIZER_FLAG_DISABLE "-fno-sanitize=address")

        SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${THREAD_SANITIZER_FLAG}")
        SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${THREAD_SANITIZER_FLAG}")
        SET(CMAKE_CGO_LDFLAGS "${CMAKE_CGO_LDFLAGS} ${THREAD_SANITIZER_FLAG}")

        # TC/jemalloc are incompatible with ThreadSanitizer - force
        # the use of the system allocator.
        SET(COUCHBASE_MEMORY_ALLOCATOR system CACHE STRING "Memory allocator to use")

        # Configure CTest's MemCheck to ThreadSanitizer.
        SET(MEMORYCHECK_TYPE ThreadSanitizer)

        ADD_DEFINITIONS(-DTHREAD_SANITIZER)

        # Need to install libtsan to be able to run sanitized
        # binaries on a machine different to the build machine
        # (for example for RPM sanitized packages).
        find_sanitizer_library(tsan_lib libtsan.so.0)
        if(NOT tsan_lib)
          message(FATAL_ERROR "TSan library not found.")
        endif()

        message(STATUS "Found libtsan at: ${tsan_lib}")
        install(FILES ${tsan_lib} DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)
        if(IS_SYMLINK ${tsan_lib})
          # Often a shared library is actually a symlink to a versioned file - e.g.
          # libtsan.so.1 -> libtsan.so.1.0.0
          # In which case we also need to install the real file.
          get_filename_component(tsan_lib_realpath ${tsan_lib} REALPATH)
          install(FILES ${tsan_lib_realpath} DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)
        endif()

        # Override the normal ADD_TEST macro to set the TSAN_OPTIONS
        # environment variable - this allows us to specify the
        # suppressions file to use.
        FUNCTION(ADD_TEST name)
            IF(${ARGV0} STREQUAL "NAME")
               SET(_name ${ARGV1})
            ELSE()
               SET(_name ${ARGV0})
            ENDIF()
            _ADD_TEST(${ARGV})
            SET_TESTS_PROPERTIES(${_name} PROPERTIES ENVIRONMENT
                                 "TSAN_OPTIONS=suppressions=${CMAKE_SOURCE_DIR}/tlm/tsan.suppressions second_deadlock_stack=1 history_size=7")
        ENDFUNCTION()

        MESSAGE(STATUS "ThreadSanitizer enabled - forcing use of 'system' memory allocator.")
    ELSE()
        MESSAGE(FATAL_ERROR "CB_THREADSANITIZER enabled but compiler doesn't support ThreadSanitizer - cannot continue.")
    ENDIF()
ENDIF()

