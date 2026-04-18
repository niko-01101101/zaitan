#include "../src/WMRect.hpp"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

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

uint32_t getFrontmostWindowID() {
  return (uint32_t)[[[NSWorkspace sharedWorkspace] frontmostApplication]
      processIdentifier];
}

void applyFrame(uint32_t windowID, WMRect frame) {
  AXUIElementRef app = AXUIElementCreateApplication((pid_t)windowID);
  AXUIElementRef window = nullptr;
  AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute,
                                (CFTypeRef *)&window);
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
