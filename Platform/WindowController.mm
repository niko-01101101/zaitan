#include "../src/WMRect.hpp"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <vector>

WMRect getScreenFrame(int display) {
  NSArray<NSScreen *> *screens = [NSScreen screens];
  NSScreen *screen = screens[display];
  NSRect visible = screen.visibleFrame;
  CGFloat screenHeight = screen.frame.size.height;
  CGFloat barHeight = screenHeight - visible.size.height;
  // NSScreen uses bottom-left origin; AX API uses top-left origin
  return {(int)visible.origin.x, (int)visible.origin.y + (int)barHeight,
          (int)visible.size.width, (int)visible.size.height};
}

std::vector<uint32_t> getAllWindowIDs() {
  std::vector<uint32_t> ids;
  pid_t myPID = getpid();
  for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
    if (app.activationPolicy != NSApplicationActivationPolicyRegular ||
        app.processIdentifier == myPID)
      continue;
    // Only include apps with an accessible window so empty pane slots aren't wasted
    AXUIElementRef axApp = AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementRef window = nullptr;
    AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute, (CFTypeRef *)&window);
    if (window) {
      ids.push_back((uint32_t)app.processIdentifier);
      CFRelease(window);
    }
    CFRelease(axApp);
  }
  return ids;
}

void focusWindow(uint32_t windowID) {
  NSRunningApplication *app =
      [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)windowID];
  [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

void launchNewInstance(uint32_t windowID, void (^onSuccess)(uint32_t newPID)) {
  NSRunningApplication *app =
      [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)windowID];
  if (!app || !app.bundleURL)
    return;
  NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
  config.createsNewApplicationInstance = YES;
  [[NSWorkspace sharedWorkspace] openApplicationAtURL:app.bundleURL
                                        configuration:config
                                    completionHandler:^(NSRunningApplication *newApp, NSError *) {
    if (!newApp) return;
    uint32_t newPID = (uint32_t)newApp.processIdentifier;
    if (newPID == windowID) return; // single-instance app, no new process
    dispatch_async(dispatch_get_main_queue(), ^{ onSuccess(newPID); });
  }];
}

void closeWindow(uint32_t windowID) {
  for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
    if ((uint32_t)app.processIdentifier == windowID) {
      [app terminate];
      return;
    }
  }
}

uint32_t getFrontmostWindowID() {
  return (uint32_t)[[[NSWorkspace sharedWorkspace] frontmostApplication]
      processIdentifier];
}

void applyFrame(uint32_t windowID, WMRect frame) {
  AXUIElementRef app = AXUIElementCreateApplication((pid_t)windowID);
  AXUIElementRef window = nullptr;
  AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, (CFTypeRef *)&window);
  if (!window)
    AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute, (CFTypeRef *)&window);
  if (window) {
    CGPoint pos = {(CGFloat)frame.x, (CGFloat)frame.y};
    CGSize size = {(CGFloat)frame.width, (CGFloat)frame.height};
    AXValueRef posVal = AXValueCreate((AXValueType)kAXValueCGPointType, &pos);
    AXValueRef sizeVal = AXValueCreate((AXValueType)kAXValueCGSizeType, &size);
    AXUIElementSetAttributeValue(window, kAXPositionAttribute, posVal);
    AXUIElementSetAttributeValue(window, kAXSizeAttribute, sizeVal);
    CFRelease(posVal);
    CFRelease(sizeVal);
    CFRelease(window);
  }
  CFRelease(app);
}
