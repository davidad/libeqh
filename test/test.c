#include <stdlib.h>
#include <string.h>
#include "libeqh.h"
#include "sodium.h"
#include "greatest.h"


TEST check200() {
  ASSERT_EQ(Eqh_200_9_GiveN(),200);
  PASS();
}

TEST check144() {
  ASSERT_EQ(Eqh_144_5_GiveN(),144);
  PASS();
}

TEST check9() {
  ASSERT_EQ(Eqh_200_9_GiveK(),9);
  PASS();
}

TEST check5() {
  ASSERT_EQ(Eqh_144_5_GiveK(),5);
  PASS();
}

SUITE(checks) {
  RUN_TEST(check200);
  RUN_TEST(check144);
  RUN_TEST(check9);
  RUN_TEST(check5);
}

TEST test_bitpack(uint32_t* ints, uint8_t* bytes) {
  uint8_t* packed = malloc(20);
  memset(packed,0,20);
  Bitpack_8_21(packed, ints);
  ASSERT_MEM_EQ(bytes, packed, 20);
  PASS();
}

SUITE(bitpack) {
  // test vectors taken from https://github.com/zcash/zcash/blob/70db019c6ae989acde0a0affd6a1f1c28ec9a3d2/src/gtest/test_equihash.cpp#L53-L67
  uint32_t ints1[] = {1, 1, 1, 1, 1, 1, 1, 1};
  RUN_TESTp(test_bitpack,ints1,"\x00\x00\x08\x00\x00\x40\x00\x02\x00\x00\x10\x00\x00\x80\x00\x04\x00\x00\x20\x00\x01");
  uint32_t ints2[] = {2097151, 2097151, 2097151, 2097151, 2097151, 2097151, 2097151, 2097151};
  RUN_TESTp(test_bitpack,ints2,"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff");
  uint32_t ints3[] = {131071, 128, 131071, 128, 131071, 128, 131071, 128};
  RUN_TESTp(test_bitpack,ints3,"\x0f\xff\xf8\x00\x20\x03\xff\xfe\x00\x08\x00\xff\xff\x80\x02\x00\x3f\xff\xe0\x00\x80");
  uint32_t ints4[] = {68, 41, 2097151, 1233, 665, 1023, 1, 1048575};
  RUN_TESTp(test_bitpack,ints4,"\x00\x02\x20\x00\x0a\x7f\xff\xfe\x00\x4d\x10\x01\x4c\x80\x0f\xfc\x00\x00\x2f\xff\xff");
}

TEST test_genhashes() {
  const char hdr[] = "davidad";
  uint8_t* hashes = Eqh_200_9_GenHashes(hdr,sizeof(hdr));
  printf("hashes: %p; hashes[0]: %x\n",hashes,hashes[0]);
  ASSERT(hashes != NULL);
  PASS();
}

SUITE(genhashes) {
  RUN_TEST(test_genhashes);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
  GREATEST_MAIN_BEGIN();
  RUN_SUITE(genhashes);
  RUN_SUITE(checks);
  RUN_SUITE(bitpack);
  GREATEST_MAIN_END();
}
