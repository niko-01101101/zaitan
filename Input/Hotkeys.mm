#include "../config/Config.hpp"
#include "../src/Desktop.hpp"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#include <unordered_set>
#include <vector>

extern uint32_t getFrontmostWindowID();
extern std::vector<uint32_t> getAllWindowIDs();
extern std::vector<uint32_t> getWindowIDsForPID(uint32_t pid);
extern bool applyFrame(uint32_t windowID, WMRect frame);
extern void closeWindow(uint32_t windowID);
extern void terminateOwner(uint32_t windowID);
extern uint32_t ownerPID(uint32_t windowID);
extern NSString *launchNewInstance(uint32_t windowID,
                                   void (^onSuccess)(uint32_t newPID));
extern void focusWindow(uint32_t windowID);
extern void performWithFade(void (^work)(void));
extern void performWithCover(void (^work)(void));
extern void getCGSWindowIDs(const uint32_t *pids, int *cgwids, int count);
extern void setCGSWindowAlpha(int cgwid, float alpha);

#ifdef DEBUG
extern void showDebugOverlay(const std::vector<WindowPlacement> &placements,
                             uint32_t selectedID);
#endif

static constexpr int NUM_DESKTOPS = 4;
static Desktop *sDesktops[NUM_DESKTOPS] = {};
static int sCurrentDesktopIndex = 0;
static uint32_t sSelectedIDs[NUM_DESKTOPS] = {};
static Config sConfig;
static WMRect sScreenFrame;
static id gLaunchObserver = nil;
static id gActivateObserver = nil;
// Bundle IDs currently being claimed by a split hotkey; autoAssignWindow skips
// them.
static NSMutableSet<NSString *> *sSplitPendingBundleIDs;

static Desktop *currentDesktop() { return sDesktops[sCurrentDesktopIndex]; }
static uint32_t &selectedID() { return sSelectedIDs[sCurrentDesktopIndex]; }

static WMRect insetFrame(WMRect f, int gap) {
  int half = gap / 2;
  return {f.x + half, f.y + half, f.width - gap, f.height - gap};
}

static WMRect visualFrame(WMRect f) {
  return sConfig.gapSize > 0 ? insetFrame(f, sConfig.gapSize) : f;
}

struct WMRectF {
  float x, y, w, h;
};

static WMRectF toF(WMRect r) {
  return {(float)r.x, (float)r.y, (float)r.width, (float)r.height};
}
static WMRect toI(WMRectF r) {
  return {(int)r.x, (int)r.y, (int)r.w, (int)r.h};
}

static WMRectF lerpF(WMRectF a, WMRectF b, float t) {
  return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.w + (b.w - a.w) * t,
          a.h + (b.h - a.h) * t};
}

static bool nearF(WMRectF a, WMRectF b) {
  return fabsf(a.x - b.x) < 2.f && fabsf(a.y - b.y) < 2.f;
}

static void applyLayout() {
  auto layout = currentDesktop()->getLayout();
  std::vector<WindowPlacement> applied;
  applied.reserve(layout.size());
  for (auto &p : layout) {
    WMRect f =
        sConfig.gapSize > 0 ? insetFrame(p.frame, sConfig.gapSize) : p.frame;
    applyFrame(p.windowID, f);
    applied.push_back({p.windowID, f});
  }
#ifdef DEBUG
  showDebugOverlay(applied, selectedID());
#endif
}

