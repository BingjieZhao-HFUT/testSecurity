#include <iostream>
#include <string>
#include <cctype>

bool is_weak_password(const std::string& password) {
    if (password.size() < 8) return true;

    bool has_upper = false;
    bool has_lower = false;
    bool has_digit = false;

    for (char ch : password) {
        unsigned char c = static_cast<unsigned char>(ch);
        if (std::isupper(c)) has_upper = true;
        if (std::islower(c)) has_lower = true;
        if (std::isdigit(c)) has_digit = true;
    }

    return !(has_upper && has_lower && has_digit);
}

int main() {
    std::string password;
    std::cout << "Enter password to test: ";
    std::getline(std::cin, password);

    if (is_weak_password(password)) {
        std::cout << "[WEAK] Password does not meet baseline policy.\n";
        return 1;
    }

    std::cout << "[PASS] Password passed baseline policy.\n";
    return 0;
}
