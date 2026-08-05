/* Copyright 2026 the misakid contributors.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Portable configuration for the reviewed UTF-8-only Open JTalk 1.11 and
 * embedded MeCab runtime. The accepted dictionary is UTF-8, so conversion is
 * an identity operation and iconv is deliberately omitted.
 */

#ifndef MISAKID_OPENJTALK_PORTABLE_CONFIG_H_
#define MISAKID_OPENJTALK_PORTABLE_CONFIG_H_

#define HAVE_CTYPE_H 1
#define HAVE_GETENV 1
#define HAVE_INTTYPES_H 1
#define HAVE_MEMORY_H 1
#define HAVE_SETJMP 1
#define HAVE_SETJMP_H 1
#define HAVE_SQRT 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRSTR 1
#define STDC_HEADERS 1

#if defined(_WIN32) && !defined(__CYGWIN__)

/*
 * The reviewed Windows profile is MSVC x64. Do not expose the POSIX headers,
 * pthreads, mmap, GCC atomics, or `__thread` selected by the Unix profile.
 * MeCab's existing Windows branches use Win32 mapping, atomics, and threads.
 * The adapter's process-global mutex serializes the fallback global diagnostic
 * buffer when HAVE_TLS_KEYWORD is intentionally absent.
 */
#if !defined(_WIN64)
#error "misakid_openjtalk supports only 64-bit Windows native assets."
#endif

#define HAVE_IO_H 1
#define HAVE_WINDOWS_H 1

#define SIZEOF_CHAR 1
#define SIZEOF_INT 4
#define SIZEOF_LONG 4
#define SIZEOF_LONG_LONG 8
#define SIZEOF_SHORT 2
#define SIZEOF_SIZE_T 8

#else

#define HAVE_DIRENT_H 1
#define HAVE_FCNTL_H 1
#define HAVE_GCC_ATOMIC_OPS 1
#define HAVE_GETPAGESIZE 1
#define HAVE_LIBPTHREAD 1
#define HAVE_MMAP 1
#define HAVE_OPENDIR 1
#define HAVE_PTHREAD_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_MMAN_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIMES_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TLS_KEYWORD 1
#define HAVE_UNISTD_H 1
#define HAVE_UNSIGNED_LONG_LONG_INT 1

#define SIZEOF_CHAR __SIZEOF_CHAR__
#define SIZEOF_INT __SIZEOF_INT__
#define SIZEOF_LONG __SIZEOF_LONG__
#define SIZEOF_LONG_LONG __SIZEOF_LONG_LONG__
#define SIZEOF_SHORT __SIZEOF_SHORT__
#define SIZEOF_SIZE_T __SIZEOF_SIZE_T__

#endif

#define ICONV_CONST
#define LT_OBJDIR ".libs/"
#define PACKAGE "open_jtalk"
#define PACKAGE_BUGREPORT "https://github.com/r9y9/open_jtalk/"
#define PACKAGE_NAME "open_jtalk"
#define PACKAGE_STRING "open_jtalk 1.11"
#define PACKAGE_TARNAME "open_jtalk"
#define PACKAGE_URL ""
#define PACKAGE_VERSION "1.11"
#define VERSION "1.11"

#endif /* MISAKID_OPENJTALK_PORTABLE_CONFIG_H_ */
