#import <AppKit/AppKit.h>

static NSWindow *sFadeWindow = nil;

void performWithFade(void (^work)(void)) {
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

    [sFadeWindow orderFront:nil];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.015;
        [sFadeWindow.animator setAlphaValue:1.0];
    } completionHandler:^{
        work();
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.20;
            [sFadeWindow.animator setAlphaValue:0.0];
        } completionHandler:^{
            [sFadeWindow orderOut:nil];
        }];
    }];
}
