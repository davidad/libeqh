#include "libeqh.h"
#include "greatest.h"

TEST check_returns17() {
  ASSERT_EQ(returns17(),17);
  PASS();
}

SUITE(checks) {
  RUN_TEST(check_returns17);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
  GREATEST_MAIN_BEGIN();
  RUN_SUITE(checks);
  GREATEST_MAIN_END();
}
