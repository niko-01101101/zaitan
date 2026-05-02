#ifdef DEBUG

#import <AppKit/AppKit.h>
#include "../src/Desktop.hpp"
#include <map>
#include <set>

static NSRect lerpRect(NSRect a, NSRect b, CGFloat t) {
    return NSMakeRect(
        a.origin.x + (b.origin.x - a.origin.x) * t,
        a.origin.y + (b.origin.y - a.origin.y) * t,
        a.size.width + (b.size.width - a.size.width) * t,
        a.size.height + (b.size.height - a.size.height) * t
    );
}

static BOOL rectsNearlyEqual(NSRect a, NSRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.5 &&
           fabs(a.origin.y - b.origin.y) < 0.5 &&
           fabs(a.size.width - b.size.width) < 0.5 &&
           fabs(a.size.height - b.size.height) < 0.5;
}

struct AnimRect { NSRect current, target; };

@interface DebugOverlayView : NSView {
    std::map<uint32_t, AnimRect> _panes;
    AnimRect _cursor;
    BOOL _hasCursor;
    NSTimer *_animTimer;
}
- (void)updatePlacements:(const std::vector<WindowPlacement> &)placements
               focusedID:(uint32_t)focusedID
                 screenH:(CGFloat)screenH;
@end

@implementation DebugOverlayView

- (void)updatePlacements:(const std::vector<WindowPlacement> &)placements
               focusedID:(uint32_t)focusedID
                 screenH:(CGFloat)screenH {
    std::set<uint32_t> incoming;
    for (auto &p : placements) {
        incoming.insert(p.windowID);
        CGFloat y = screenH - p.frame.y - p.frame.height;
        NSRect target = NSMakeRect(p.frame.x, y, p.frame.width, p.frame.height);

        auto it = _panes.find(p.windowID);
        if (it == _panes.end())
            _panes[p.windowID] = {target, target};
        else
            it->second.target = target;

        if (p.windowID == focusedID) {
            if (!_hasCursor) { _cursor = {target, target}; _hasCursor = YES; }
            else              { _cursor.target = target; }
        }
    }

    for (auto it = _panes.begin(); it != _panes.end(); )
        it = incoming.count(it->first) ? std::next(it) : _panes.erase(it);

    if (!_animTimer)
        _animTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                     target:self
                                                   selector:@selector(tick:)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)tick:(NSTimer *)timer {
    BOOL allDone = YES;
    for (auto &kv : _panes) {
        kv.second.current = lerpRect(kv.second.current, kv.second.target, 0.3);
        if (rectsNearlyEqual(kv.second.current, kv.second.target))
            kv.second.current = kv.second.target;
        else
            allDone = NO;
    }
    if (_hasCursor) {
        _cursor.current = lerpRect(_cursor.current, _cursor.target, 0.3);
        if (rectsNearlyEqual(_cursor.current, _cursor.target))
            _cursor.current = _cursor.target;
        else
            allDone = NO;
    }
    [self setNeedsDisplay:YES];
    if (allDone) {
        [_animTimer invalidate];
        _animTimer = nil;
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    for (auto &kv : _panes) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:kv.second.current xRadius:8 yRadius:8];
        path.lineWidth = 1.5;
        [[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:0.1] set];
        [path stroke];
    }

    if (_hasCursor) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:_cursor.current xRadius:8 yRadius:8];
        path.lineWidth = 2.0;
        [[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0] set];
        [path stroke];
    }
}

@end

static NSWindow *gOverlayWindow = nil;
static DebugOverlayView *gOverlayView = nil;

void showDebugOverlay(const std::vector<WindowPlacement> &placements,
                      uint32_t selectedID) {
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

    NSScreen *screen = [NSScreen mainScreen];
    CGFloat screenH = screen.frame.size.height;

    [gOverlayView updatePlacements:placements focusedID:selectedID screenH:screenH];
}

#endif // DEBUG
