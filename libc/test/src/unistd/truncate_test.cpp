//===-- Unittests for truncate --------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "src/__support/CPP/string_view.h"
#include "src/errno/libc_errno.h"
#include "src/fcntl/open.h"
#include "src/unistd/close.h"
#include "src/unistd/read.h"
#include "src/unistd/truncate.h"
#include "src/unistd/unlink.h"
#include "src/unistd/write.h"
#include "test/UnitTest/ErrnoSetterMatcher.h"
#include "test/UnitTest/Test.h"

namespace cpp = __llvm_libc::cpp;

TEST(LlvmLibcTruncateTest, CreateAndTruncate) {
  using __llvm_libc::testing::ErrnoSetterMatcher::Succeeds;
  constexpr const char TEST_FILE[] = "testdata/truncate.test";
  constexpr const char WRITE_DATA[] = "hello, truncate";
  constexpr size_t WRITE_SIZE = sizeof(WRITE_DATA);
  char buf[WRITE_SIZE];

  // The test strategy is as follows:
  //   1. Create a normal file with some data in it.
  //   2. Read it to make sure what was written is actually in the file.
  //   3. Truncate to 1 byte.
  //   4. Try to read more than 1 byte and fail.
  libc_errno = 0;
  int fd = __llvm_libc::open(TEST_FILE, O_WRONLY | O_CREAT, S_IRWXU);
  ASSERT_EQ(libc_errno, 0);
  ASSERT_GT(fd, 0);
  ASSERT_EQ(ssize_t(WRITE_SIZE),
            __llvm_libc::write(fd, WRITE_DATA, WRITE_SIZE));
  ASSERT_THAT(__llvm_libc::close(fd), Succeeds(0));

  fd = __llvm_libc::open(TEST_FILE, O_RDONLY);
  ASSERT_EQ(libc_errno, 0);
  ASSERT_GT(fd, 0);
  ASSERT_EQ(ssize_t(WRITE_SIZE), __llvm_libc::read(fd, buf, WRITE_SIZE));
  ASSERT_EQ(cpp::string_view(buf), cpp::string_view(WRITE_DATA));
  ASSERT_THAT(__llvm_libc::close(fd), Succeeds(0));

  ASSERT_THAT(__llvm_libc::truncate(TEST_FILE, off_t(1)), Succeeds(0));

  fd = __llvm_libc::open(TEST_FILE, O_RDONLY);
  ASSERT_EQ(libc_errno, 0);
  ASSERT_GT(fd, 0);
  ASSERT_EQ(ssize_t(1), __llvm_libc::read(fd, buf, WRITE_SIZE));
  ASSERT_EQ(buf[0], WRITE_DATA[0]);
  ASSERT_THAT(__llvm_libc::close(fd), Succeeds(0));

  ASSERT_THAT(__llvm_libc::unlink(TEST_FILE), Succeeds(0));
}

TEST(LlvmLibcTruncateTest, TruncateNonExistentFile) {
  using __llvm_libc::testing::ErrnoSetterMatcher::Fails;
  ASSERT_THAT(
      __llvm_libc::truncate("non-existent-dir/non-existent-file", off_t(1)),
      Fails(ENOENT));
}
