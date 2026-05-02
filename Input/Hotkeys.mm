#include "../src/Desktop.hpp"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <vector>

extern uint32_t getFrontmostWindowID();
extern std::vector<uint32_t> getAllWindowIDs();
extern void applyFrame(uint32_t windowID, WMRect frame);
extern void closeWindow(uint32_t windowID);
extern void launchNewInstance(uint32_t windowID);
extern void focusWindow(uint32_t windowID);

#ifdef DEBUG
extern void showDebugOverlay(const std::vector<WindowPlacement> &placements,
                             uint32_t selectedID);
#endif

static constexpr int NUM_DESKTOPS = 4;
static Desktop *sDesktops[NUM_DESKTOPS] = {};
static int sCurrentDesktopIndex = 0;
// Per-desktop selection: tracks the last-selected window on each desktop.
static uint32_t sSelectedIDs[NUM_DESKTOPS] = {};
static id gLaunchObserver = nil;
static id gActivateObserver = nil;

static Desktop *currentDesktop() { return sDesktops[sCurrentDesktopIndex]; }
static uint32_t &selectedID() { return sSelectedIDs[sCurrentDesktopIndex]; }

static void applyLayout() {
  auto layout = currentDesktop()->getLayout();
  for (auto &p : layout)
    applyFrame(p.windowID, p.frame);
#ifdef DEBUG
  showDebugOverlay(layout, selectedID());
#endif
}

static void hideDesktopWindows(Desktop *desktop) {
  for (auto &p : desktop->getLayout())
    applyFrame(p.windowID, {100000, 100000, p.frame.width, p.frame.height});
}

// Returns the split direction that gives the new pane the most room.
static SplitDirection preferredSplit(WMRect frame) {
  return frame.width >= frame.height ? SplitDirection::Horizontal
                                     : SplitDirection::Vertical;
}

// Adds a window to a desktop, splitting if there are no empty panes.
static void addWindowToDesktop(Desktop *desktop, uint32_t windowID) {
  if (desktop->assignWindow(windowID))
    return;
  auto layout = desktop->getLayout();
  if (layout.empty())
    return;
  auto &last = layout.back();
  if (preferredSplit(last.frame) == SplitDirection::Horizontal)
    desktop->splitHorizontally(last.windowID, windowID);
  else
    desktop->splitVertically(last.windowID, windowID);
}