static void applyLayoutAnimated(const std::vector<WindowPlacement> &before) {
  auto after = currentDesktop()->getLayout();

  using AP = std::pair<uint32_t, WMRectF>;
  __block std::vector<AP> cur;
  std::vector<WMRectF> tgts;

  for (auto &p : after) {
    WMRectF target = toF(visualFrame(p.frame));
    WMRectF start = target;
    for (auto &b : before)
      if (b.windowID == p.windowID) {
        start = toF(visualFrame(b.frame));
        break;
      }
    cur.push_back({p.windowID, start});
    tgts.push_back(target);
  }

  __block std::vector<WMRectF> btgts = tgts;
  static const float kFactor = 0.5f;
  [NSTimer
      scheduledTimerWithTimeInterval:1.0 / 120.0
                             repeats:YES
                               block:^(NSTimer *t) {
                                 bool done = true;
                                 for (size_t i = 0; i < cur.size(); i++) {
                                   cur[i].second =
                                       lerpF(cur[i].second, btgts[i], kFactor);
                                   applyFrame(cur[i].first, toI(cur[i].second));
                                   if (!nearF(cur[i].second, btgts[i]))
                                     done = false;
                                 }
                                 if (done) {
                                   for (size_t i = 0; i < cur.size(); i++)
                                     applyFrame(cur[i].first, toI(btgts[i]));
#ifdef DEBUG
                                   std::vector<WindowPlacement> applied;
                                   for (size_t i = 0; i < cur.size(); i++)
                                     applied.push_back(
                                         {cur[i].first, toI(btgts[i])});
                                   showDebugOverlay(applied, selectedID());
#endif
                                   [t invalidate];
                                 }
                               }];
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

static void switchToDesktop(int newIndex, int direction) {
#ifdef DEBUG
  showDebugOverlay({}, 0);
#endif

  auto exitLayout = currentDesktop()->getLayout();

  sCurrentDesktopIndex = newIndex;
  __block uint32_t toFocus = selectedID();
  if (!toFocus) {
    auto lay = currentDesktop()->getLayout();
    if (!lay.empty())
      toFocus = lay.back().windowID;
  }
  if (toFocus)
    selectedID() = toFocus;
  auto enterLayout = currentDesktop()->getLayout();

  const float kInterval = 1.0 / 120.0;

  // --- None: instant switch under a cover flash ---
  if (sConfig.transitionEffect == TransitionEffect::None) {
    performWithCover(^{
      for (auto &p : exitLayout)
        applyFrame(p.windowID, {100000, 100000, p.frame.width, p.frame.height});
      for (auto &p : enterLayout)
        applyFrame(p.windowID, visualFrame(p.frame));
    });
    if (toFocus)
      focusWindow(toFocus);
#ifdef DEBUG
    std::vector<WindowPlacement> applied;
    for (auto &p : enterLayout)
      applied.push_back({p.windowID, visualFrame(p.frame)});
    showDebugOverlay(applied, toFocus);
#endif
    return;
  }

  // --- Fade: entering windows scale from 90% and fade in using the same lerp
  // as slide ---
  if (sConfig.transitionEffect == TransitionEffect::Fade) {
    std::vector<uint32_t> enterPIDs;
    for (auto &p : enterLayout)
      enterPIDs.push_back(p.windowID);
    std::vector<int> cgwids(enterPIDs.size(), 0);
    getCGSWindowIDs(enterPIDs.data(), cgwids.data(), (int)enterPIDs.size());

    for (int wid : cgwids)
      setCGSWindowAlpha(wid, 0.0f);

    for (auto &p : exitLayout)
      applyFrame(p.windowID, {100000, 100000, p.frame.width, p.frame.height});

    static const float kStartScale = 0.95f;
    static const float kFactor = 0.8f;

    __block std::vector<WindowPlacement> enterFinal;
    __block std::vector<WMRectF> enterCur;
    for (size_t i = 0; i < enterLayout.size(); i++) {
      WMRect fin = visualFrame(enterLayout[i].frame);
      WMRectF f = toF(fin);
      WMRectF start = {f.x + f.w * (1.0f - kStartScale) * 0.5f,
                       f.y + f.h * (1.0f - kStartScale) * 0.5f,
                       f.w * kStartScale, f.h * kStartScale};
      applyFrame(enterLayout[i].windowID, toI(start));
      enterFinal.push_back({enterLayout[i].windowID, fin});
      enterCur.push_back(start);
    }
    if (toFocus)
      focusWindow(toFocus);

    __block float curAlpha = 0.0f;

    [NSTimer
        scheduledTimerWithTimeInterval:kInterval
                               repeats:YES
                                 block:^(NSTimer *t) {
                                   bool done = true;
                                   curAlpha += (1.0f - curAlpha) * kFactor;
                                   for (size_t i = 0; i < enterFinal.size();
                                        i++) {
                                     WMRectF fin = toF(enterFinal[i].frame);
                                     enterCur[i] =
                                         lerpF(enterCur[i], fin, kFactor);
                                     applyFrame(enterFinal[i].windowID,
                                                toI(enterCur[i]));
                                     setCGSWindowAlpha(cgwids[i], curAlpha);
                                     if (!nearF(enterCur[i], fin))
                                       done = false;
                                   }
                                   if (done) {
                                     for (size_t i = 0; i < enterFinal.size();
                                          i++) {
                                       applyFrame(enterFinal[i].windowID,
                                                  enterFinal[i].frame);
                                       setCGSWindowAlpha(cgwids[i], 1.0f);
                                     }
#ifdef DEBUG
                                     showDebugOverlay(enterFinal, toFocus);
#endif
                                     [t invalidate];
                                   }
                                 }];
    return;
  }

  // --- Slide (default): exit windows slide off, enter windows slide in ---
  using AP = std::pair<uint32_t, WMRectF>;
  // Both directions use a positive x offset to avoid macOS clamping negative
  // coords.
  float slideX = (float)(sScreenFrame.width);

  __block std::vector<AP> exitAnim;
  __block std::vector<WMRectF> exitTgts;
  for (auto &p : exitLayout) {
    WMRectF cur = toF(visualFrame(p.frame));
    exitAnim.push_back({p.windowID, cur});
    exitTgts.push_back({cur.x + slideX, cur.y, cur.w, cur.h});
  }

  __block std::vector<AP> enterAnim;
  __block std::vector<WMRectF> enterTgts;
  for (auto &p : enterLayout) {
    WMRectF fin = toF(visualFrame(p.frame));
    WMRectF start = {fin.x + slideX, fin.y, fin.w, fin.h};
    enterAnim.push_back({p.windowID, start});
    enterTgts.push_back(fin);
    applyFrame(p.windowID, toI(start));
  }

  if (toFocus)
    focusWindow(toFocus);

  static const float kFactor = 0.5f;

  [NSTimer
      scheduledTimerWithTimeInterval:kInterval
                             repeats:YES
                               block:^(NSTimer *t) {
                                 bool done = true;
                                 for (size_t i = 0; i < exitAnim.size(); i++) {
                                   WMRectF &cur = exitAnim[i].second;
                                   cur = lerpF(cur, exitTgts[i], kFactor);
                                   applyFrame(exitAnim[i].first, toI(cur));
                                   if (!nearF(cur, exitTgts[i]))
                                     done = false;
                                 }
                                 for (size_t i = 0; i < enterAnim.size(); i++) {
                                   WMRectF &cur = enterAnim[i].second;
                                   cur = lerpF(cur, enterTgts[i], kFactor);
                                   applyFrame(enterAnim[i].first, toI(cur));
                                   if (!nearF(cur, enterTgts[i]))
                                     done = false;
                                 }
                                 if (done) {
                                   for (size_t i = 0; i < exitAnim.size(); i++)
                                     applyFrame(exitAnim[i].first,
                                                {100000, 100000,
                                                 (int)exitTgts[i].w,
                                                 (int)exitTgts[i].h});
                                   for (size_t i = 0; i < enterAnim.size(); i++)
                                     applyFrame(enterAnim[i].first,
                                                toI(enterTgts[i]));
#ifdef DEBUG
                                   std::vector<WindowPlacement> applied;
                                   for (size_t i = 0; i < enterAnim.size(); i++)
                                     applied.push_back({enterAnim[i].first,
                                                        toI(enterTgts[i])});
                                   showDebugOverlay(applied, toFocus);
#endif
                                   [t invalidate];
                                 }
                               }];
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
  kHotkeyReloadConfig = 18,
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
static EventHotKeyRef gHotkeyReloadConfig = nullptr;

static void registerConfigHotkeys(const Config &c) {
  auto reg = [](HotkeyDef h, UInt32 id, EventHotKeyRef *ref) {
    RegisterEventHotKey(h.keyCode, h.modifiers, {0, id},
                        GetApplicationEventTarget(), 0, ref);
  };
  reg(c.assign, kHotkeyAssign, &gHotkeyAssign);
  reg(c.splitH, kHotkeySplitH, &gHotkeySplitH);
  reg(c.splitV, kHotkeySplitV, &gHotkeySplitV);
  reg(c.remove, kHotkeyRemove, &gHotkeyRemove);
  reg(c.moveWinL, kHotkeyMoveWinL, &gHotkeyMoveWinL);
  reg(c.moveWinR, kHotkeyMoveWinR, &gHotkeyMoveWinR);
  reg(c.moveWinU, kHotkeyMoveWinU, &gHotkeyMoveWinU);
  reg(c.moveWinD, kHotkeyMoveWinD, &gHotkeyMoveWinD);
  reg(c.moveL, kHotkeyMoveL, &gHotkeyMoveL);
  reg(c.moveR, kHotkeyMoveR, &gHotkeyMoveR);
  reg(c.moveU, kHotkeyMoveU, &gHotkeyMoveU);
  reg(c.moveD, kHotkeyMoveD, &gHotkeyMoveD);
  reg(c.rotate, kHotkeyRotate, &gHotkeyRotate);
  reg(c.desktopPrev, kHotkeyDesktopPrev, &gHotkeyDesktopPrev);
  reg(c.desktopNext, kHotkeyDesktopNext, &gHotkeyDesktopNext);
  reg(c.moveWinToPrev, kHotkeyMoveWinToPrev, &gHotkeyMoveWinToPrev);
  reg(c.moveWinToNext, kHotkeyMoveWinToNext, &gHotkeyMoveWinToNext);
}

static void unregisterConfigHotkeys() {
  auto unreg = [](EventHotKeyRef &ref) {
    if (ref) {
      UnregisterEventHotKey(ref);
      ref = nullptr;
    }
  };
  unreg(gHotkeyAssign);
  unreg(gHotkeySplitH);
  unreg(gHotkeySplitV);
  unreg(gHotkeyRemove);
  unreg(gHotkeyMoveWinL);
  unreg(gHotkeyMoveWinR);
  unreg(gHotkeyMoveWinU);
  unreg(gHotkeyMoveWinD);
  unreg(gHotkeyMoveL);
  unreg(gHotkeyMoveR);
  unreg(gHotkeyMoveU);
  unreg(gHotkeyMoveD);
  unreg(gHotkeyRotate);
  unreg(gHotkeyDesktopPrev);
  unreg(gHotkeyDesktopNext);
  unreg(gHotkeyMoveWinToPrev);
  unreg(gHotkeyMoveWinToNext);
}

static void whenWindowForPIDAppears(uint32_t pid,
                                    void (^callback)(uint32_t cgwid));
static void watchForNewWindowInPID(uint32_t pid,
                                   void (^callback)(uint32_t cgwid));

static OSStatus HotkeyHandler(EventHandlerCallRef nextHandler, EventRef event,
                              void *userData) {
  EventHotKeyID hotkeyID;
  GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                    sizeof(EventHotKeyID), NULL, &hotkeyID);

  uint32_t focused = getFrontmostWindowID();
  bool needsCover = false;
  switch (hotkeyID.id) {
  case kHotkeyAssign:
    NSLog(@"[zaitan] assign  cgwid=%u", focused);
    currentDesktop()->assignWindow(focused);
    selectedID() = focused;
    needsCover = true;
    break;
  case kHotkeySplitH: {
    uint32_t target = selectedID() ? selectedID() : focused;
    int capturedIdx = sCurrentDesktopIndex;
    NSLog(@"[zaitan] splitH  cgwid=%u", target);
    __block NSString *bundleID = nil;
    bundleID = launchNewInstance(target, ^(uint32_t newPID) {
      watchForNewWindowInPID(newPID, ^(uint32_t newCGWID) {
        NSString *bid = bundleID;
        if (bid)
          [sSplitPendingBundleIDs removeObject:bid];
        for (int i = 0; i < NUM_DESKTOPS; i++)
          sDesktops[i]->removeWindow(newCGWID);
        applyFrame(newCGWID, {100000, 100000, 100, 100});
        Desktop *desk = sDesktops[capturedIdx];
        if (!desk->splitHorizontally(target, newCGWID))
          return;
        sSelectedIDs[capturedIdx] = newCGWID;
        if (capturedIdx == sCurrentDesktopIndex) {
          applyLayout();
          focusWindow(newCGWID);
        }
      });
    });
    if (bundleID)
      [sSplitPendingBundleIDs addObject:bundleID];
    break;
  }
  case kHotkeySplitV: {
    uint32_t target = selectedID() ? selectedID() : focused;
    int capturedIdx = sCurrentDesktopIndex;
    NSLog(@"[zaitan] splitV  cgwid=%u", target);
    __block NSString *bundleID = nil;
    bundleID = launchNewInstance(target, ^(uint32_t newPID) {
      watchForNewWindowInPID(newPID, ^(uint32_t newCGWID) {
        NSString *bid = bundleID;
        if (bid)
          [sSplitPendingBundleIDs removeObject:bid];
        for (int i = 0; i < NUM_DESKTOPS; i++)
          sDesktops[i]->removeWindow(newCGWID);
        applyFrame(newCGWID, {100000, 100000, 100, 100});
        Desktop *desk = sDesktops[capturedIdx];
        if (!desk->splitVertically(target, newCGWID))
          return;
        sSelectedIDs[capturedIdx] = newCGWID;
        if (capturedIdx == sCurrentDesktopIndex) {
          applyLayout();
          focusWindow(newCGWID);
        }
      });
    });
    if (bundleID)
      [sSplitPendingBundleIDs addObject:bundleID];
    break;
  }
  case kHotkeyRemove: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] remove  cgwid=%u", target);
    uint32_t pid = ownerPID(target);
    currentDesktop()->removeWindow(target);
    bool hasOtherManagedWindows = false;
    if (pid) {
      for (int i = 0; i < NUM_DESKTOPS && !hasOtherManagedWindows; i++) {
        for (auto &p : sDesktops[i]->getLayout()) {
          if (ownerPID(p.windowID) == pid) {
            hasOtherManagedWindows = true;
            break;
          }
        }
      }
    }
    if (hasOtherManagedWindows)
      closeWindow(target);
    else
      terminateOwner(target);
    selectedID() = 0;
    needsCover = true;
    break;
  }
  case kHotkeyMoveWinL: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] move window left  cgwid=%u", target);
    auto before = currentDesktop()->getLayout();
    currentDesktop()->moveWindowHorizontally(target, HorizontalDirection::Left);
    applyLayoutAnimated(before);
    return noErr;
  }
  case kHotkeyMoveWinR: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] move window right  cgwid=%u", target);
    auto before = currentDesktop()->getLayout();
    currentDesktop()->moveWindowHorizontally(target,
                                             HorizontalDirection::Right);
    applyLayoutAnimated(before);
    return noErr;
  }
  case kHotkeyMoveWinU: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] move window up  cgwid=%u", target);
    auto before = currentDesktop()->getLayout();
    currentDesktop()->moveWindowVertically(target, VerticalDirection::Up);
    applyLayoutAnimated(before);
    return noErr;
  }
  case kHotkeyMoveWinD: {
    uint32_t target = selectedID() ? selectedID() : focused;
    NSLog(@"[zaitan] move window down  cgwid=%u", target);
    auto before = currentDesktop()->getLayout();
    currentDesktop()->moveWindowVertically(target, VerticalDirection::Down);
    applyLayoutAnimated(before);
    return noErr;
  }
  case kHotkeyMoveL: {
    uint32_t next = currentDesktop()->moveHorizontally(
        selectedID() ? selectedID() : focused, HorizontalDirection::Left);
    if (next) {
      selectedID() = next;
      focusWindow(next);
    }
    NSLog(@"[zaitan] select left  cgwid=%u next=>%u", selectedID(), next);
    break;
  }
  case kHotkeyMoveR: {
    uint32_t next = currentDesktop()->moveHorizontally(
        selectedID() ? selectedID() : focused, HorizontalDirection::Right);
    if (next) {
      selectedID() = next;
      focusWindow(next);
    }
    NSLog(@"[zaitan] select right  cgwid=%u", selectedID());
    break;
  }
  case kHotkeyMoveU: {
    uint32_t next = currentDesktop()->moveVertically(
        selectedID() ? selectedID() : focused, VerticalDirection::Up);
    if (next) {
      selectedID() = next;
      focusWindow(next);
    }
    NSLog(@"[zaitan] select up  cgwid=%u", selectedID());
    break;
  }
  case kHotkeyMoveD: {
    uint32_t next = currentDesktop()->moveVertically(
        selectedID() ? selectedID() : focused, VerticalDirection::Down);
    if (next) {
      selectedID() = next;
      focusWindow(next);
    }
    NSLog(@"[zaitan] select down  cgwid=%u", selectedID());
    break;
  }
  case kHotkeyRotate:
    NSLog(@"[zaitan] flip splits");
    currentDesktop()->flipSplits();
    needsCover = true;
    break;
  case kHotkeyReloadConfig:
    NSLog(@"[zaitan] reload config");
    unregisterConfigHotkeys();
    sConfig = loadConfig();
    registerConfigHotkeys(sConfig);
    applyLayout();
    return noErr;
  case kHotkeyDesktopPrev: {
    int prevIdx = (sCurrentDesktopIndex + NUM_DESKTOPS - 1) % NUM_DESKTOPS;
    bool emptyOk = sConfig.firstDesktopEmpty && prevIdx == 0;
    if (sDesktops[prevIdx]->getLayout().empty() && !emptyOk)
      return noErr;
    NSLog(@"[zaitan] switch to desktop %d", prevIdx);
    switchToDesktop(prevIdx, -1);
    return noErr;
  }
  case kHotkeyDesktopNext: {
    int nextIdx = (sCurrentDesktopIndex + 1) % NUM_DESKTOPS;
    bool emptyOk = sConfig.firstDesktopEmpty && nextIdx == 0;
    if (sDesktops[nextIdx]->getLayout().empty() && !emptyOk)
      return noErr;
    NSLog(@"[zaitan] switch to desktop %d", nextIdx);
    switchToDesktop(nextIdx, +1);
    return noErr;
  }
  case kHotkeyMoveWinToPrev: {
    uint32_t target = selectedID() ? selectedID() : focused;
    int prevIdx = (sCurrentDesktopIndex + NUM_DESKTOPS - 1) % NUM_DESKTOPS;
    NSLog(@"[zaitan] move window to desktop %d  cgwid=%u", prevIdx, target);
    currentDesktop()->removeWindow(target);
    addWindowToDesktop(sDesktops[prevIdx], target);
    selectedID() = 0;
    sSelectedIDs[prevIdx] = target;
    switchToDesktop(prevIdx, -1);
    return noErr;
  }
  case kHotkeyMoveWinToNext: {
    uint32_t target = selectedID() ? selectedID() : focused;
    int nextIdx = (sCurrentDesktopIndex + 1) % NUM_DESKTOPS;
    NSLog(@"[zaitan] move window to desktop %d  cgwid=%u", nextIdx, target);
    currentDesktop()->removeWindow(target);
    addWindowToDesktop(sDesktops[nextIdx], target);
    selectedID() = 0;
    sSelectedIDs[nextIdx] = target;
    switchToDesktop(nextIdx, +1);
    return noErr;
  }
  }

  if (needsCover)
    performWithCover(^{
      applyLayout();
    });
  else
    applyLayout();
  return noErr;
}

