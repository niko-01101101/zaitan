#pragma once
#include <cstdint>

struct HotkeyDef {
    uint32_t keyCode   = 0;
    uint32_t modifiers = 0;
};

enum class TransitionEffect { Slide, Fade, None };

struct Config {
    int gapSize = 0;
    bool firstDesktopEmpty = true;
    TransitionEffect transitionEffect = TransitionEffect::Slide;

    HotkeyDef assign;
    HotkeyDef splitH;
    HotkeyDef splitV;
    HotkeyDef remove;
    HotkeyDef rotate;
    HotkeyDef moveWinL;
    HotkeyDef moveWinR;
    HotkeyDef moveWinU;
    HotkeyDef moveWinD;
    HotkeyDef moveL;
    HotkeyDef moveR;
    HotkeyDef moveU;
    HotkeyDef moveD;
    HotkeyDef desktopPrev;
    HotkeyDef desktopNext;
    HotkeyDef moveWinToPrev;
    HotkeyDef moveWinToNext;
};

Config loadConfig();
