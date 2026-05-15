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
// v2: added more test cases for edge conditions
// v3: refactored code for better readability and maintainability
// v4: added comments and documentation for utility functions
// v5: optimized trim function using iterators and lambda functions