struct WindowObserverCtx {
  AXObserverRef observer;
  uint32_t pid;
  void (^callback)(uint32_t cgwid);
};

static void onWindowForPID(AXObserverRef observer, AXUIElementRef element,
                           CFStringRef notif, void *refcon) {
  auto *ctx = static_cast<WindowObserverCtx *>(refcon);
  uint32_t pid = ctx->pid;

  // Get CGWindowID from element (kAXWindowCreatedNotification) or main window
  // (kAXMainWindowChangedNotification).
  uint32_t cgwid = 0;
  AXUIElementRef winElem = nullptr;
  if (CFEqual(notif, kAXWindowCreatedNotification)) {
    winElem = (AXUIElementRef)CFRetain(element);
  } else {
    AXUIElementCopyAttributeValue(element, kAXMainWindowAttribute,
                                  (CFTypeRef *)&winElem);
  }
  if (winElem) {
    CFTypeRef wnum = nullptr;
    if (AXUIElementCopyAttributeValue(winElem, CFSTR("AXWindowID"), &wnum) ==
            kAXErrorSuccess &&
        wnum) {
      cgwid = [(__bridge NSNumber *)wnum unsignedIntValue];
      CFRelease(wnum);
    }
    CFRelease(winElem);
  }
  if (!cgwid)
    return; // window ID not available yet; keep observing

  // Remove both notifications to prevent re-entry.
  AXUIElementRef appElem = AXUIElementCreateApplication((pid_t)pid);
  AXObserverRemoveNotification(observer, appElem, kAXWindowCreatedNotification);
  AXObserverRemoveNotification(observer, appElem,
                               kAXMainWindowChangedNotification);
  CFRelease(appElem);

  void (^cb)(uint32_t) = ctx->callback;
  dispatch_async(dispatch_get_main_queue(), ^{
    CFRunLoopRemoveSource(CFRunLoopGetMain(),
                          AXObserverGetRunLoopSource(observer),
                          kCFRunLoopDefaultMode);
    CFRelease(observer);
    delete ctx;
    cb(cgwid);
  });
}

