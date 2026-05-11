#include "../src/WMRect.hpp"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <vector>

// CGS private API for per-window alpha.
static int (*sCGSMainConnection)(void) = nullptr;
static int (*sCGSSetWindowAlpha)(int, int, float) = nullptr;

static bool cgsFunctionsAvailable() {
  if (sCGSMainConnection)
    return true;
  const char *paths[] = {
      "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
      "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
  };
  for (const char *path : paths) {
    void *h = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (!h)
      continue;
    sCGSMainConnection = (int (*)(void))dlsym(h, "CGSMainConnection");
    sCGSSetWindowAlpha =
        (int (*)(int, int, float))dlsym(h, "CGSSetWindowAlpha");
    if (sCGSMainConnection && sCGSSetWindowAlpha)
      return true;
  }
  return false;
}

WMRect getScreenFrame(int display) {
  NSArray<NSScreen *> *screens = [NSScreen screens];
  NSScreen *screen = screens[display];
  NSRect visible = screen.visibleFrame;
  CGFloat screenHeight = screen.frame.size.height;
  CGFloat barHeight = screenHeight - visible.size.height;
  return {(int)visible.origin.x, (int)visible.origin.y + (int)barHeight,
          (int)visible.size.width, (int)visible.size.height};
}

// ----- Private helpers -----

static pid_t pidForCGWindowID(uint32_t cgwid) {
  CFArrayRef list =
      CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
  if (!list)
    return 0;
  pid_t pid = 0;
  NSString *pidKey = (__bridge NSString *)kCGWindowOwnerPID;
  NSString *numKey = (__bridge NSString *)kCGWindowNumber;
  for (NSDictionary *entry in (__bridge NSArray *)list) {
    if ([entry[numKey] unsignedIntValue] == cgwid) {
      pid = (pid_t)[entry[pidKey] intValue];
      break;
    }
  }
  CFRelease(list);
  return pid;
}

// Returns the AX element for the window with the given CGWindowID. Caller must
// CFRelease.
static AXUIElementRef axWindowForCGWindowID(uint32_t cgwid) {
  pid_t pid = pidForCGWindowID(cgwid);
  if (!pid)
    return nullptr;
  AXUIElementRef appElem = AXUIElementCreateApplication(pid);
  CFArrayRef wins = nullptr;
  AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute,
                                (CFTypeRef *)&wins);

  if (wins) {
    AXUIElementRef result = nullptr;
    CFIndex count = CFArrayGetCount(wins);
    for (CFIndex i = 0; i < count; i++) {
      AXUIElementRef w = (AXUIElementRef)CFArrayGetValueAtIndex(wins, i);
      CFTypeRef wnum = nullptr;
      if (AXUIElementCopyAttributeValue(w, CFSTR("AXWindowID"), &wnum) ==
              kAXErrorSuccess &&
          wnum) {
        bool match = [(__bridge NSNumber *)wnum unsignedIntValue] == cgwid;
        CFRelease(wnum);
        if (match) {
          result = (AXUIElementRef)CFRetain(w);
          break;
        }
      }
    }
    // Fall back to first window if AXWindowID attribute not exposed
    if (!result && count > 0)
      result = (AXUIElementRef)CFRetain(CFArrayGetValueAtIndex(wins, 0));
    CFRelease(wins);
    CFRelease(appElem);
    return result;
  }

  // Final fallback: focused or main window
  AXUIElementRef window = nullptr;
  AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute,
                                (CFTypeRef *)&window);
  if (!window)
    AXUIElementCopyAttributeValue(appElem, kAXMainWindowAttribute,
                                  (CFTypeRef *)&window);
  CFRelease(appElem);
  return window;
}

// ----- Public API -----

// Returns CGWindowIDs for all visible normal windows owned by the given PID.
std::vector<uint32_t> getWindowIDsForPID(uint32_t pid) {
  std::vector<uint32_t> ids;
  CFArrayRef list = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (!list)
    return ids;
  NSString *pidKey = (__bridge NSString *)kCGWindowOwnerPID;
  NSString *layKey = (__bridge NSString *)kCGWindowLayer;
  NSString *numKey = (__bridge NSString *)kCGWindowNumber;
  NSString *bndKey = (__bridge NSString *)kCGWindowBounds;
  for (NSDictionary *entry in (__bridge NSArray *)list) {
    if ([entry[layKey] intValue] != 0)
      continue;
    if ([entry[pidKey] unsignedIntValue] != pid)
      continue;
    NSDictionary *b = entry[bndKey];
    if (!b || [b[@"Width"] floatValue] < 100 || [b[@"Height"] floatValue] < 100)
      continue;
    ids.push_back([entry[numKey] unsignedIntValue]);
  }
  CFRelease(list);
  return ids;
}

