#include <boost/format.hpp>
#include <iostream>
#include <memory>
#include <string>

int main() {
  auto message = std::make_unique<std::string>("Nix Seed");
  std::cout << boost::format("Hello from %1%!") % *message << std::endl;
  return 0;
}