// Watches for a NEW window from pid — one not already in any desktop layout.
// Pre-checks CGWindowList first, then tries an AX observer. If AX setup fails
// (common for brand-new processes whose AX server isn't ready yet), falls back
// to polling CGWindowList every 100ms for up to 10 seconds.
static void watchForNewWindowInPID(uint32_t pid,
                                   void (^callback)(uint32_t cgwid)) {
  // Pre-check: find a window from this PID that is not in any desktop layout.
  auto allWindows = getWindowIDsForPID(pid);
  for (uint32_t wid : allWindows) {
    bool inLayout = false;
    for (int i = 0; i < NUM_DESKTOPS; i++) {
      if (sDesktops[i]->containsWindow(wid)) {
        inLayout = true;
        break;
      }
    }
    if (!inLayout) {
      dispatch_async(dispatch_get_main_queue(), ^{
        callback(wid);
      });
      return;
    }
  }

  // Try AX observer (works well for already-running processes).
  auto *ctx = new WindowObserverCtx();
  ctx->pid = pid;
  ctx->callback = callback;
  bool axOk = false;
  if (AXObserverCreate((pid_t)pid, onWindowForPID, &ctx->observer) ==
      kAXErrorSuccess) {
    AXUIElementRef appElem = AXUIElementCreateApplication((pid_t)pid);
    axOk = AXObserverAddNotification(ctx->observer, appElem,
                                     kAXWindowCreatedNotification,
                                     ctx) == kAXErrorSuccess;
    CFRelease(appElem);
    if (axOk)
      CFRunLoopAddSource(CFRunLoopGetMain(),
                         AXObserverGetRunLoopSource(ctx->observer),
                         kCFRunLoopDefaultMode);
    else
      CFRelease(ctx->observer);
  }
  if (axOk)
    return; // onWindowForPID will clean up ctx

  // AX setup failed — poll every 100ms for up to 10 seconds.
  __block void (^pollCb)(uint32_t) = ctx->callback;
  delete ctx;
  __block int remaining = 100;
  [NSTimer
      scheduledTimerWithTimeInterval:0.1
                             repeats:YES
                               block:^(NSTimer *t) {
                                 auto wins = getWindowIDsForPID(pid);
                                 for (uint32_t wid : wins) {
                                   bool inLayout = false;
                                   for (int i = 0; i < NUM_DESKTOPS; i++)
                                     if (sDesktops[i]->containsWindow(wid)) {
                                       inLayout = true;
                                       break;
                                     }
                                   if (!inLayout) {
                                     [t invalidate];
                                     void (^fn)(uint32_t) = pollCb;
                                     pollCb = nil;
                                     fn(wid);
                                     return;
                                   }
                                 }
                                 if (--remaining <= 0)
                                   [t invalidate];
                               }];
}

