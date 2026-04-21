// Copyright 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef SANDBOX_LINUX_SYSTEM_HEADERS_PPC64_LINUX_SYSCALLS_H_
#define SANDBOX_LINUX_SYSTEM_HEADERS_PPC64_LINUX_SYSCALLS_H_

#include <asm/unistd.h>

//TODO: is it necessary to redefine syscall numbers for PPC64?
// Needed for Ubuntu/Debian/Centos/RHEL:
#if !defined(__NR_shmget)
#define __NR_shmget     395
#endif
#if !defined(__NR_shmdt)
#define __NR_shmdt      398
#endif
#if !defined(__NR_shmctl)
#define __NR_shmctl     396
#endif
#if !defined(__NR_shmat)
#define __NR_shmat      397
#endif
#if !defined(__NR_mseal)
#define __NR_mseal      462
#endif

#endif  // SANDBOX_LINUX_SYSTEM_HEADERS_PPC64_LINUX_SYSCALLS_H_
