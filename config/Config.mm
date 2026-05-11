#include "Config.hpp"
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>

static std::string trim(const std::string &s) {
    size_t a = s.find_first_not_of(" \t\r");
    size_t b = s.find_last_not_of(" \t\r");
    return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}

static std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), ::tolower);
    return s;
}

static const std::unordered_map<std::string, uint32_t> kKeyNames = {
    {"a", kVK_ANSI_A}, {"b", kVK_ANSI_B}, {"c", kVK_ANSI_C}, {"d", kVK_ANSI_D},
    {"e", kVK_ANSI_E}, {"f", kVK_ANSI_F}, {"g", kVK_ANSI_G}, {"h", kVK_ANSI_H},
    {"i", kVK_ANSI_I}, {"j", kVK_ANSI_J}, {"k", kVK_ANSI_K}, {"l", kVK_ANSI_L},
    {"m", kVK_ANSI_M}, {"n", kVK_ANSI_N}, {"o", kVK_ANSI_O}, {"p", kVK_ANSI_P},
    {"q", kVK_ANSI_Q}, {"r", kVK_ANSI_R}, {"s", kVK_ANSI_S}, {"t", kVK_ANSI_T},
    {"u", kVK_ANSI_U}, {"v", kVK_ANSI_V}, {"w", kVK_ANSI_W}, {"x", kVK_ANSI_X},
    {"y", kVK_ANSI_Y}, {"z", kVK_ANSI_Z},
    {"0", kVK_ANSI_0}, {"1", kVK_ANSI_1}, {"2", kVK_ANSI_2}, {"3", kVK_ANSI_3},
    {"4", kVK_ANSI_4}, {"5", kVK_ANSI_5}, {"6", kVK_ANSI_6}, {"7", kVK_ANSI_7},
    {"8", kVK_ANSI_8}, {"9", kVK_ANSI_9},
    {"return",    kVK_Return},    {"enter",     kVK_Return},
    {"delete",    kVK_Delete},    {"backspace",  kVK_Delete},
    {"tab",       kVK_Tab},       {"space",      kVK_Space},
    {"escape",    kVK_Escape},    {"esc",        kVK_Escape},
    {"left",      kVK_LeftArrow}, {"right",      kVK_RightArrow},
    {"up",        kVK_UpArrow},   {"down",       kVK_DownArrow},
    {"f1",  kVK_F1},  {"f2",  kVK_F2},  {"f3",  kVK_F3},  {"f4",  kVK_F4},
    {"f5",  kVK_F5},  {"f6",  kVK_F6},  {"f7",  kVK_F7},  {"f8",  kVK_F8},
    {"f9",  kVK_F9},  {"f10", kVK_F10}, {"f11", kVK_F11}, {"f12", kVK_F12},
};

static const std::unordered_map<std::string, uint32_t> kModNames = {
    {"cmd", cmdKey},       {"command",  cmdKey},
    {"shift", shiftKey},
    {"opt", optionKey},    {"option",   optionKey}, {"alt", optionKey},
    {"ctrl", controlKey},  {"control",  controlKey},
};

static HotkeyDef parseHotkey(const std::string &value) {
    HotkeyDef def = {};
    std::istringstream ss(value);
    std::string token;
    while (std::getline(ss, token, '+')) {
        std::string t = lower(trim(token));
        auto mod = kModNames.find(t);
        if (mod != kModNames.end()) {
            def.modifiers |= mod->second;
        } else {
            auto key = kKeyNames.find(t);
            if (key != kKeyNames.end())
                def.keyCode = key->second;
        }
    }
    return def;
}

static Config makeDefaults() {
    Config c;
    c.assign        = { kVK_Return,      (uint32_t)(cmdKey | shiftKey) };
    c.splitH        = { kVK_ANSI_Z,      (uint32_t)(cmdKey | shiftKey) };
    c.splitV        = { kVK_ANSI_X,      (uint32_t)(cmdKey | shiftKey) };
    c.remove        = { kVK_Delete,      (uint32_t)(cmdKey | shiftKey) };
    c.rotate        = { kVK_ANSI_R,      (uint32_t)(cmdKey | shiftKey) };
    c.moveWinL      = { kVK_LeftArrow,   (uint32_t)(cmdKey | shiftKey) };
    c.moveWinR      = { kVK_RightArrow,  (uint32_t)(cmdKey | shiftKey) };
    c.moveWinU      = { kVK_UpArrow,     (uint32_t)(cmdKey | shiftKey) };
    c.moveWinD      = { kVK_DownArrow,   (uint32_t)(cmdKey | shiftKey) };
    c.moveL         = { kVK_LeftArrow,   (uint32_t)(cmdKey) };
    c.moveR         = { kVK_RightArrow,  (uint32_t)(cmdKey) };
    c.moveU         = { kVK_UpArrow,     (uint32_t)(cmdKey) };
    c.moveD         = { kVK_DownArrow,   (uint32_t)(cmdKey) };
    c.desktopPrev   = { kVK_LeftArrow,   (uint32_t)(cmdKey | controlKey) };
    c.desktopNext   = { kVK_RightArrow,  (uint32_t)(cmdKey | controlKey) };
    c.moveWinToPrev = { kVK_LeftArrow,   (uint32_t)(cmdKey | controlKey | shiftKey) };
    c.moveWinToNext = { kVK_RightArrow,  (uint32_t)(cmdKey | controlKey | shiftKey) };
    return c;
}