static void whenWindowForPIDAppears(uint32_t pid,
                                    void (^callback)(uint32_t cgwid)) {
  // Pre-check: window may already be visible in CGWindowList.
  auto existing = getWindowIDsForPID(pid);
  if (!existing.empty()) {
    uint32_t cgwid = existing[0];
    dispatch_async(dispatch_get_main_queue(), ^{
      callback(cgwid);
    });
    return;
  }
  // Pre-check: window may already be in the AX tree but not yet on screen.
  AXUIElementRef checkElem = AXUIElementCreateApplication((pid_t)pid);
  CFArrayRef axWins = nullptr;
  AXUIElementCopyAttributeValue(checkElem, kAXWindowsAttribute,
                                (CFTypeRef *)&axWins);
  CFRelease(checkElem);
  if (axWins) {
    uint32_t cgwid = 0;
    for (CFIndex i = 0, n = CFArrayGetCount(axWins); i < n && !cgwid; i++) {
      AXUIElementRef w = (AXUIElementRef)CFArrayGetValueAtIndex(axWins, i);
      CFTypeRef wnum = nullptr;
      if (AXUIElementCopyAttributeValue(w, CFSTR("AXWindowID"), &wnum) ==
              kAXErrorSuccess &&
          wnum) {
        cgwid = [(__bridge NSNumber *)wnum unsignedIntValue];
        CFRelease(wnum);
      }
    }
    CFRelease(axWins);
    if (cgwid) {
      dispatch_async(dispatch_get_main_queue(), ^{
        callback(cgwid);
      });
      return;
    }
  }
  // Fall back to AX observer for windows that haven't appeared yet.
  auto *ctx = new WindowObserverCtx();
  ctx->pid = pid;
  ctx->callback = callback;
  if (AXObserverCreate((pid_t)pid, onWindowForPID, &ctx->observer) !=
      kAXErrorSuccess) {
    delete ctx;
    return;
  }
  AXUIElementRef appElem = AXUIElementCreateApplication((pid_t)pid);
  bool ok = AXObserverAddNotification(ctx->observer, appElem,
                                      kAXWindowCreatedNotification,
                                      ctx) == kAXErrorSuccess;
  ok = AXObserverAddNotification(ctx->observer, appElem,
                                 kAXMainWindowChangedNotification,
                                 ctx) == kAXErrorSuccess ||
       ok;
  CFRelease(appElem);
  if (!ok) {
    CFRelease(ctx->observer);
    delete ctx;
    return;
  }
  CFRunLoopAddSource(CFRunLoopGetMain(),
                     AXObserverGetRunLoopSource(ctx->observer),
                     kCFRunLoopDefaultMode);
}

