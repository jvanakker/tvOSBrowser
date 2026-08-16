#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

NSString * const BrowserGlobalSelectPressEndedNotification = @"BrowserGlobalSelectPressEndedNotification";

// Depth of -[UIApplication sendEvent:] on the current stack. Anything that would spin the run
// loop must not do so while an event is being delivered: spinning dispatches the next event and
// re-enters sendEvent:, which UIKit traps on (EXC_BREAKPOINT) from tvOS 27 onwards.
static NSInteger sBrowserSendEventDepth = 0;

BOOL BrowserIsDeliveringEvent(void) {
    return sBrowserSendEventDepth > 0;
}
static BOOL sBrowserNativeScrubTracking = NO;
static CGFloat sBrowserNativePendingScrubPixels = 0.0;
static CGPoint sBrowserNativeLastTouchLocation = {0, 0};
static CFTimeInterval sBrowserNativeLastArrowPressTimestamp = 0.0;
static UIPressType sBrowserNativeLastArrowPressType = (UIPressType)-1;
static CGFloat const kBrowserNativeScrubPixelStep = 18.0;
static CFTimeInterval const kBrowserNativeArrowDoubleTapInterval = 0.35;

static NSString *BrowserPressTypeString(UIPressType type) {
    switch (type) {
        case UIPressTypeMenu: return @"Menu";
        case UIPressTypePlayPause: return @"PlayPause";
        case UIPressTypeSelect: return @"Select";
        case UIPressTypeUpArrow: return @"Up";
        case UIPressTypeDownArrow: return @"Down";
        case UIPressTypeLeftArrow: return @"Left";
        case UIPressTypeRightArrow: return @"Right";
        default: return [NSString stringWithFormat:@"Type-%ld", (long)type];
    }
}

static NSString *BrowserPressPhaseString(UIPressPhase phase) {
    switch (phase) {
        case UIPressPhaseBegan: return @"Began";
        case UIPressPhaseChanged: return @"Changed";
        case UIPressPhaseStationary: return @"Stationary";
        case UIPressPhaseEnded: return @"Ended";
        case UIPressPhaseCancelled: return @"Cancelled";
        default: return [NSString stringWithFormat:@"Phase-%ld", (long)phase];
    }
}

static UIViewController *BrowserFindViewControllerOfClass(UIViewController *viewController, Class targetClass) {
    if (viewController == nil || targetClass == Nil) {
        return nil;
    }

    if ([viewController isKindOfClass:targetClass]) {
        return viewController;
    }

    if (viewController.presentedViewController != nil) {
        UIViewController *match = BrowserFindViewControllerOfClass(viewController.presentedViewController, targetClass);
        if (match != nil) {
            return match;
        }
    }

    for (UIViewController *childViewController in viewController.childViewControllers) {
        UIViewController *match = BrowserFindViewControllerOfClass(childViewController, targetClass);
        if (match != nil) {
            return match;
        }
    }

    if ([viewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)viewController;
        UIViewController *match = BrowserFindViewControllerOfClass(navigationController.visibleViewController, targetClass);
        if (match != nil) {
            return match;
        }
    }

    if ([viewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)viewController;
        UIViewController *match = BrowserFindViewControllerOfClass(tabBarController.selectedViewController, targetClass);
        if (match != nil) {
            return match;
        }
    }

    return nil;
}

static UIViewController *BrowserFindPresentedNativeVideoPlayerViewController(UIApplication *application, Class nativeVideoPlayerClass) {
    for (UIWindow *window in application.windows) {
        if (window.hidden || window.rootViewController == nil) {
            continue;
        }

        UIViewController *match = BrowserFindViewControllerOfClass(window.rootViewController, nativeVideoPlayerClass);
        if (match != nil) {
            return match;
        }
    }
    return nil;
}

@interface UIApplication (BrowserSelectPressForwarding)

- (void)browser_sendEvent:(UIEvent *)event;

