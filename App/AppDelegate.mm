#import "AppDelegate.h"
#import <ApplicationServices/ApplicationServices.h>
#include "../src/WMRect.hpp"
#include "../config/Config.hpp"

extern WMRect getScreenFrame(int display);
extern void RegisterHotkeys(WMRect screenFrame, Config config);
extern void StartAutoAssign();
extern void UnregisterHotkeys();

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (!AXIsProcessTrusted()) {
        NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }

    RegisterHotkeys(getScreenFrame(0), loadConfig());
    StartAutoAssign();
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    UnregisterHotkeys();
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end
