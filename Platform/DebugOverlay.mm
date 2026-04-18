#ifdef DEBUG

#import <AppKit/AppKit.h>
#include "../src/Desktop.hpp"

@interface DebugOverlayView : NSView
@property (nonatomic) std::vector<WindowPlacement> placements;
@property (nonatomic) uint32_t focusedID;
@end

@implementation DebugOverlayView

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    NSScreen *screen = [NSScreen mainScreen];
    CGFloat screenH = screen.frame.size.height;

    for (auto &p : _placements) {
        CGFloat y = screenH - p.frame.y - p.frame.height;
        NSRect r = NSInsetRect(NSMakeRect(p.frame.x, y, p.frame.width, p.frame.height), 1, 1);

        BOOL isFocused = (p.windowID == _focusedID);
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:r];
        path.lineWidth = isFocused ? 3.0 : 2.0;

        if (isFocused)
            [[NSColor colorWithCalibratedRed:0.2 green:0.8 blue:1.0 alpha:0.9] set];
        else
            [[NSColor colorWithCalibratedRed:1.0 green:0.3 blue:0.0 alpha:0.6] set];

        [path stroke];
    }
}

@end

static NSWindow *gOverlayWindow = nil;
static DebugOverlayView *gOverlayView = nil;

void showDebugOverlay(const std::vector<WindowPlacement> &placements,
                      uint32_t selectedID) {
    uint32_t focusedID = selectedID;
    if (!gOverlayWindow) {
        NSScreen *screen = [NSScreen mainScreen];
        gOverlayWindow = [[NSWindow alloc]
            initWithContentRect:screen.frame
                      styleMask:NSWindowStyleMaskBorderless
                        backing:NSBackingStoreBuffered
                          defer:NO];
        gOverlayWindow.backgroundColor = [NSColor clearColor];
        gOverlayWindow.opaque = NO;
        gOverlayWindow.ignoresMouseEvents = YES;
        gOverlayWindow.level = NSScreenSaverWindowLevel;
        gOverlayWindow.hasShadow = NO;
        gOverlayWindow.collectionBehavior =
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorStationary;

        gOverlayView = [[DebugOverlayView alloc] initWithFrame:screen.frame];
        gOverlayWindow.contentView = gOverlayView;
        [gOverlayWindow orderFrontRegardless];
    }

    gOverlayView.placements = placements;
    gOverlayView.focusedID = focusedID;
    [gOverlayView setNeedsDisplay:YES];
}

#endif // DEBUG
