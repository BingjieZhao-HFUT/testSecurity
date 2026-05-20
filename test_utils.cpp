#include <cassert>
#include <iostream>
#include "utils.h"

void test_greet() {
    assert(Utils::greet("Alice") == "Hello, Alice!");
    assert(Utils::greet("")      == "Hello, !");
    std::cout << "[PASS] test_greet\n";
}

void test_sum() {
    assert(Utils::sum({1, 2, 3})    == 6);
    assert(Utils::sum({})           == 0);
    assert(Utils::sum({-1, 1})      == 0);
    std::cout << "[PASS] test_sum\n";
}

void test_average() {
    assert(Utils::average({1, 2, 3}) == 2.0);
    assert(Utils::average({})        == 0.0);
    std::cout << "[PASS] test_average\n";
}

void test_trim() {
    assert(Utils::trim("  hello  ") == "hello");
    assert(Utils::trim("no spaces") == "no spaces");
    assert(Utils::trim("   ")       == "");
    std::cout << "[PASS] test_trim\n";
}

int main() {
    std::cout << "Running unit tests...\n";
    test_greet();
    test_sum();
    test_average();
    test_trim();
    std::cout << "All unit tests passed!\n";
    return 0;
}

// v1: initial implementation of utility functions and unit tests
// v2: added more test cases and edge cases for utility functions
// v3: test at 2026-05-20, added comments and improved test output formatting
// v3: test at 2026-05-20, added comments and improved test output formatting  111
// v3: test at 2026-05-20, added comments and improved test output formatting  222
// v3: test at 2026-05-20, added comments and improved test output formatting  333
// v3: test at 2026-05-20, added comments and improved test output formatting  444
// v3: test at 2026-05-20, added comments and improved test output formatting  
// v3: test at 2026-05-20, added comments and improved test output formatting  666
// v3: test at 2026-05-20, added comments and improved test output formatting  777
// v3: test at 2026-05-20, added comments and improved test output formatting  888
// v3: test at 2026-05-20, added comments and improved test output formatting  999
// v3: test at 2026-05-20, added comments and improved test output formatting  1111
// v3: test at 2026-05-20, added comments and improved test output formatting  2222