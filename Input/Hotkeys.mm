#import <Carbon/Carbon.h>
#include "../src/Desktop.hpp"

extern uint32_t getFrontmostWindowID();
extern void applyFrame(uint32_t windowID, WMRect frame);

static Desktop *sDesktop = nullptr;

static void applyLayout() {
    for (auto &p : sDesktop->getLayout())
        applyFrame(p.windowID, p.frame);
}

enum : UInt32 {
    kHotkeyAssign  = 1,
    kHotkeySplitH  = 2,
    kHotkeySplitV  = 3,
    kHotkeyRemove  = 4,
};

static EventHotKeyRef gHotkeyAssign  = nullptr;
static EventHotKeyRef gHotkeySplitH  = nullptr;
static EventHotKeyRef gHotkeySplitV  = nullptr;
static EventHotKeyRef gHotkeyRemove  = nullptr;

static OSStatus HotkeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotkeyID;
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                      NULL, sizeof(EventHotKeyID), NULL, &hotkeyID);

    uint32_t focused = getFrontmostWindowID();
    switch (hotkeyID.id) {
        case kHotkeyAssign: NSLog(@"[zaitan] assign  pid=%u", focused); sDesktop->assignWindow(focused);      break;
        case kHotkeySplitH: NSLog(@"[zaitan] splitH  pid=%u", focused); sDesktop->splitHorizontally(focused); break;
        case kHotkeySplitV: NSLog(@"[zaitan] splitV  pid=%u", focused); sDesktop->splitVertically(focused);   break;
        case kHotkeyRemove: NSLog(@"[zaitan] remove  pid=%u", focused); sDesktop->removeWindow(focused);      break;
    }

    applyLayout();
    return noErr;
}

void RegisterHotkeys(Desktop &desktop) {
    sDesktop = &desktop;

    EventTypeSpec hotkeyType = {kEventClassKeyboard, kEventHotKeyPressed};
    InstallApplicationEventHandler(&HotkeyHandler, 1, &hotkeyType, NULL, NULL);

    // Cmd+Shift+Return  — assign focused window to first empty pane
    // Cmd+Shift+Right   — split focused pane left/right
    // Cmd+Shift+Down    — split focused pane top/bottom
    // Cmd+Shift+Delete  — remove focused window from layout
    RegisterEventHotKey(kVK_Return,     cmdKey | shiftKey, {0, kHotkeyAssign}, GetApplicationEventTarget(), 0, &gHotkeyAssign);
    RegisterEventHotKey(kVK_RightArrow, cmdKey | shiftKey, {0, kHotkeySplitH}, GetApplicationEventTarget(), 0, &gHotkeySplitH);
    RegisterEventHotKey(kVK_DownArrow,  cmdKey | shiftKey, {0, kHotkeySplitV}, GetApplicationEventTarget(), 0, &gHotkeySplitV);
    RegisterEventHotKey(kVK_Delete,     cmdKey | shiftKey, {0, kHotkeyRemove}, GetApplicationEventTarget(), 0, &gHotkeyRemove);
}

void UnregisterHotkeys() {
    if (gHotkeyAssign) UnregisterEventHotKey(gHotkeyAssign);
    if (gHotkeySplitH) UnregisterEventHotKey(gHotkeySplitH);
    if (gHotkeySplitV) UnregisterEventHotKey(gHotkeySplitV);
    if (gHotkeyRemove) UnregisterEventHotKey(gHotkeyRemove);
}