// Switches to the desktop at newIndex: hides current, shows next, restores selection.
static void switchToDesktop(int newIndex) {
  hideDesktopWindows(currentDesktop());
  sCurrentDesktopIndex = newIndex;
  uint32_t toFocus = selectedID();
  if (!toFocus) {
    auto layout = currentDesktop()->getLayout();
    if (!layout.empty())
      toFocus = layout.back().windowID;
  }
  if (toFocus) {
    selectedID() = toFocus;
    focusWindow(toFocus);
  }
  applyLayout();
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
  kHotkeyDesktopPrev = 13,
  kHotkeyDesktopNext = 14,
  kHotkeyMoveWinToPrev = 15,
  kHotkeyMoveWinToNext = 16,
  kHotkeyRotate = 17,
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
static EventHotKeyRef gHotkeyDesktopPrev = nullptr;
static EventHotKeyRef gHotkeyDesktopNext = nullptr;
static EventHotKeyRef gHotkeyMoveWinToPrev = nullptr;
static EventHotKeyRef gHotkeyMoveWinToNext = nullptr;
static EventHotKeyRef gHotkeyRotate = nullptr;

static OSStatus HotkeyHandler(EventHandlerCallRef nextHandler, EventRef event,
                              void *userData) {
  EventHotKeyID hotkeyID;
  GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                    sizeof(EventHotKeyID), NULL, &hotkeyID);

  uint32_t focused = getFrontmostWindowID();
  switch (hotkeyID.id) {
  case kHotkeyAssign:
    NSLog(@"[zaitan] assign  pid=%u", focused);
    currentDesktop()->assignWindow(focused);
    selectedID() = focused;
    break;
  case kHotkeySplitH: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] splitH  pid=%u", target);
    if (currentDesktop()->splitHorizontally(target))
      launchNewInstance(target);
    break;
  }
  case kHotkeySplitV: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] splitV  pid=%u", target);
    if (currentDesktop()->splitVertically(target))
      launchNewInstance(target);
    break;
  }
  case kHotkeyRemove: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] remove  pid=%u", target);
    currentDesktop()->removeWindow(target);
    if (!currentDesktop()->assignWindow(target))
      closeWindow(target);
    selectedID() = 0;
    break;
  }
  case kHotkeyMoveWinL:
    NSLog(@"[zaitan] move window left  pid=%u", selectedID());
    currentDesktop()->moveWindowHorizontally(selectedID() ? selectedID() : focused,
                                     HorizontalDirection::Left);
    break;
  case kHotkeyMoveWinR:
    NSLog(@"[zaitan] move window right  pid=%u", selectedID());
    currentDesktop()->moveWindowHorizontally(selectedID() ? selectedID() : focused,
                                     HorizontalDirection::Right);
    break;
  case kHotkeyMoveWinU:
    NSLog(@"[zaitan] move window up  pid=%u", selectedID());
    currentDesktop()->moveWindowVertically(selectedID() ? selectedID() : focused,
                                   VerticalDirection::Up);
    break;
  case kHotkeyMoveWinD:
    NSLog(@"[zaitan] move window down  pid=%u", selectedID());
    currentDesktop()->moveWindowVertically(selectedID() ? selectedID() : focused,
                                   VerticalDirection::Down);
    break;
  case kHotkeyMoveL: {
    uint32_t next = currentDesktop()->moveHorizontally(selectedID() ? selectedID() : focused,
                                               HorizontalDirection::Left);
    if (next) { selectedID() = next; focusWindow(next); }
    NSLog(@"[zaitan] select left  pid=%u next=>%u", selectedID(), next);
    break;
  }
  case kHotkeyMoveR: {
    uint32_t next = currentDesktop()->moveHorizontally(selectedID() ? selectedID() : focused,
                                               HorizontalDirection::Right);
    if (next) { selectedID() = next; focusWindow(next); }
    NSLog(@"[zaitan] select right  pid=%u", selectedID());
    break;
  }
  case kHotkeyMoveU: {
    uint32_t next = currentDesktop()->moveVertically(selectedID() ? selectedID() : focused,
                                             VerticalDirection::Up);
    if (next) { selectedID() = next; focusWindow(next); }
    NSLog(@"[zaitan] select up  pid=%u", selectedID());
    break;
  }
  case kHotkeyMoveD: {
    uint32_t next = currentDesktop()->moveVertically(selectedID() ? selectedID() : focused,
                                             VerticalDirection::Down);
    if (next) { selectedID() = next; focusWindow(next); }
    NSLog(@"[zaitan] select down  pid=%u", selectedID());
    break;
  }
  case kHotkeyRotate:
    NSLog(@"[zaitan] flip splits");
    currentDesktop()->flipSplits();
    break;
  case kHotkeyDesktopPrev: {
    int prevIdx = (sCurrentDesktopIndex + NUM_DESKTOPS - 1) % NUM_DESKTOPS;
    if (sDesktops[prevIdx]->getLayout().empty())
      return noErr;
    NSLog(@"[zaitan] switch to desktop %d", prevIdx);
    switchToDesktop(prevIdx);
    return noErr;
  }
  case kHotkeyDesktopNext: {
    int nextIdx = (sCurrentDesktopIndex + 1) % NUM_DESKTOPS;
    if (sDesktops[nextIdx]->getLayout().empty())
      return noErr;
    NSLog(@"[zaitan] switch to desktop %d", nextIdx);
    switchToDesktop(nextIdx);
    return noErr;
  }
  case kHotkeyMoveWinToPrev: {
    uint32_t target = selectedID() ? selectedID() : focused;
    int prevIdx = (sCurrentDesktopIndex + NUM_DESKTOPS - 1) % NUM_DESKTOPS;
    NSLog(@"[zaitan] move window to desktop %d  pid=%u", prevIdx, target);
    currentDesktop()->removeWindow(target);
    addWindowToDesktop(sDesktops[prevIdx], target);
    selectedID() = 0;
    sSelectedIDs[prevIdx] = target;
    switchToDesktop(prevIdx);
    return noErr;
  }
  case kHotkeyMoveWinToNext: {
    uint32_t target = selectedID() ? selectedID() : focused;
    int nextIdx = (sCurrentDesktopIndex + 1) % NUM_DESKTOPS;
    NSLog(@"[zaitan] move window to desktop %d  pid=%u", nextIdx, target);
    currentDesktop()->removeWindow(target);
    addWindowToDesktop(sDesktops[nextIdx], target);
    selectedID() = 0;
    sSelectedIDs[nextIdx] = target;
    switchToDesktop(nextIdx);
    return noErr;
  }
  }

  applyLayout();
  return noErr;
}

static void autoAssignWindow(uint32_t pid) {
  if (!currentDesktop()->assignWindow(pid)) {
    auto layout = currentDesktop()->getLayout();
    if (layout.empty())
      return;
    uint32_t target = selectedID() ? selectedID() : layout.back().windowID;
    WMRect frame = {};
    for (auto &p : layout)
      if (p.windowID == target) { frame = p.frame; break; }
    if (preferredSplit(frame) == SplitDirection::Horizontal)
      currentDesktop()->splitHorizontally(target, pid);
    else
      currentDesktop()->splitVertically(target, pid);
  }
  selectedID() = pid;
  applyLayout();
  focusWindow(pid);
}

