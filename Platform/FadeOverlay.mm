#import <AppKit/AppKit.h>

static NSWindow *sFadeWindow = nil;

static NSWindow *coverWindow() {
    if (!sFadeWindow) {
        NSRect screen = [[NSScreen mainScreen] frame];
        sFadeWindow = [[NSWindow alloc] initWithContentRect:screen
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        sFadeWindow.backgroundColor = [NSColor blackColor];
        sFadeWindow.ignoresMouseEvents = YES;
        sFadeWindow.level = NSScreenSaverWindowLevel;
        sFadeWindow.alphaValue = 0.0;
        sFadeWindow.opaque = NO;
        sFadeWindow.hasShadow = NO;
        sFadeWindow.collectionBehavior =
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorStationary |
            NSWindowCollectionBehaviorIgnoresCycle;
    }
    return sFadeWindow;
}

// Slow fade-in then fade-out — used for desktop switches.
void performWithFade(void (^work)(void)) {
    NSWindow *w = coverWindow();
    [w orderFront:nil];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.015;
        [w.animator setAlphaValue:1.0];
    } completionHandler:^{
        work();
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.20;
            [w.animator setAlphaValue:0.0];
        } completionHandler:^{
            [w orderOut:nil];
        }];
    }];
}

// Instant cover then quick fade-out — used to hide window repositioning.
void performWithCover(void (^work)(void)) {
    NSWindow *w = coverWindow();
    [w orderFront:nil];
    [NSAnimationContext beginGrouping];
    [NSAnimationContext currentContext].duration = 0;
    w.alphaValue = 1.0;
    [NSAnimationContext endGrouping];
    work();
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.08;
        [w.animator setAlphaValue:0.0];
    } completionHandler:^{
        [w orderOut:nil];
    }];
}
