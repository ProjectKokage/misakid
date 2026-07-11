/* Copyright 2026 the misakid contributors.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Portable configuration for the reviewed UTF-8-only MeCab 0.996 runtime.
 * This target intentionally omits iconv: the accepted UniDic snapshot and
 * MeCab runtime are both UTF-8, for which MeCab's identity conversion is a
 * no-op.
 */

#ifndef MISAKID_MECAB_JA_PORTABLE_CONFIG_H_
#define MISAKID_MECAB_JA_PORTABLE_CONFIG_H_

#define HAVE_CTYPE_H 1
#define HAVE_DIRENT_H 1
#define HAVE_DLFCN_H 1
#define HAVE_FCNTL_H 1
#define HAVE_GCC_ATOMIC_OPS 1
#define HAVE_GETENV 1
#define HAVE_GETPAGESIZE 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIBPTHREAD 1
#define HAVE_MEMORY_H 1
#define HAVE_MMAP 1
#define HAVE_OPENDIR 1
#define HAVE_PTHREAD_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_MMAN_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIMES_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TLS_KEYWORD 1
#define HAVE_UNISTD_H 1
#define HAVE_UNSIGNED_LONG_LONG_INT 1
#define STDC_HEADERS 1

#define ICONV_CONST
#define LT_OBJDIR ".libs/"
#define PACKAGE "mecab"
#define PACKAGE_BUGREPORT ""
#define PACKAGE_NAME "mecab"
#define PACKAGE_STRING "mecab 0.996"
#define PACKAGE_TARNAME "mecab"
#define PACKAGE_URL ""
#define PACKAGE_VERSION "0.996"
#define VERSION "0.996"

#define SIZEOF_CHAR __SIZEOF_CHAR__
#define SIZEOF_INT __SIZEOF_INT__
#define SIZEOF_LONG __SIZEOF_LONG__
#define SIZEOF_LONG_LONG __SIZEOF_LONG_LONG__
#define SIZEOF_SHORT __SIZEOF_SHORT__
#define SIZEOF_SIZE_T __SIZEOF_SIZE_T__

#endif /* MISAKID_MECAB_JA_PORTABLE_CONFIG_H_ */