static NSString *configPath() {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".config/zaitan/zaitan.conf"];
}

static void createDefaultConfigIfNeeded() {
    NSString *path = configPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        return;
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *template_ =
        @"# Zaitan configuration\n"
        @"# Reload without restarting: Cmd+Ctrl+Shift+R\n"
        @"\n"
        @"# Gap between windows in points (0 = no gap)\n"
        @"# gap_size = 0\n"
        @"\n"
        @"# Keep desktop 1 empty on startup; assign existing windows to desktop 2\n"
        @"# first_desktop_empty = true\n"
        @"\n"
        @"# Desktop switch animation: slide | fade | none\n"
        @"# transition_effect = slide\n"
        @"\n"
        @"# Hotkeys — modifiers: cmd, shift, ctrl, opt\n"
        @"# Keys: a-z, 0-9, return, delete, left, right, up, down, space, tab, escape, f1-f12\n"
        @"# hotkey_assign          = cmd+shift+return\n"
        @"# hotkey_split_h         = cmd+shift+z\n"
        @"# hotkey_split_v         = cmd+shift+x\n"
        @"# hotkey_remove          = cmd+shift+delete\n"
        @"# hotkey_rotate          = cmd+shift+r\n"
        @"# hotkey_move_win_l      = cmd+shift+left\n"
        @"# hotkey_move_win_r      = cmd+shift+right\n"
        @"# hotkey_move_win_u      = cmd+shift+up\n"
        @"# hotkey_move_win_d      = cmd+shift+down\n"
        @"# hotkey_move_l          = cmd+left\n"
        @"# hotkey_move_r          = cmd+right\n"
        @"# hotkey_move_u          = cmd+up\n"
        @"# hotkey_move_d          = cmd+down\n"
        @"# hotkey_desktop_prev    = cmd+ctrl+left\n"
        @"# hotkey_desktop_next    = cmd+ctrl+right\n"
        @"# hotkey_move_win_to_prev = cmd+ctrl+shift+left\n"
        @"# hotkey_move_win_to_next = cmd+ctrl+shift+right\n";
    [template_ writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

Config loadConfig() {
    createDefaultConfigIfNeeded();
    Config config = makeDefaults();

    NSString *path = configPath();
    std::ifstream file([path UTF8String]);
    if (!file.is_open())
        return config;

    std::string line;
    while (std::getline(file, line)) {
        size_t commentPos = line.find('#');
        if (commentPos != std::string::npos)
            line = line.substr(0, commentPos);

        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;

        std::string key = lower(trim(line.substr(0, eq)));
        std::string val = trim(line.substr(eq + 1));
        if (key.empty() || val.empty()) continue;

        if      (key == "gap_size")               { try { config.gapSize = std::stoi(val); } catch (...) {} }
        else if (key == "first_desktop_empty")    { config.firstDesktopEmpty = (val == "true" || val == "1"); }
        else if (key == "transition_effect") {
            if      (val == "fade") config.transitionEffect = TransitionEffect::Fade;
            else if (val == "none") config.transitionEffect = TransitionEffect::None;
            else                    config.transitionEffect = TransitionEffect::Slide;
        }
        else if (key == "hotkey_assign")           { config.assign        = parseHotkey(val); }
        else if (key == "hotkey_split_h")          { config.splitH        = parseHotkey(val); }
        else if (key == "hotkey_split_v")          { config.splitV        = parseHotkey(val); }
        else if (key == "hotkey_remove")           { config.remove        = parseHotkey(val); }
        else if (key == "hotkey_rotate")           { config.rotate        = parseHotkey(val); }
        else if (key == "hotkey_move_win_l")       { config.moveWinL      = parseHotkey(val); }
        else if (key == "hotkey_move_win_r")       { config.moveWinR      = parseHotkey(val); }
        else if (key == "hotkey_move_win_u")       { config.moveWinU      = parseHotkey(val); }
        else if (key == "hotkey_move_win_d")       { config.moveWinD      = parseHotkey(val); }
        else if (key == "hotkey_move_l")           { config.moveL         = parseHotkey(val); }
        else if (key == "hotkey_move_r")           { config.moveR         = parseHotkey(val); }
        else if (key == "hotkey_move_u")           { config.moveU         = parseHotkey(val); }
        else if (key == "hotkey_move_d")           { config.moveD         = parseHotkey(val); }
        else if (key == "hotkey_desktop_prev")     { config.desktopPrev   = parseHotkey(val); }
        else if (key == "hotkey_desktop_next")     { config.desktopNext   = parseHotkey(val); }
        else if (key == "hotkey_move_win_to_prev") { config.moveWinToPrev = parseHotkey(val); }
        else if (key == "hotkey_move_win_to_next") { config.moveWinToNext = parseHotkey(val); }
    }

    return config;
}