static void autoAssignWindow(uint32_t pid) {
  bool onEmptyDesktop = sConfig.firstDesktopEmpty && sCurrentDesktopIndex == 0;
  int destIdx = onEmptyDesktop ? 1 : sCurrentDesktopIndex;
  Desktop *dest = sDesktops[destIdx];

  void (^doAssign)(uint32_t) = ^(uint32_t cgwid) {
    for (int i = 0; i < NUM_DESKTOPS; i++)
      if (sDesktops[i]->containsWindow(cgwid))
        return;

    applyFrame(cgwid, {100000, 100000, 100, 100});
    if (!dest->assignWindow(cgwid)) {
      auto layout = dest->getLayout();
      if (layout.empty())
        return;
      uint32_t tgt = sSelectedIDs[destIdx] ? sSelectedIDs[destIdx]
                                           : layout.back().windowID;
      WMRect frame = {};
      for (auto &p : layout)
        if (p.windowID == tgt) {
          frame = p.frame;
          break;
        }
      if (preferredSplit(frame) == SplitDirection::Horizontal)
        dest->splitHorizontally(tgt, cgwid);
      else
        dest->splitVertically(tgt, cgwid);
    }
    sSelectedIDs[destIdx] = cgwid;
    if (onEmptyDesktop)
      return;
    applyLayout();
    focusWindow(cgwid);
  };

  auto existing = getWindowIDsForPID(pid);
  if (!existing.empty())
    doAssign(existing[0]);
  else
    whenWindowForPIDAppears(pid, doAssign);
}

