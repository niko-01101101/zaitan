#pragma once
#include "WMRect.hpp"
#include <cstdint>

struct Pane {
    uint32_t windowID = 0; // 0 = empty
    WMRect frame;
};
