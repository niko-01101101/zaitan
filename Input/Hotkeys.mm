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

static Desktop *sDesktop = nullptr;
static uint32_t sSelectedID = 0;
static id gLaunchObserver = nil;
static id gActivateObserver = nil;

static void applyLayout() {
  auto layout = sDesktop->getLayout();
  for (auto &p : layout)
    applyFrame(p.windowID, p.frame);
#ifdef DEBUG
  showDebugOverlay(layout, sSelectedID);
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
    sSelectedID = focused;
    break;
  case kHotkeySplitH: {
    uint32_t target = sSelectedID ? sSelectedID : focused;
    NSLog(@"[zaitan] splitH  pid=%u", target);
    if (sDesktop->splitHorizontally(target))
      launchNewInstance(target);
    break;
  }
  case kHotkeySplitV: {
    uint32_t target = sSelectedID ? sSelectedID : focused;
    NSLog(@"[zaitan] splitV  pid=%u", target);
    if (sDesktop->splitVertically(target))
      launchNewInstance(target);
    break;
  }
  case kHotkeyRemove: {
    uint32_t target = sSelectedID ? sSelectedID : focused;
    NSLog(@"[zaitan] remove  pid=%u", target);
    sDesktop->removeWindow(target);
    if (!sDesktop->assignWindow(target))
      closeWindow(target);
    sSelectedID = 0;
    break;
  }
  case kHotkeyMoveWinL:
    NSLog(@"[zaitan] move window left  pid=%u", sSelectedID);
    sDesktop->moveWindowHorizontally(sSelectedID ? sSelectedID : focused,
                                     HorizontalDirection::Left);
    break;
  case kHotkeyMoveWinR:
    NSLog(@"[zaitan] move window right  pid=%u", sSelectedID);
    sDesktop->moveWindowHorizontally(sSelectedID ? sSelectedID : focused,
                                     HorizontalDirection::Right);
    break;
  case kHotkeyMoveWinU:
    NSLog(@"[zaitan] move window up  pid=%u", sSelectedID);
    sDesktop->moveWindowVertically(sSelectedID ? sSelectedID : focused,
                                   VerticalDirection::Up);
    break;
  case kHotkeyMoveWinD:
    NSLog(@"[zaitan] move window down  pid=%u", sSelectedID);
    sDesktop->moveWindowVertically(sSelectedID ? sSelectedID : focused,
                                   VerticalDirection::Down);
    break;
  case kHotkeyMoveL: {
    uint32_t next = sDesktop->moveHorizontally(sSelectedID ? sSelectedID : focused,
                                               HorizontalDirection::Left);
    if (next) { sSelectedID = next; focusWindow(next); }
    NSLog(@"[zaitan] select left  pid=%u next=>%u", sSelectedID, next);
    break;
  }
  case kHotkeyMoveR: {
    uint32_t next = sDesktop->moveHorizontally(sSelectedID ? sSelectedID : focused,
                                               HorizontalDirection::Right);
    if (next) { sSelectedID = next; focusWindow(next); }
    NSLog(@"[zaitan] select right  pid=%u", sSelectedID);
    break;
  }
  case kHotkeyMoveU: {
    uint32_t next = sDesktop->moveVertically(sSelectedID ? sSelectedID : focused,
                                             VerticalDirection::Up);
    if (next) { sSelectedID = next; focusWindow(next); }
    NSLog(@"[zaitan] select up  pid=%u", sSelectedID);
    break;
  }
  case kHotkeyMoveD: {
    uint32_t next = sDesktop->moveVertically(sSelectedID ? sSelectedID : focused,
                                             VerticalDirection::Down);
    if (next) { sSelectedID = next; focusWindow(next); }
    NSLog(@"[zaitan] select down  pid=%u", sSelectedID);
    break;
  }
  }

  applyLayout();
  return noErr;
}

static void autoAssignWindow(uint32_t pid) {
  if (!sDesktop->assignWindow(pid)) {
    auto layout = sDesktop->getLayout();
    if (layout.empty())
      return;
    uint32_t target = sSelectedID ? sSelectedID : layout.back().windowID;
    sDesktop->splitHorizontally(target, pid);
  }
  sSelectedID = pid;
  applyLayout();
  focusWindow(pid);
}

void StartAutoAssign() {
  auto pids = getAllWindowIDs();
  if (!pids.empty()) {
    sDesktop->assignWindow(pids[0]);
    for (size_t i = 1; i < pids.size() && (int)i < MAX_PANES - 1; i++)
      sDesktop->splitHorizontally(pids[i - 1], pids[i]);
    applyLayout();
  }

  gActivateObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserverForName:NSWorkspaceDidActivateApplicationNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
                uint32_t pid = (uint32_t)app.processIdentifier;
                for (auto &p : sDesktop->getLayout()) {
                  if (p.windowID == pid) {
                    sSelectedID = pid;
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

void RegisterHotkeys(Desktop &desktop) {
  sDesktop = &desktop;

  EventTypeSpec hotkeyType = {kEventClassKeyboard, kEventHotKeyPressed};
  InstallApplicationEventHandler(&HotkeyHandler, 1, &hotkeyType, NULL, NULL);

  // Cmd+Shift+Return  — assign focused window to first empty pane
  // Cmd+Shift+Z   — split selected pane left/right
  // Cmd+Shift+X    — split selected pane top/bottom
  // Cmd+Shift+Delete  — remove selected window from layout
  // Cmd+Shift+Left  — move selected window left
  // Cmd+Shift+Right   — move selected window right
  // Cmd+Shift+Down    — move selected window down
  // Cmd+Shift+Up  — move selected window up
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
}