void StartAutoAssign() {
  auto pids = getAllWindowIDs();
  if (!pids.empty()) {
    currentDesktop()->assignWindow(pids[0]);
    for (size_t i = 1; i < pids.size() && (int)i < MAX_PANES - 1; i++) {
      auto layout = currentDesktop()->getLayout();
      WMRect frame = {};
      for (auto &p : layout)
        if (p.windowID == pids[i - 1]) { frame = p.frame; break; }
      if (preferredSplit(frame) == SplitDirection::Horizontal)
        currentDesktop()->splitHorizontally(pids[i - 1], pids[i]);
      else
        currentDesktop()->splitVertically(pids[i - 1], pids[i]);
    }
    applyLayout();
  }

  gActivateObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserverForName:NSWorkspaceDidActivateApplicationNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
                uint32_t pid = (uint32_t)app.processIdentifier;
                for (auto &p : currentDesktop()->getLayout()) {
                  if (p.windowID == pid) {
                    selectedID() = pid;
                    applyLayout();
                    break;
                  }
                }
              }];

  gLaunchObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                NSRunningApplication *app =
                    note.userInfo[NSWorkspaceApplicationKey];
                if (app.activationPolicy != NSApplicationActivationPolicyRegular)
                  return;
                autoAssignWindow((uint32_t)app.processIdentifier);
              }];
}

void RegisterHotkeys(WMRect screenFrame) {
  for (int i = 0; i < NUM_DESKTOPS; i++)
    sDesktops[i] = new Desktop(screenFrame);

  EventTypeSpec hotkeyType = {kEventClassKeyboard, kEventHotKeyPressed};
  InstallApplicationEventHandler(&HotkeyHandler, 1, &hotkeyType, NULL, NULL);

  // Cmd+Shift+Return              — assign focused window to first empty pane
  // Cmd+Shift+Z                   — split selected pane left/right
  // Cmd+Shift+X                   — split selected pane top/bottom
  // Cmd+Shift+Delete              — remove selected window from layout
  // Cmd+Shift+Left/Right/Up/Down  — move selected window to neighbor pane
  // Cmd+Left/Right/Up/Down        — select neighbor pane
  // Cmd+Shift+R                   — rotate windows through pane positions
  // Cmd+Ctrl+Left/Right           — switch to previous/next desktop
  // Cmd+Ctrl+Shift+Left/Right     — move selected window to previous/next desktop
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
  RegisterEventHotKey(kVK_ANSI_R, cmdKey | shiftKey, {0, kHotkeyRotate},
                      GetApplicationEventTarget(), 0, &gHotkeyRotate);
  RegisterEventHotKey(kVK_LeftArrow, cmdKey | controlKey, {0, kHotkeyDesktopPrev},
                      GetApplicationEventTarget(), 0, &gHotkeyDesktopPrev);
  RegisterEventHotKey(kVK_RightArrow, cmdKey | controlKey, {0, kHotkeyDesktopNext},
                      GetApplicationEventTarget(), 0, &gHotkeyDesktopNext);
  RegisterEventHotKey(kVK_LeftArrow, cmdKey | controlKey | shiftKey, {0, kHotkeyMoveWinToPrev},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveWinToPrev);
  RegisterEventHotKey(kVK_RightArrow, cmdKey | controlKey | shiftKey, {0, kHotkeyMoveWinToNext},
                      GetApplicationEventTarget(), 0, &gHotkeyMoveWinToNext);
}

void UnregisterHotkeys() {
  if (gHotkeyAssign)       UnregisterEventHotKey(gHotkeyAssign);
  if (gHotkeySplitH)       UnregisterEventHotKey(gHotkeySplitH);
  if (gHotkeySplitV)       UnregisterEventHotKey(gHotkeySplitV);
  if (gHotkeyRemove)       UnregisterEventHotKey(gHotkeyRemove);
  if (gHotkeyMoveWinL)     UnregisterEventHotKey(gHotkeyMoveWinL);
  if (gHotkeyMoveWinR)     UnregisterEventHotKey(gHotkeyMoveWinR);
  if (gHotkeyMoveWinU)     UnregisterEventHotKey(gHotkeyMoveWinU);
  if (gHotkeyMoveWinD)     UnregisterEventHotKey(gHotkeyMoveWinD);
  if (gHotkeyMoveL)        UnregisterEventHotKey(gHotkeyMoveL);
  if (gHotkeyMoveR)        UnregisterEventHotKey(gHotkeyMoveR);
  if (gHotkeyMoveU)        UnregisterEventHotKey(gHotkeyMoveU);
  if (gHotkeyMoveD)        UnregisterEventHotKey(gHotkeyMoveD);
  if (gHotkeyRotate)         UnregisterEventHotKey(gHotkeyRotate);
  if (gHotkeyDesktopPrev)   UnregisterEventHotKey(gHotkeyDesktopPrev);
  if (gHotkeyDesktopNext)   UnregisterEventHotKey(gHotkeyDesktopNext);
  if (gHotkeyMoveWinToPrev) UnregisterEventHotKey(gHotkeyMoveWinToPrev);
  if (gHotkeyMoveWinToNext) UnregisterEventHotKey(gHotkeyMoveWinToNext);
  if (gActivateObserver) {
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        removeObserver:gActivateObserver];
    gActivateObserver = nil;
  }
  if (gLaunchObserver) {
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        removeObserver:gLaunchObserver];
    gLaunchObserver = nil;
  }
  for (int i = 0; i < NUM_DESKTOPS; i++) {
    delete sDesktops[i];
    sDesktops[i] = nullptr;
  }
}