@end

@implementation UIApplication (BrowserSelectPressForwarding)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMethod = class_getInstanceMethod(self, @selector(sendEvent:));
        Method replacementMethod = class_getInstanceMethod(self, @selector(browser_sendEvent:));
        if (originalMethod != NULL && replacementMethod != NULL) {
            method_exchangeImplementations(originalMethod, replacementMethod);
        }
    });
}

- (void)browser_sendEvent:(UIEvent *)event {
    sBrowserSendEventDepth += 1;
    @try {
        [self browser_deliverEvent:event];
    } @finally {
        sBrowserSendEventDepth -= 1;
    }
}

- (void)browser_deliverEvent:(UIEvent *)event {
    Class nativeVideoPlayerClass = NSClassFromString(@"BrowserNativeVideoPlayerViewController");
    UIViewController *nativeVideoPlayerViewController = BrowserFindPresentedNativeVideoPlayerViewController(self, nativeVideoPlayerClass);

    if (event.type == UIEventTypeTouches) {
        SEL allTouchesSelector = NSSelectorFromString(@"allTouches");
        if ([event respondsToSelector:allTouchesSelector]) {
            NSSet<UITouch *> *touches = ((id (*)(id, SEL))objc_msgSend)(event, allTouchesSelector);
            for (UITouch *touch in touches) {
                if (touch.type != UITouchTypeIndirect) {
                    continue;
                }

                CGPoint location = [touch locationInView:nil];
                if (touch.phase == UITouchPhaseBegan) {
                    sBrowserNativeScrubTracking = (nativeVideoPlayerClass != Nil && nativeVideoPlayerViewController != nil);
                    sBrowserNativePendingScrubPixels = 0.0;
                    sBrowserNativeLastTouchLocation = location;
                    continue;
                }

                if (!sBrowserNativeScrubTracking || nativeVideoPlayerViewController == nil) {
                    continue;
                }

                if (touch.phase == UITouchPhaseMoved) {
                    CGFloat deltaX = location.x - sBrowserNativeLastTouchLocation.x;
                    sBrowserNativeLastTouchLocation = location;
                    sBrowserNativePendingScrubPixels += deltaX;

                    SEL scrubSelector = NSSelectorFromString(@"scrubByHorizontalDelta:");
                    if ([nativeVideoPlayerViewController respondsToSelector:scrubSelector]) {
                        while (fabs(sBrowserNativePendingScrubPixels) >= kBrowserNativeScrubPixelStep) {
                            CGFloat step = sBrowserNativePendingScrubPixels > 0.0 ? kBrowserNativeScrubPixelStep : -kBrowserNativeScrubPixelStep;
                            ((void (*)(id, SEL, CGFloat))objc_msgSend)(nativeVideoPlayerViewController, scrubSelector, step);
                            sBrowserNativePendingScrubPixels -= step;
                            NSLog(@"[InputTrace][App] scrub step delta=%.2f", step);
                        }
                    }
                }

                if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                    sBrowserNativeScrubTracking = NO;
                    sBrowserNativePendingScrubPixels = 0.0;
                }
            }
        }

        [self browser_sendEvent:event];
        return;
    }

    if (event.type != UIEventTypePresses) {
        [self browser_sendEvent:event];
        return;
    }

    SEL allPressesSelector = NSSelectorFromString(@"allPresses");
    if (![event respondsToSelector:allPressesSelector]) {
        [self browser_sendEvent:event];
        return;
    }

    NSSet<UIPress *> *presses = ((id (*)(id, SEL))objc_msgSend)(event, allPressesSelector);
    for (UIPress *press in presses) {
        nativeVideoPlayerViewController = BrowserFindPresentedNativeVideoPlayerViewController(self, nativeVideoPlayerClass);
        if (press.type == UIPressTypeMenu || press.type == UIPressTypePlayPause || press.type == UIPressTypeSelect) {
            NSLog(@"[InputTrace][App] press=%@ phase=%@ top=%@",
                  BrowserPressTypeString(press.type),
                  BrowserPressPhaseString(press.phase),
                  nativeVideoPlayerViewController == nil ? @"(nil)" : NSStringFromClass([nativeVideoPlayerViewController class]));
        }

        if (press.type == UIPressTypeMenu && press.phase == UIPressPhaseBegan) {
            if (nativeVideoPlayerClass != Nil && nativeVideoPlayerViewController != nil) {
                NSLog(@"[InputTrace][App] swallow Menu for native player");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [nativeVideoPlayerViewController dismissViewControllerAnimated:YES completion:nil];
                });
                return;
            }
        }

        if (press.type == UIPressTypePlayPause && press.phase == UIPressPhaseEnded) {
            if (nativeVideoPlayerClass != Nil && nativeVideoPlayerViewController != nil) {
                SEL togglePlaybackSelector = NSSelectorFromString(@"togglePlayback");
                if ([nativeVideoPlayerViewController respondsToSelector:togglePlaybackSelector]) {
                    NSLog(@"[InputTrace][App] swallow PlayPause for native player");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ((void (*)(id, SEL))objc_msgSend)(nativeVideoPlayerViewController, togglePlaybackSelector);
                    });
                    return;
                }
            }
        }

        if (press.type == UIPressTypeSelect && press.phase == UIPressPhaseEnded) {
            if (nativeVideoPlayerClass != Nil && nativeVideoPlayerViewController != nil) {
                SEL togglePlaybackSelector = NSSelectorFromString(@"togglePlayback");
                if ([nativeVideoPlayerViewController respondsToSelector:togglePlaybackSelector]) {
                    NSLog(@"[InputTrace][App] swallow Select for native player");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ((void (*)(id, SEL))objc_msgSend)(nativeVideoPlayerViewController, togglePlaybackSelector);
                    });
                    return;
                }
            }
        }

        if ((press.type == UIPressTypeLeftArrow || press.type == UIPressTypeRightArrow) && press.phase == UIPressPhaseEnded) {
            if (nativeVideoPlayerClass != Nil && nativeVideoPlayerViewController != nil) {
                SEL skipSelector = NSSelectorFromString(@"skipByInterval:");
                if ([nativeVideoPlayerViewController respondsToSelector:skipSelector]) {
                    CFTimeInterval now = CACurrentMediaTime();
                    BOOL isDoubleTap = (sBrowserNativeLastArrowPressType == press.type) &&
                                       ((now - sBrowserNativeLastArrowPressTimestamp) <= kBrowserNativeArrowDoubleTapInterval);
                    sBrowserNativeLastArrowPressType = press.type;
                    sBrowserNativeLastArrowPressTimestamp = now;

                    if (isDoubleTap) {
                        NSTimeInterval delta = (press.type == UIPressTypeRightArrow) ? 5.0 : -5.0;
                        NSLog(@"[InputTrace][App] swallow %@ double tap for native player (delta=%0.1f)",
                              BrowserPressTypeString(press.type), delta);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(nativeVideoPlayerViewController, skipSelector, delta);
                        });
                        sBrowserNativeLastArrowPressType = (UIPressType)-1;
                        sBrowserNativeLastArrowPressTimestamp = 0.0;
                    } else {
                        NSLog(@"[InputTrace][App] swallow %@ single tap for native player (waiting for double tap)",
                              BrowserPressTypeString(press.type));
                    }
                    return;
                }
            }
        }
    }

    [self browser_sendEvent:event];

    for (UIPress *press in presses) {
        if (press.type == UIPressTypeSelect && press.phase == UIPressPhaseEnded) {
            NSLog(@"[InputTrace][App] post BrowserGlobalSelectPressEndedNotification");
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:BrowserGlobalSelectPressEndedNotification object:nil];
            });
            break;
        }
    }
}

@end
