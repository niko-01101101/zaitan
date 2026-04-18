#include "../src/Desktop.hpp"
#import <Carbon/Carbon.h>
#include <HIToolbox/Events.h>

extern uint32_t getFrontmostWindowID();
extern void applyFrame(uint32_t windowID, WMRect frame);

#ifdef DEBUG
extern void showDebugOverlay(const std::vector<WindowPlacement> &placements);
#endif

static Desktop *sDesktop = nullptr;

static void applyLayout() {
  auto layout = sDesktop->getLayout();
  for (auto &p : layout)
    applyFrame(p.windowID, p.frame);
#ifdef DEBUG
  showDebugOverlay(layout);
#endif
}

enum : UInt32 {
  kHotkeyAssign = 1,
  kHotkeySplitH = 2,
  kHotkeySplitV = 3,
  kHotkeyRemove = 4,
  kHotkeyMoveWinL = 5,
  kHotkeyMoveWinR = 6,
  kHotkeyMoveWinU = 7,
  kHotkeyMoveWinD = 8,
  kHotkeyMoveL = 9,
  kHotkeyMoveR = 10,
  kHotkeyMoveU = 11,
  kHotkeyMoveD = 12,
};

static EventHotKeyRef gHotkeyAssign = nullptr;
static EventHotKeyRef gHotkeySplitH = nullptr;
static EventHotKeyRef gHotkeySplitV = nullptr;
static EventHotKeyRef gHotkeyRemove = nullptr;
static EventHotKeyRef gHotkeyMoveWinL = nullptr;
static EventHotKeyRef gHotkeyMoveWinR = nullptr;
static EventHotKeyRef gHotkeyMoveWinU = nullptr;
static EventHotKeyRef gHotkeyMoveWinD = nullptr;
static EventHotKeyRef gHotkeyMoveL = nullptr;
static EventHotKeyRef gHotkeyMoveR = nullptr;
static EventHotKeyRef gHotkeyMoveU = nullptr;
static EventHotKeyRef gHotkeyMoveD = nullptr;

static OSStatus HotkeyHandler(EventHandlerCallRef nextHandler, EventRef event,
                              void *userData) {
  EventHotKeyID hotkeyID;
  GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                    sizeof(EventHotKeyID), NULL, &hotkeyID);

  uint32_t focused = getFrontmostWindowID();
  switch (hotkeyID.id) {
  case kHotkeyAssign:
    NSLog(@"[zaitan] assign  pid=%u", focused);
    sDesktop->assignWindow(focused);
    break;
  case kHotkeySplitH:
    NSLog(@"[zaitan] splitH  pid=%u", focused);
    sDesktop->splitHorizontally(focused);
    break;
  case kHotkeySplitV:
    NSLog(@"[zaitan] splitV  pid=%u", focused);
    sDesktop->splitVertically(focused);
    break;
  case kHotkeyRemove:
    NSLog(@"[zaitan] remove  pid=%u", focused);
    sDesktop->removeWindow(focused);
    break;
  }

  applyLayout();
  return noErr;
}

void RegisterHotkeys(Desktop &desktop) {
  sDesktop = &desktop;

  EventTypeSpec hotkeyType = {kEventClassKeyboard, kEventHotKeyPressed};
  InstallApplicationEventHandler(&HotkeyHandler, 1, &hotkeyType, NULL, NULL);

  // Cmd+Shift+Return  — assign focused window to first empty pane
  // Cmd+Shift+Z   — split focused pane left/right
  // Cmd+Shift+X    — split focused pane top/bottom
  // Cmd+Shift+Delete  — remove focused window from layout
  // Cmd+Shift+Left  — move window left
  // Cmd+Shift+Right   — move window right
  // Cmd+Shift+Down    — move window down
  // Cmd+Shift+Up  — move window up
  // Cmd+Left  — select pane to the left
  // Cmd+Right   — select pane to the right
  // Cmd+Down    — select pane down
  // Cmd+Up  — select pane up
  RegisterEventHotKey(kVK_Return, cmdKey | shiftKey, {0, kHotkeyAssign},
                      GetApplicationEventTarget(), 0, &gHotkeyAssign);
  RegisterEventHotKey(kVK_ANSI_Z, cmdKey | shiftKey, {0, kHotkeySplitH},
                      GetApplicationEventTarget(), 0, &gHotkeySplitH);
  RegisterEventHotKey(kVK_ANSI_X, cmdKey | shiftKey, {0, kHotkeySplitV},
                      GetApplicationEventTarget(), 0, &gHotkeySplitV);
  RegisterEventHotKey(kVK_Delete, cmdKey | shiftKey, {0, kHotkeyRemove},
                      GetApplicationEventTarget(), 0, &gHotkeyRemove);
  RegisterEventHotKey(kVK_LeftArrow, cmdKey | shiftKey, {0, kHotkeyMoveWinL},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveWinL);
  RegisterEventHotKey(kVK_RightArrow, cmdKey | shiftKey, {0, kHotkeyMoveWinR},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveWinR);
  RegisterEventHotKey(kVK_UpArrow, cmdKey | shiftKey, {0, kHotkeyMoveWinU},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveWinU);
  RegisterEventHotKey(kVK_DownArrow, cmdKey | shiftKey, {0, kHotkeyMoveWinD},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveWinD);
  RegisterEventHotKey(kVK_LeftArrow, cmdKey, {0, kHotkeyMoveL},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveL);
  RegisterEventHotKey(kVK_RightArrow, cmdKey, {0, kHotkeyMoveR},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveR);
  RegisterEventHotKey(kVK_UpArrow, cmdKey, {0, kHotkeyMoveU},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveU);
  RegisterEventHotKey(kVK_DownArrow, cmdKey, {0, kHotkeyMoveD},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveD);
}

void UnregisterHotkeys() {
  if (gHotkeyAssign)
    UnregisterEventHotKey(gHotkeyAssign);
  if (gHotkeySplitH)
    UnregisterEventHotKey(gHotkeySplitH);
  if (gHotkeySplitV)
    UnregisterEventHotKey(gHotkeySplitV);
  if (gHotkeyRemove)
    UnregisterEventHotKey(gHotkeyRemove);
}