void StartAutoAssign() {
  int assignIdx = sConfig.firstDesktopEmpty ? 1 : 0;
  sCurrentDesktopIndex = assignIdx;

  auto pids = getAllWindowIDs();
  if (!pids.empty()) {
    currentDesktop()->assignWindow(pids[0]);
    for (size_t i = 1; i < pids.size() && (int)i < MAX_PANES - 1; i++) {
      auto layout = currentDesktop()->getLayout();
      WMRect frame = {};
      for (auto &p : layout)
        if (p.windowID == pids[i - 1]) {
          frame = p.frame;
          break;
        }
      if (preferredSplit(frame) == SplitDirection::Horizontal)
        currentDesktop()->splitHorizontally(pids[i - 1], pids[i]);
      else
        currentDesktop()->splitVertically(pids[i - 1], pids[i]);
    }
    selectedID() = pids[0];

    if (sConfig.firstDesktopEmpty) {
      // Park windows off-screen and open on the empty desktop 0.
      hideDesktopWindows(sDesktops[assignIdx]);
      sCurrentDesktopIndex = 0;
    } else {
      applyLayout();
      focusWindow(pids[0]);
    }
  }

  gActivateObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserverForName:NSWorkspaceDidActivateApplicationNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                uint32_t cgwid = getFrontmostWindowID();
                if (!cgwid)
                  return;
                for (auto &p : currentDesktop()->getLayout()) {
                  if (p.windowID == cgwid) {
                    selectedID() = cgwid;
                    applyLayout();
                    return;
                  }
                }
                for (int i = 0; i < NUM_DESKTOPS; i++) {
                  if (i == sCurrentDesktopIndex)
                    continue;
                  for (auto &p : sDesktops[i]->getLayout()) {
                    if (p.windowID == cgwid) {
                      sSelectedIDs[i] = cgwid;
                      int dir = (i > sCurrentDesktopIndex) ? +1 : -1;
                      switchToDesktop(i, dir);
                      return;
                    }
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
                if (app.activationPolicy !=
                    NSApplicationActivationPolicyRegular)
                  return;
                NSString *bid = app.bundleIdentifier;
                if (bid && [sSplitPendingBundleIDs containsObject:bid]) {
                  [sSplitPendingBundleIDs removeObject:bid];
                  return; // split hotkey owns this launch
                }
                autoAssignWindow((uint32_t)app.processIdentifier);
              }];
}

void RegisterHotkeys(WMRect screenFrame, Config config) {
  sConfig = config;
  sScreenFrame = screenFrame;
  sSplitPendingBundleIDs = [[NSMutableSet alloc] init];

  for (int i = 0; i < NUM_DESKTOPS; i++)
    sDesktops[i] = new Desktop(screenFrame);

  EventTypeSpec hotkeyType = {kEventClassKeyboard, kEventHotKeyPressed};
  InstallApplicationEventHandler(&HotkeyHandler, 1, &hotkeyType, NULL, NULL);

  // Reload hotkey is hardcoded so it always works regardless of config.
  RegisterEventHotKey(kVK_ANSI_R, cmdKey | controlKey | shiftKey,
                      {0, kHotkeyReloadConfig}, GetApplicationEventTarget(), 0,
                      &gHotkeyReloadConfig);
  registerConfigHotkeys(config);
}

void UnregisterHotkeys() {
  unregisterConfigHotkeys();
  if (gHotkeyReloadConfig) {
    UnregisterEventHotKey(gHotkeyReloadConfig);
    gHotkeyReloadConfig = nullptr;
  }
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
