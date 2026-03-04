#import <AVKit/AVKit.h>
#import <objc/runtime.h>

static BOOL const kBrowserAVKitFullscreenBlockEnabled = YES;

@interface AVPlayerViewController (BrowserFullscreenBlock)

- (void)browser_blockedEnterFullScreenAnimated:(BOOL)animated completionHandler:(void (^ __nullable)(void))completionHandler;
- (void)browser_blockedExitFullScreenAnimated:(BOOL)animated completionHandler:(void (^ __nullable)(void))completionHandler;

@end

@implementation AVPlayerViewController (BrowserFullscreenBlock)

+ (void)load {
    if (!kBrowserAVKitFullscreenBlockEnabled) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class playerViewControllerClass = [AVPlayerViewController class];

        Method enterOriginal = class_getInstanceMethod(playerViewControllerClass, NSSelectorFromString(@"enterFullScreenAnimated:completionHandler:"));
        Method enterReplacement = class_getInstanceMethod(playerViewControllerClass, @selector(browser_blockedEnterFullScreenAnimated:completionHandler:));
        if (enterOriginal != NULL && enterReplacement != NULL) {
            method_exchangeImplementations(enterOriginal, enterReplacement);
        }

        Method exitOriginal = class_getInstanceMethod(playerViewControllerClass, NSSelectorFromString(@"exitFullScreenAnimated:completionHandler:"));
        Method exitReplacement = class_getInstanceMethod(playerViewControllerClass, @selector(browser_blockedExitFullScreenAnimated:completionHandler:));
        if (exitOriginal != NULL && exitReplacement != NULL) {
            method_exchangeImplementations(exitOriginal, exitReplacement);
        }
    });
}

- (void)browser_blockedEnterFullScreenAnimated:(BOOL)animated completionHandler:(void (^ __nullable)(void))completionHandler {
    if (completionHandler != nil) {
        completionHandler();
    }
}

- (void)browser_blockedExitFullScreenAnimated:(BOOL)animated completionHandler:(void (^ __nullable)(void))completionHandler {
    if (completionHandler != nil) {
        completionHandler();
    }
}

@end
