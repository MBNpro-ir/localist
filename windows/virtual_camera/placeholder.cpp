#include <cstdint>
#include <vector>
// Neutral frame when Localist is stopped. Never retain the last private image.
static const std::vector<uint8_t>& Pixels() {
  static const auto pixels = [] {
    std::vector<uint8_t> value(640 * 480 * 3 / 2, 128);
    std::fill(value.begin(), value.begin() + 640 * 480, uint8_t(16));
    return value;
  }();
  return pixels;
}
bool initialize_placeholder() { Pixels(); return true; }
const uint8_t* get_placeholder_ptr() { return Pixels().data(); }
const bool get_placeholder_size(int* width, int* height) { *width = 640; *height = 480; return true; }