// Returns CGWindowIDs for all visible normal windows belonging to regular apps.
std::vector<uint32_t> getAllWindowIDs() {
  std::vector<uint32_t> ids;
  pid_t myPID = getpid();
  NSMutableSet<NSNumber *> *regularPIDs = [NSMutableSet set];
  for (NSRunningApplication *app in
       [[NSWorkspace sharedWorkspace] runningApplications]) {
    if (app.activationPolicy == NSApplicationActivationPolicyRegular &&
        app.processIdentifier != myPID)
      [regularPIDs addObject:@(app.processIdentifier)];
  }
  CFArrayRef list = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (!list)
    return ids;
  NSString *pidKey = (__bridge NSString *)kCGWindowOwnerPID;
  NSString *layKey = (__bridge NSString *)kCGWindowLayer;
  NSString *numKey = (__bridge NSString *)kCGWindowNumber;
  NSString *bndKey = (__bridge NSString *)kCGWindowBounds;
  for (NSDictionary *entry in (__bridge NSArray *)list) {
    if ([entry[layKey] intValue] != 0)
      continue;
    if (![regularPIDs containsObject:entry[pidKey]])
      continue;
    NSDictionary *b = entry[bndKey];
    if (!b || [b[@"Width"] floatValue] < 100 || [b[@"Height"] floatValue] < 100)
      continue;
    ids.push_back([entry[numKey] unsignedIntValue]);
  }
  CFRelease(list);
  return ids;
}

// Returns the CGWindowID of the frontmost app's focused window, or 0.
uint32_t getFrontmostWindowID() {
  NSRunningApplication *front =
      [[NSWorkspace sharedWorkspace] frontmostApplication];
  if (!front)
    return 0;
  pid_t pid = front.processIdentifier;
  AXUIElementRef appElem = AXUIElementCreateApplication(pid);
  AXUIElementRef window = nullptr;
  AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute,
                                (CFTypeRef *)&window);
  if (!window)
    AXUIElementCopyAttributeValue(appElem, kAXMainWindowAttribute,
                                  (CFTypeRef *)&window);
  CFRelease(appElem);
  if (window) {
    CFTypeRef wnum = nullptr;
    AXUIElementCopyAttributeValue(window, CFSTR("AXWindowID"), &wnum);
    CFRelease(window);
    if (wnum) {
      uint32_t cgwid = [(__bridge NSNumber *)wnum unsignedIntValue];
      CFRelease(wnum);
      if (cgwid)
        return cgwid;
    }
  }
  // Fallback for apps that don't expose focused/main window via AX (e.g. Arc,
  // Messages).
  auto ids = getWindowIDsForPID((uint32_t)pid);
  return ids.empty() ? 0 : ids[0];
}

void focusWindow(uint32_t cgwid) {
  pid_t pid = pidForCGWindowID(cgwid);
  if (!pid)
    return;
  NSRunningApplication *app =
      [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
  [app activateWithOptions:0];
  AXUIElementRef window = axWindowForCGWindowID(cgwid);
  if (window) {
    AXUIElementPerformAction(window, kAXRaiseAction);
    CFRelease(window);
  }
}

NSString *launchNewInstance(uint32_t windowID, void (^onSuccess)(uint32_t newPID)) {
  pid_t pid = pidForCGWindowID(windowID);
  if (!pid)
    return nil;
  NSRunningApplication *app =
      [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
  if (!app || !app.bundleURL)
    return nil;
  NSString *bundleID = app.bundleIdentifier;
  NSWorkspaceOpenConfiguration *config =
      [NSWorkspaceOpenConfiguration configuration];
  config.createsNewApplicationInstance = YES;
  [[NSWorkspace sharedWorkspace]
      openApplicationAtURL:app.bundleURL
             configuration:config
         completionHandler:^(NSRunningApplication *newApp, NSError *) {
           if (!newApp)
             return;
           // Always watch the original process. Single-instance apps (e.g. Kitty)
           // create the new window there regardless of what process macOS spawned.
           dispatch_async(dispatch_get_main_queue(), ^{
             onSuccess((uint32_t)newApp.processIdentifier);
           });
         }];
  return bundleID;
}

uint32_t ownerPID(uint32_t cgwid) { return (uint32_t)pidForCGWindowID(cgwid); }

void terminateOwner(uint32_t cgwid) {
  pid_t pid = pidForCGWindowID(cgwid);
  if (!pid)
    return;
  NSRunningApplication *app =
      [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
  [app terminate];
}

void closeWindow(uint32_t cgwid) {
  AXUIElementRef window = axWindowForCGWindowID(cgwid);
  if (!window)
    return;
  AXUIElementRef btn = nullptr;
  AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute,
                                (CFTypeRef *)&btn);
  if (btn) {
    AXUIElementPerformAction(btn, kAXPressAction);
    CFRelease(btn);
  }
  CFRelease(window);
}

// CGWindowID == CGS window number, so this is a trivial passthrough.
void getCGSWindowIDs(const uint32_t *ids, int *out, int count) {
  for (int i = 0; i < count; i++)
    out[i] = (int)ids[i];
}

void setCGSWindowAlpha(int cgwid, float alpha) {
  if (cgwid && cgsFunctionsAvailable())
    sCGSSetWindowAlpha(sCGSMainConnection(), cgwid, alpha);
}

bool applyFrame(uint32_t cgwid, WMRect frame) {
  AXUIElementRef window = axWindowForCGWindowID(cgwid);
  if (!window)
    return false;
  CGPoint pos = {(CGFloat)frame.x, (CGFloat)frame.y};
  CGSize size = {(CGFloat)frame.width, (CGFloat)frame.height};
  AXValueRef posVal = AXValueCreate((AXValueType)kAXValueCGPointType, &pos);
  AXValueRef sizeVal = AXValueCreate((AXValueType)kAXValueCGSizeType, &size);
  AXUIElementSetAttributeValue(window, kAXPositionAttribute, posVal);
  AXUIElementSetAttributeValue(window, kAXSizeAttribute, sizeVal);
  CFRelease(posVal);
  CFRelease(sizeVal);
  CFRelease(window);
  return true;
}
