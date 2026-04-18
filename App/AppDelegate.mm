#import "AppDelegate.h"
#import <ApplicationServices/ApplicationServices.h>
#include "../src/Desktop.hpp"

extern WMRect getScreenFrame(int display);
extern void RegisterHotkeys(Desktop &desktop);
extern void UnregisterHotkeys();

static Desktop *gDesktop = nullptr;

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (!AXIsProcessTrusted()) {
        NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }

    gDesktop = new Desktop(getScreenFrame(0));
    RegisterHotkeys(*gDesktop);
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    UnregisterHotkeys();
    delete gDesktop;
    gDesktop = nullptr;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end
