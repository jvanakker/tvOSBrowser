//
//  ViewController.m
//  Browser
//
//  Created by Steven Troughton-Smith on 20/09/2015.
//  Improved by Jip van Akker on 14/10/2015 through 10/01/2019
//

// Icons made by https://www.flaticon.com/authors/daniel-bruce Daniel Bruce from https://www.flaticon.com/ Flaticon" is licensed by  http://creativecommons.org/licenses/by/3.0/  CC 3.0 BY


#import "BrowserMenuPresenter.h"
#import "BrowserNativeVideoPlayerViewController.h"
#import "BrowserSessionStore.h"
#import "BrowserYouTubeExtractor.h"
#import "ViewController.h"
#import "BrowserNavigationService.h"
#import "BrowserTabViewModel.h"
#import "BrowserWebView.h"
#import "BrowserViewModel.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - UI

static UIColor *kTextColor(void) {
    if (@available(tvOS 13, *)) {
        return UIColor.labelColor;
    } else {
        return UIColor.blackColor;
    }
}

static UIImage *kDefaultCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Cursor"];
    });
    return image;
}

static UIImage *kPointerCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Pointer"];
    });
    return image;
}

static CGFloat const kTabOverviewPanelWidth = 1520.0;
static CGFloat const kTabOverviewPanelHeight = 760.0;
static CGFloat const kTabCardWidth = 260.0;
static CGFloat const kTabCardHeight = 240.0;
static CGFloat const kTabCardSpacing = 20.0;
static CGFloat const kTabCardGlowInset = 12.0;
static NSString * const kDisableInlineMediaPlaybackDefaultsKey = @"DisableInlineMediaPlayback";
static NSString * const kInteractiveElementSelector = @"a, button, input, textarea, select, option, label, summary, [role='button'], [onclick], [tabindex]";
static NSString * const kEditableElementSelector = @"input, textarea, select, [contenteditable='true'], [contenteditable=''], [contenteditable]";
static NSString * const kUserAgentDefaultsKey = @"UserAgent";
static NSString * const kBrowserGlobalSelectPressEndedNotification = @"BrowserGlobalSelectPressEndedNotification";

@interface ViewController () <BrowserMenuPresenterHost>

@property BrowserWebView *webview;
@property NSString *requestURL;
@property NSString *previousURL;
@property UIImageView *cursorView;
@property BOOL cursorMode;
@property BOOL displayedHintsOnLaunch;
@property BOOL scrollViewAllowBounces;
@property CGPoint lastTouchLocation;
@property NSUInteger textFontSize;
@property (readonly) BOOL topMenuShowing;
@property (readonly) CGFloat topMenuBrowserOffset;
@property UIPanGestureRecognizer *manualScrollPanRecognizer;
@property CADisplayLink *manualScrollDisplayLink;
@property CGPoint manualScrollVelocity;
@property CFTimeInterval manualScrollLastTimestamp;
@property CFTimeInterval manualScrollLastMovementTimestamp;
@property UITapGestureRecognizer *playPauseDoubleTapRecognizer;
@property BrowserMenuPresenter *menuPresenter;
@property BrowserNavigationService *navigationService;
@property BrowserSessionStore *sessionStore;
@property BrowserViewModel *viewModel;
@property NSMutableDictionary *webViewsByTabIdentifier;
@property UIVisualEffectView *tabOverviewOverlayView;
@property UIView *tabOverviewPanelView;
@property UIScrollView *tabOverviewScrollView;
@property UIButton *tabOverviewAddButton;
@property NSMutableArray *tabOverviewCardViews;
@property BOOL tabOverviewVisible;
@property BOOL cursorModeBeforeShowingTabOverview;
@property CFTimeInterval lastDirectSelectPressTimestamp;
@property CFTimeInterval lastSelectPressTimestamp;
@property BOOL awaitingSecondSelectPress;
@property (nonatomic, strong) BrowserYouTubeExtractor *youTubeExtractor;

@end

@implementation ViewController

- (BOOL)applyManualScrollDelta:(CGPoint)delta {
    UIScrollView *scrollView = [self.webview scrollView];
    if (scrollView == nil) {
        return NO;
    }

    CGPoint contentOffset = scrollView.contentOffset;
    CGFloat maxOffsetX = MAX(0.0, scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds));
    CGFloat maxOffsetY = MAX(0.0, scrollView.contentSize.height - CGRectGetHeight(scrollView.bounds));
    CGFloat nextOffsetX = MIN(MAX(contentOffset.x + delta.x, 0.0), maxOffsetX);
    CGFloat nextOffsetY = MIN(MAX(contentOffset.y + delta.y, 0.0), maxOffsetY);
    CGPoint nextOffset = CGPointMake(nextOffsetX, nextOffsetY);
    [scrollView setContentOffset:nextOffset animated:NO];
    return !CGPointEqualToPoint(contentOffset, nextOffset);
}

- (void)stopManualScrollInertia {
    [self.manualScrollDisplayLink invalidate];
    self.manualScrollDisplayLink = nil;
    self.manualScrollVelocity = CGPointZero;
    self.manualScrollLastTimestamp = 0;
    self.manualScrollLastMovementTimestamp = 0;
}

- (void)startManualScrollInertiaWithVelocity:(CGPoint)velocity {
    [self stopManualScrollInertia];

    if (fabs(velocity.x) < 25.0 && fabs(velocity.y) < 25.0) {
        return;
    }

    self.manualScrollVelocity = velocity;
    self.manualScrollLastTimestamp = 0;
    self.manualScrollDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleManualScrollDisplayLink:)];
    [self.manualScrollDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)handleManualScrollDisplayLink:(CADisplayLink *)displayLink {
    if (self.cursorMode || self.tabOverviewVisible) {
        [self stopManualScrollInertia];
        return;
    }

    if (self.manualScrollLastTimestamp <= 0) {
        self.manualScrollLastTimestamp = displayLink.timestamp;
        return;
    }

    CFTimeInterval deltaTime = displayLink.timestamp - self.manualScrollLastTimestamp;
    self.manualScrollLastTimestamp = displayLink.timestamp;

    CGPoint step = CGPointMake(self.manualScrollVelocity.x * deltaTime, self.manualScrollVelocity.y * deltaTime);
    BOOL didMove = [self applyManualScrollDelta:step];

    CGFloat decay = pow(0.92, deltaTime * 60.0);
    self.manualScrollVelocity = CGPointMake(self.manualScrollVelocity.x * decay, self.manualScrollVelocity.y * decay);

    if (!didMove ||
        (fabs(self.manualScrollVelocity.x) < 10.0 && fabs(self.manualScrollVelocity.y) < 10.0)) {
        [self stopManualScrollInertia];
        [self persistBrowserSession];
    }
}

- (void)handleGlobalSelectPressEndedNotification:(NSNotification *)notification {
    if (self.presentedViewController != nil) {
        return;
    }

    if ((CACurrentMediaTime() - self.lastDirectSelectPressTimestamp) < 0.15) {
        return;
    }

    [self handleSelectPressEndedWithSource:@"fallback"];
}

- (void)handleDeferredSelectPressAction {
    if (!self.awaitingSecondSelectPress) {
        return;
    }

    self.awaitingSecondSelectPress = NO;
    self.lastTouchLocation = CGPointMake(-1, -1);

    if (self.presentedViewController != nil) {
        return;
    }

    if (self.tabOverviewVisible) {
        [self handleTabOverviewSelectionAtPoint:self.cursorView.frame.origin];
        return;
    }

    [self browserHandleSelectPressAction];
}

- (void)handleSelectPressEndedWithSource:(NSString *)source {
    CFTimeInterval now = CACurrentMediaTime();

    if (self.awaitingSecondSelectPress && (now - self.lastSelectPressTimestamp) < 0.35) {
        self.awaitingSecondSelectPress = NO;
        self.lastSelectPressTimestamp = now;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredSelectPressAction) object:nil];
        if (!self.tabOverviewVisible) {
            [self toggleMode];
        }
        return;
    }

    self.awaitingSecondSelectPress = YES;
    self.lastSelectPressTimestamp = now;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredSelectPressAction) object:nil];
    [self performSelector:@selector(handleDeferredSelectPressAction) withObject:nil afterDelay:0.3];
}

- (BrowserTabViewModel *)activeTab {
    return [self.viewModel activeTab];
}

- (BrowserTabViewModel *)tabForWebView:(id)webView {
    for (BrowserTabViewModel *tab in self.viewModel.tabs) {
        if (self.webViewsByTabIdentifier[tab.identifier] == webView) {
            return tab;
        }
    }
    return nil;
}

- (NSString *)requestURL {
    return [self activeTab].requestURL;
}

- (void)setRequestURL:(NSString *)requestURL {
    [self activeTab].requestURL = requestURL;
}

- (NSString *)previousURL {
    return [self activeTab].previousURL;
}

- (void)setPreviousURL:(NSString *)previousURL {
    [self activeTab].previousURL = previousURL;
}

- (BrowserWebView *)browserWebView {
    return self.webview;
}

- (NSString *)browserPreviousURL {
    return self.previousURL;
}

- (void)setBrowserPreviousURL:(NSString *)browserPreviousURL {
    self.previousURL = browserPreviousURL;
}

- (NSUInteger)browserTextFontSize {
    return self.textFontSize;
}

- (void)setBrowserTextFontSize:(NSUInteger)browserTextFontSize {
    self.textFontSize = browserTextFontSize;
}

- (BOOL)browserTopMenuShowing {
    return self.topMenuShowing;
}

- (void)browserPresentViewController:(UIViewController *)viewController {
    [self presentViewController:viewController animated:YES completion:nil];
}

- (void)browserLoadHomePage {
    [self loadHomePage];
}

- (void)browserShowHints {
    [self showHintsAlert];
}

- (void)browserShowTabOverview {
    [self showTabOverview];
}

- (void)browserCreateNewTabLoadingHomePage:(BOOL)loadHomePage {
    [self createNewTabLoadingHomePage:loadHomePage];
}

- (void)browserHideTopNav {
    [self hideTopNav];
}

- (void)browserShowTopNav {
    [self showTopNav];
}

- (void)browserUpdateTextFontSize {
    [self updateTextFontSize];
}

- (void)browserCaptureSnapshotForCurrentTab {
    [self captureSnapshotForTab:[self activeTab]];
}

- (void)browserRecreateActiveWebViewPreservingCurrentURL {
    [self recreateActiveWebViewPreservingCurrentURL];
}

- (void)browserBringCursorToFront {
    [self.view bringSubviewToFront:self.cursorView];
}

- (void)browserPlayVideoUnderCursorIfAvailable {
    [self playVideoUnderCursorIfAvailable];
}

- (BrowserYouTubeExtractor *)youTubeExtractor {
    if (_youTubeExtractor == nil) {
        _youTubeExtractor = [BrowserYouTubeExtractor new];
    }
    return _youTubeExtractor;
}

- (void)handleApplicationWillResignActive:(NSNotification *)notification {
    [self persistBrowserSession];
}

- (void)handleApplicationDidEnterBackground:(NSNotification *)notification {
    [self persistBrowserSession];
}

- (void)handleApplicationWillTerminate:(NSNotification *)notification {
    [self persistBrowserSession];
}

- (BOOL)tabOverviewVisible {
    return self.viewModel.tabOverviewVisible;
}

- (void)setTabOverviewVisible:(BOOL)tabOverviewVisible {
    self.viewModel.tabOverviewVisible = tabOverviewVisible;
}

- (BrowserWebView *)createConfiguredWebView {
    if (@available(tvOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }

    NSString *userAgent = [[NSUserDefaults standardUserDefaults] stringForKey:kUserAgentDefaultsKey];
    BOOL disablesInlineMediaPlayback = [[NSUserDefaults standardUserDefaults] boolForKey:kDisableInlineMediaPlaybackDefaultsKey];
    BrowserWebView *webView = [[BrowserWebView alloc] initWithUserAgent:userAgent
                                           allowsInlineMediaPlayback:!disablesInlineMediaPlayback];
    [webView setTranslatesAutoresizingMaskIntoConstraints:false];
    [webView setClipsToBounds:false];
    [webView setDelegate:self];
    [webView setLayoutMargins:UIEdgeInsetsZero];
    [webView setOpaque:NO];
    [webView setBackgroundColor:UIColor.blackColor];
    
    UIScrollView *scrollView = [webView scrollView];
    [scrollView setLayoutMargins:UIEdgeInsetsZero];
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scrollView.contentOffset = CGPointZero;
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.clipsToBounds = NO;
    scrollView.backgroundColor = UIColor.blackColor;
    scrollView.bounces = self.scrollViewAllowBounces;
    [scrollView.panGestureRecognizer addTarget:self action:@selector(handleWebViewPanGesture:)];
    scrollView.scrollEnabled = NO;
    
    NSNumber *scalePagesToFit = [[NSUserDefaults standardUserDefaults] objectForKey:@"ScalePagesToFit"];
    BOOL shouldScalePagesToFit = scalePagesToFit.boolValue;
    [webView setScalesPageToFit:shouldScalePagesToFit];
    [webView setContentMode:shouldScalePagesToFit ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleToFill];
    [webView setUserInteractionEnabled:NO];
    return webView;
}

- (void)refreshActiveTabUI {
    BrowserTabViewModel *tab = [self activeTab];
    if (tab == nil) {
        self.topMenuView.URLLabel.text = @"";
        return;
    }
    
    NSURLRequest *request = [self.webview request];
    NSString *currentURL = tab.URLString.length > 0 ? tab.URLString : request.URL.absoluteString;
    self.topMenuView.URLLabel.text = currentURL.length > 0 ? currentURL : @"New Tab";
    
    if (request != nil) {
        [self updateTextFontSize];
    }
}

- (CGPoint)browserDOMPointForCursor {
    CGPoint point = [self.view convertPoint:self.cursorView.frame.origin toView:self.webview];
    if (point.y < 0.0) {
        return point;
    }

    NSInteger displayWidth = [[self.webview stringByEvaluatingJavaScriptFromString:@"window.innerWidth"] integerValue];
    if (displayWidth <= 0) {
        return point;
    }

    CGFloat scale = CGRectGetWidth([self.webview frame]) / (CGFloat)displayWidth;
    if (scale <= 0.0) {
        return point;
    }

    point.x /= scale;
    point.y /= scale;
    return point;
}

- (NSString *)evaluateResolvedElementJavaScriptAtPoint:(CGPoint)point body:(NSString *)body {
    NSInteger pointX = (NSInteger)llround(point.x);
    NSInteger pointY = (NSInteger)llround(point.y);
    NSString *script = [NSString stringWithFormat:
                        @"(function(){"
                        "var x=%ld;"
                        "var y=%ld;"
                        "var interactiveSelector=\"%@\";"
                        "var editableSelector=\"%@\";"
                        "function resolveElement(root, px, py) {"
                            "if (!root || typeof root.elementFromPoint !== 'function') { return null; }"
                            "var element = root.elementFromPoint(px, py);"
                            "while (element) {"
                                "if (element.shadowRoot && typeof element.shadowRoot.elementFromPoint === 'function') {"
                                    "var shadowRect = element.getBoundingClientRect();"
                                    "var shadowElement = resolveElement(element.shadowRoot, px - shadowRect.left, py - shadowRect.top);"
                                    "if (shadowElement && shadowElement !== element) {"
                                        "element = shadowElement;"
                                        "continue;"
                                    "}"
                                "}"
                                "if (element.tagName === 'IFRAME') {"
                                    "try {"
                                        "var frameRect = element.getBoundingClientRect();"
                                        "var frameDocument = element.contentDocument;"
                                        "var frameElement = resolveElement(frameDocument, px - frameRect.left, py - frameRect.top);"
                                        "if (frameElement) {"
                                            "element = frameElement;"
                                            "continue;"
                                        "}"
                                    "} catch (error) {}"
                                "}"
                                "return element;"
                            "}"
                            "return null;"
                        "}"
                        "function closestMatch(element, selector) {"
                            "while (element) {"
                                "if (element.matches && element.matches(selector)) { return element; }"
                                "element = element.parentElement;"
                            "}"
                            "return null;"
                        "}"
                        "var resolvedElement = resolveElement(document, x, y);"
                        "var interactiveElement = closestMatch(resolvedElement, interactiveSelector);"
                        "var editableElement = closestMatch(resolvedElement, editableSelector);"
                        "%@"
                        "})()",
                        (long)pointX,
                        (long)pointY,
                        kInteractiveElementSelector,
                        kEditableElementSelector,
                        body];
    return [self.webview stringByEvaluatingJavaScriptFromString:script];
}

- (NSString *)evaluateEditableElementJavaScriptAtPoint:(CGPoint)point body:(NSString *)body {
    NSString *wrappedBody = [NSString stringWithFormat:
                             @"function browserIsEditableCandidate(element) {"
                                 "if (!element) { return false; }"
                                 "var tagName = element.tagName ? element.tagName.toLowerCase() : '';"
                                 "if (element.matches && element.matches(editableSelector)) { return true; }"
                                 "if (tagName === 'textarea' || tagName === 'select') { return true; }"
                                 "if (element.isContentEditable) { return true; }"
                                 "return false;"
                             "}"
                             "function browserEditableTarget() {"
                                 "var stored = window.__browserLastEditableElement;"
                                 "if (stored && stored.isConnected && browserIsEditableCandidate(stored)) { return stored; }"
                                 "var active = document.activeElement;"
                                 "if (active && browserIsEditableCandidate(active)) {"
                                     "window.__browserLastEditableElement = active;"
                                     "return active;"
                                 "}"
                                 "var candidate = editableElement || interactiveElement || resolvedElement;"
                                 "if (candidate && browserIsEditableCandidate(candidate)) {"
                                     "window.__browserLastEditableElement = candidate;"
                                     "return candidate;"
                                 "}"
                                 "if (candidate && candidate.closest) {"
                                     "var fallback = candidate.closest(editableSelector) || candidate.closest('textarea, select');"
                                     "if (fallback && browserIsEditableCandidate(fallback)) {"
                                         "window.__browserLastEditableElement = fallback;"
                                         "return fallback;"
                                     "}"
                                 "}"
                                 "return null;"
                             "}"
                             "%@",
                             body];
    return [self evaluateResolvedElementJavaScriptAtPoint:point body:wrappedBody];
}

- (NSString *)evaluateHoverStateJavaScriptAtPoint:(CGPoint)point {
    NSInteger pointX = (NSInteger)llround(point.x);
    NSInteger pointY = (NSInteger)llround(point.y);
    NSString *script = [NSString stringWithFormat:
                        @"(function(){"
                        "var element = document.elementFromPoint(%ld, %ld);"
                        "while (element) {"
                            "if (element.matches && element.matches(\"%@\")) { return 'true'; }"
                            "element = element.parentElement;"
                        "}"
                        "return 'false';"
                        "})()",
                        (long)pointX,
                        (long)pointY,
                        kInteractiveElementSelector];
    return [self.webview stringByEvaluatingJavaScriptFromString:script];
}

- (NSString *)javaScriptEscapedString:(NSString *)string {
    NSString *escapedString = string ?: @"";
    escapedString = [escapedString stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escapedString = [escapedString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    escapedString = [escapedString stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escapedString = [escapedString stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    escapedString = [escapedString stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\\u2028"];
    escapedString = [escapedString stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\\u2029"];
    return escapedString;
}

- (NSDictionary *)JSONObjectFromJavaScriptString:(NSString *)string {
    if (string.length == 0) {
        return nil;
    }

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    return object;
}

- (NSDictionary *)videoInfoAtDOMPoint:(CGPoint)point {
    NSString *result = [self evaluateResolvedElementJavaScriptAtPoint:point
                                                                 body:@"function browserAbsoluteURL(url) {"
                                                                      "if (!url) { return ''; }"
                                                                      "try { return String(new URL(url, document.baseURI).toString()); } catch (error) { return String(url); }"
                                                                      "}"
                                                                      "function browserVideoContainsPoint(video) {"
                                                                          "if (!video || typeof video.getBoundingClientRect !== 'function') { return false; }"
                                                                          "var rect = video.getBoundingClientRect();"
                                                                          "return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;"
                                                                      "}"
                                                                      "function browserResolveVideoElement() {"
                                                                          "var candidate = resolvedElement;"
                                                                          "while (candidate) {"
                                                                              "if (candidate.tagName && candidate.tagName.toLowerCase() === 'video') { return candidate; }"
                                                                              "candidate = candidate.parentElement;"
                                                                          "}"
                                                                          "var videos = document.querySelectorAll('video');"
                                                                          "var bestVisibleVideo = null;"
                                                                          "var bestVisibleArea = 0;"
                                                                          "for (var i = 0; i < videos.length; i++) {"
                                                                              "var video = videos[i];"
                                                                              "if (browserVideoContainsPoint(video)) { return video; }"
                                                                              "if (!video || typeof video.getBoundingClientRect !== 'function') { continue; }"
                                                                              "var rect = video.getBoundingClientRect();"
                                                                              "var visibleWidth = Math.max(0, Math.min(rect.right, window.innerWidth) - Math.max(rect.left, 0));"
                                                                              "var visibleHeight = Math.max(0, Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0));"
                                                                              "var visibleArea = visibleWidth * visibleHeight;"
                                                                              "if (visibleArea <= 0) { continue; }"
                                                                              "if (!video.paused && !video.ended && video.readyState >= 2) { return video; }"
                                                                              "if (visibleArea > bestVisibleArea) {"
                                                                                  "bestVisibleArea = visibleArea;"
                                                                                  "bestVisibleVideo = video;"
                                                                              "}"
                                                                          "}"
                                                                          "return bestVisibleVideo;"
                                                                      "}"
                                                                      "function browserResolvePrimarySource(video) {"
                                                                          "if (!video) { return ''; }"
                                                                          "if (video.currentSrc) { return browserAbsoluteURL(video.currentSrc); }"
                                                                          "if (video.src) { return browserAbsoluteURL(video.src); }"
                                                                          "var sources = video.querySelectorAll('source');"
                                                                          "for (var i = 0; i < sources.length; i++) {"
                                                                              "var sourceSrc = sources[i].src || sources[i].getAttribute('src') || '';"
                                                                              "if (sourceSrc) { return browserAbsoluteURL(sourceSrc); }"
                                                                          "}"
                                                                          "return '';"
                                                                      "}"
                                                                      "function browserResolveSourceList(video) {"
                                                                          "var values = [];"
                                                                          "if (!video) { return values; }"
                                                                          "if (video.currentSrc) { values.push(browserAbsoluteURL(video.currentSrc)); }"
                                                                          "if (video.src && values.indexOf(browserAbsoluteURL(video.src)) === -1) { values.push(browserAbsoluteURL(video.src)); }"
                                                                          "var sources = video.querySelectorAll('source');"
                                                                          "for (var i = 0; i < sources.length; i++) {"
                                                                              "var sourceSrc = sources[i].src || sources[i].getAttribute('src') || '';"
                                                                              "sourceSrc = browserAbsoluteURL(sourceSrc);"
                                                                              "if (sourceSrc && values.indexOf(sourceSrc) === -1) { values.push(sourceSrc); }"
                                                                          "}"
                                                                          "return values;"
                                                                      "}"
                                                                      "var video = browserResolveVideoElement();"
                                                                      "if (!video) { return ''; }"
                                                                      "return JSON.stringify({"
                                                                          "src: browserResolvePrimarySource(video),"
                                                                          "sources: browserResolveSourceList(video),"
                                                                          "poster: browserAbsoluteURL(video.poster || ''),"
                                                                          "title: video.getAttribute('title') || video.getAttribute('aria-label') || document.title || '',"
                                                                          "tagName: video.tagName ? video.tagName.toLowerCase() : '',"
                                                                          "paused: !!video.paused"
                                                                      "});"];
    return [self JSONObjectFromJavaScriptString:result];
}

- (BOOL)isNativePlayableVideoURLString:(NSString *)URLString {
    if (URLString.length == 0) {
        return NO;
    }

    NSString *lowercaseURLString = URLString.lowercaseString;
    if ([lowercaseURLString hasPrefix:@"blob:"] ||
        [lowercaseURLString hasPrefix:@"data:"] ||
        [lowercaseURLString hasPrefix:@"mediastream:"]) {
        return NO;
    }

    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL == nil) {
        return NO;
    }

    NSString *scheme = URL.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

- (void)presentNativeVideoPlayerForURL:(NSURL *)URL title:(NSString *)title {
    [self presentNativeVideoPlayerForURL:URL title:title requestHeaders:nil cookies:nil];
}

- (void)presentNativeVideoPlayerForURL:(NSURL *)URL
                                 title:(NSString *)title
                        requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
                               cookies:(NSArray<NSHTTPCookie *> *)cookies {
    if (URL == nil) {
        return;
    }

    BrowserNativeVideoPlayerViewController *playerViewController = [[BrowserNativeVideoPlayerViewController alloc] initWithURL:URL
                                                                                                                          title:title
                                                                                                                  requestHeaders:requestHeaders
                                                                                                                         cookies:cookies];
    [self presentViewController:playerViewController animated:YES completion:nil];
}

- (NSDictionary<NSString *, NSString *> *)browserHeadersForYouTubePlaybackURL:(NSURL *)playbackURL pageURL:(NSURL *)pageURL {
    if (playbackURL == nil || pageURL == nil) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSString *userAgent = [[NSUserDefaults standardUserDefaults] stringForKey:kUserAgentDefaultsKey];
    if (userAgent.length > 0) {
        headers[@"User-Agent"] = userAgent;
    }

    headers[@"Referer"] = pageURL.absoluteString ?: @"https://www.youtube.com/";
    NSString *origin = [NSString stringWithFormat:@"%@://%@", pageURL.scheme ?: @"https", pageURL.host ?: @"www.youtube.com"];
    headers[@"Origin"] = origin;

    NSArray<NSHTTPCookie *> *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:pageURL];
    if (cookies.count > 0) {
        NSDictionary<NSString *, NSString *> *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        NSString *cookieHeader = cookieHeaders[@"Cookie"];
        if (cookieHeader.length > 0) {
            headers[@"Cookie"] = cookieHeader;
        }
    }

    return headers.count > 0 ? headers : nil;
}

- (BOOL)cookie:(NSHTTPCookie *)cookie matchesHost:(NSString *)host {
    if (cookie == nil || host.length == 0) {
        return NO;
    }

    NSString *cookieDomain = cookie.domain.lowercaseString ?: @"";
    NSString *lowercaseHost = host.lowercaseString;
    if (cookieDomain.length == 0) {
        return NO;
    }

    if ([cookieDomain hasPrefix:@"."]) {
        cookieDomain = [cookieDomain substringFromIndex:1];
    }

    return [lowercaseHost isEqualToString:cookieDomain] || [lowercaseHost hasSuffix:[@"." stringByAppendingString:cookieDomain]];
}

- (NSArray<NSHTTPCookie *> *)browserCookiesForYouTubePlaybackURL:(NSURL *)playbackURL pageURL:(NSURL *)pageURL {
    NSMutableArray<NSHTTPCookie *> *matchingCookies = [NSMutableArray array];
    NSMutableSet<NSString *> *seenCookieKeys = [NSMutableSet set];
    NSArray<NSHTTPCookie *> *allCookies = [BrowserWebView allCookies];
    NSString *pageHost = pageURL.host.lowercaseString ?: @"";
    NSString *playbackHost = playbackURL.host.lowercaseString ?: @"";

    for (NSHTTPCookie *cookie in allCookies) {
        BOOL matches = [self cookie:cookie matchesHost:pageHost] ||
        [self cookie:cookie matchesHost:playbackHost] ||
        [self cookie:cookie matchesHost:@"youtube.com"] ||
        [self cookie:cookie matchesHost:@"googlevideo.com"];
        if (!matches) {
            continue;
        }

        NSString *cookieKey = [NSString stringWithFormat:@"%@|%@|%@", cookie.domain ?: @"", cookie.path ?: @"", cookie.name ?: @""];
        if ([seenCookieKeys containsObject:cookieKey]) {
            continue;
        }
        [seenCookieKeys addObject:cookieKey];
        [matchingCookies addObject:cookie];
    }

    return matchingCookies;
}

- (void)presentUnsupportedNativeVideoAlertForVideoInfo:(NSDictionary *)videoInfo {
    NSArray *sources = [videoInfo[@"sources"] isKindOfClass:[NSArray class]] ? videoInfo[@"sources"] : @[];
    NSString *sourceSummary = nil;
    if (sources.count > 0) {
        sourceSummary = [sources componentsJoinedByString:@"\n"];
    } else if (videoInfo.count > 0) {
        sourceSummary = @"No direct media URL was exposed by the page.";
    } else {
        sourceSummary = @"No video element was detected under the cursor.";
    }
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Native Video Unavailable"
                                                                             message:[NSString stringWithFormat:@"This page is not exposing a direct video URL that AVPlayer can open.\n\nDetected sources:\n%@", sourceSummary]
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)presentYouTubeExtractionError:(NSError *)error fallbackVideoInfo:(NSDictionary *)videoInfo {
    NSString *message = error.localizedDescription ?: @"Could not extract a better YouTube playback URL.";
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"YouTube Extraction Failed"
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    NSString *fallbackURLString = [videoInfo[@"src"] isKindOfClass:[NSString class]] ? videoInfo[@"src"] : @"";
    if ([self isNativePlayableVideoURLString:fallbackURLString]) {
        [alertController addAction:[UIAlertAction actionWithTitle:@"Play Current URL"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(__unused UIAlertAction *action) {
            NSURL *fallbackURL = [NSURL URLWithString:fallbackURLString];
            NSString *title = [videoInfo[@"title"] isKindOfClass:[NSString class]] ? videoInfo[@"title"] : weakSelf.webview.title;
            [weakSelf presentNativeVideoPlayerForURL:fallbackURL title:title];
        }]];
    }
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)playYouTubeVideoAtPageURL:(NSURL *)pageURL fallbackVideoInfo:(NSDictionary *)videoInfo {
    __weak typeof(self) weakSelf = self;
    [[self youTubeExtractor] extractPlaybackInfoFromPageURL:pageURL webView:self.webview completion:^(BrowserYouTubeExtractionResult *result, NSError *error) {
        if (result.playbackURL != nil) {
            NSString *title = result.title.length > 0 ? result.title : weakSelf.webview.title;
            NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionaryWithDictionary:result.requestHeaders ?: @{}];
            NSDictionary<NSString *, NSString *> *fallbackHeaders = [weakSelf browserHeadersForYouTubePlaybackURL:result.playbackURL pageURL:pageURL];
            [fallbackHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
                if (headers[key].length == 0 && value.length > 0) {
                    headers[key] = value;
                }
            }];

            NSArray<NSHTTPCookie *> *cookies = [weakSelf browserCookiesForYouTubePlaybackURL:result.playbackURL pageURL:pageURL];
            if (cookies.count > 0) {
                NSDictionary<NSString *, NSString *> *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
                NSString *cookieHeader = cookieHeaders[@"Cookie"];
                if (cookieHeader.length > 0) {
                    headers[@"Cookie"] = cookieHeader;
                }
            }

            [weakSelf presentNativeVideoPlayerForURL:result.playbackURL
                                               title:title
                                      requestHeaders:headers.count > 0 ? headers : nil
                                             cookies:cookies];
            return;
        }

        [weakSelf presentYouTubeExtractionError:error fallbackVideoInfo:videoInfo ?: @{}];
    }];
}

- (void)playVideoUnderCursorIfAvailable {
    UIViewController *presentedViewController = self.presentedViewController;
    if (!self.cursorMode ||
        (presentedViewController != nil && ![presentedViewController isKindOfClass:[UIAlertController class]])) {
        return;
    }

    NSURL *pageURL = self.webview.request.URL;
    CGPoint point = [self browserDOMPointForCursor];
    NSDictionary *videoInfo = [self videoInfoAtDOMPoint:point];
    if ([[self youTubeExtractor] canExtractFromPageURL:pageURL]) {
        [self playYouTubeVideoAtPageURL:pageURL fallbackVideoInfo:videoInfo];
        return;
    }

    NSString *videoURLString = [videoInfo[@"src"] isKindOfClass:[NSString class]] ? videoInfo[@"src"] : @"";
    if (![self isNativePlayableVideoURLString:videoURLString]) {
        [self presentUnsupportedNativeVideoAlertForVideoInfo:videoInfo ?: @{}];
        return;
    }

    NSURL *videoURL = [NSURL URLWithString:videoURLString];
    NSString *title = [videoInfo[@"title"] isKindOfClass:[NSString class]] ? videoInfo[@"title"] : self.webview.title;
    [self presentNativeVideoPlayerForURL:videoURL title:title];
}

- (BOOL)isPrimaryDocumentRequest:(NSURLRequest *)request {
    NSURL *requestURL = request.URL;
    NSURL *mainDocumentURL = request.mainDocumentURL;
    if (requestURL == nil) {
        return NO;
    }
    if (mainDocumentURL == nil) {
        return YES;
    }
    return [requestURL isEqual:mainDocumentURL];
}

- (void)updateStoredScrollOffsetForTab:(BrowserTabViewModel *)tab {
    if (tab == nil) {
        return;
    }
    
    id webView = self.webViewsByTabIdentifier[tab.identifier];
    if (webView == nil) {
        return;
    }
    
    UIScrollView *scrollView = [webView scrollView];
    tab.savedScrollOffset = scrollView.contentOffset;
    tab.hasSavedScrollOffset = YES;
}

- (void)persistBrowserSession {
    for (BrowserTabViewModel *tab in self.viewModel.tabs) {
        [self updateStoredScrollOffsetForTab:tab];
    }
    [self.sessionStore saveSessionForViewModel:self.viewModel];
}

- (BOOL)restoreBrowserSession {
    return [self.sessionStore restoreSessionIntoViewModel:self.viewModel];
}

- (NSURLRequest *)requestWithURLString:(NSString *)URLString {
    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL == nil) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    NSString *userAgent = [[NSUserDefaults standardUserDefaults] stringForKey:kUserAgentDefaultsKey];
    if (userAgent.length > 0) {
        [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    return request;
}

- (void)loadStoredContentForTab:(BrowserTabViewModel *)tab {
    if (tab == nil) {
        [self loadHomePage];
        return;
    }
    
    NSString *URLString = tab.URLString.length > 0 ? tab.URLString : tab.requestURL;
    if (URLString.length == 0) {
        [self loadHomePage];
        return;
    }

    NSURLRequest *request = [self requestWithURLString:URLString];
    if (request != nil) {
        [self.webview loadRequest:request];
    }
}

- (void)restoreSavedScrollOffsetForTab:(BrowserTabViewModel *)tab webView:(id)webView {
    if (tab == nil || !tab.needsScrollRestore || !tab.hasSavedScrollOffset) {
        return;
    }
    
    UIScrollView *scrollView = [webView scrollView];
    CGPoint savedScrollOffset = tab.savedScrollOffset;
    dispatch_async(dispatch_get_main_queue(), ^{
        [scrollView layoutIfNeeded];
        CGFloat maxOffsetX = MAX(0.0, scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds));
        CGFloat maxOffsetY = MAX(0.0, scrollView.contentSize.height - CGRectGetHeight(scrollView.bounds));
        CGPoint clampedScrollOffset = CGPointMake(MIN(MAX(savedScrollOffset.x, 0.0), maxOffsetX),
                                                  MIN(MAX(savedScrollOffset.y, 0.0), maxOffsetY));
        [scrollView setContentOffset:clampedScrollOffset animated:NO];
        tab.savedScrollOffset = clampedScrollOffset;
        tab.hasSavedScrollOffset = YES;
        [self captureSnapshotForTab:tab];
        [self persistBrowserSession];
    });
    tab.needsScrollRestore = NO;
}

- (void)attachActiveWebView {
    BrowserTabViewModel *tab = [self activeTab];
    if (tab == nil) {
        return;
    }
    
    id activeWebView = self.webViewsByTabIdentifier[tab.identifier];
    if (activeWebView == nil) {
        return;
    }
    
    for (BrowserTabViewModel *candidate in self.viewModel.tabs) {
        [self.webViewsByTabIdentifier[candidate.identifier] removeFromSuperview];
    }
    
    self.webview = activeWebView;
    [self.topMenuView.loadingSpinner stopAnimating];
    [self.browserContainerView addSubview:self.webview];
    [self updateTopNavAndWebView];
    
    UIScrollView *scrollView = [self.webview scrollView];
    [scrollView setNeedsLayout];
    [scrollView layoutIfNeeded];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    scrollView.bounces = self.scrollViewAllowBounces;
    scrollView.scrollEnabled = !self.cursorMode && !self.tabOverviewVisible;
    [self.webview setUserInteractionEnabled:!self.cursorMode && !self.tabOverviewVisible];
    self.manualScrollPanRecognizer.enabled = !self.cursorMode && !self.tabOverviewVisible;
    
    [self refreshActiveTabUI];
}

- (void)setCursorModeEnabled:(BOOL)cursorMode {
    BOOL wasCursorMode = self.cursorMode;
    self.cursorMode = cursorMode;
    self.lastTouchLocation = CGPointMake(-1, -1);
    [self stopManualScrollInertia];
    UIScrollView *scrollView = [self.webview scrollView];
    BOOL shouldAllowWebInteraction = !cursorMode && !self.tabOverviewVisible;
    scrollView.scrollEnabled = shouldAllowWebInteraction;
    [self.webview setUserInteractionEnabled:shouldAllowWebInteraction];
    self.manualScrollPanRecognizer.enabled = shouldAllowWebInteraction;
    self.cursorView.hidden = self.tabOverviewVisible ? NO : !cursorMode;

    if (!wasCursorMode && cursorMode) {
        [self persistBrowserSession];
    }
}

- (void)captureSnapshotForTab:(BrowserTabViewModel *)tab {
    if (tab == nil) {
        return;
    }
    
    if (!tab.needsScrollRestore) {
        [self updateStoredScrollOffsetForTab:tab];
    }
    
    id webView = self.webViewsByTabIdentifier[tab.identifier];
    if (webView == nil || CGRectIsEmpty([webView bounds])) {
        return;
    }
    
    UIGraphicsBeginImageContextWithOptions([webView bounds].size, YES, 0.0);
    [webView drawViewHierarchyInRect:[webView bounds] afterScreenUpdates:NO];
    UIImage *snapshotImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (snapshotImage != nil) {
        tab.snapshotImage = snapshotImage;
    }
}

- (void)showMaxTabsAlert {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Maximum Tabs Reached"
                                                                             message:@"This build keeps up to five tabs open at once."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Dismiss"
                                                        style:UIAlertActionStyleCancel
                                                      handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)createNewTabLoadingHomePage:(BOOL)loadHomePage {
    BrowserTabViewModel *tab = [self.viewModel addTab];
    if (tab == nil) {
        [self showMaxTabsAlert];
        return;
    }
    
    [self initWebView];
    [self refreshActiveTabUI];
    [self.view bringSubviewToFront:self.cursorView];
    
    if (loadHomePage) {
        [self loadHomePage];
    }
    [self persistBrowserSession];
}

- (void)switchToTabAtIndex:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex >= self.viewModel.tabs.count) {
        return;
    }
    
    BrowserTabViewModel *currentTab = [self activeTab];
    [self captureSnapshotForTab:currentTab];
    
    [self.viewModel switchToTabAtIndex:tabIndex];
    [self initWebView];
    [self.view bringSubviewToFront:self.cursorView];
    if ([self.webview request] == nil) {
        [self loadStoredContentForTab:[self activeTab]];
    }
    [self persistBrowserSession];
}

- (void)closeTabAtIndex:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex >= self.viewModel.tabs.count) {
        return;
    }
    
    BOOL closingActiveTab = tabIndex == self.viewModel.activeTabIndex;
    BrowserTabViewModel *tab = self.viewModel.tabs[tabIndex];
    [self.webViewsByTabIdentifier[tab.identifier] removeFromSuperview];
    [self.webViewsByTabIdentifier removeObjectForKey:tab.identifier];
    [self.viewModel removeTabAtIndex:tabIndex];
    
    if (self.viewModel.tabs.count == 0) {
        [self createNewTabLoadingHomePage:YES];
        return;
    }
    
    if (closingActiveTab) {
        [self initWebView];
        if ([self.webview request] == nil) {
            [self loadStoredContentForTab:[self activeTab]];
        }
    }
    
    [self refreshActiveTabUI];
    [self persistBrowserSession];
}

- (void)recreateActiveWebViewPreservingCurrentURL {
    BrowserTabViewModel *tab = [self activeTab];
    if (tab == nil) {
        return;
    }
    
    NSString *currentURL = [self.webview request].URL.absoluteString;
    [self.webViewsByTabIdentifier[tab.identifier] removeFromSuperview];
    [self.webViewsByTabIdentifier removeObjectForKey:tab.identifier];
    tab.requestURL = currentURL;
    tab.previousURL = @"";
    tab.URLString = currentURL ?: @"";
    [self initWebView];
    
    if (currentURL.length > 0) {
        NSURLRequest *request = [self requestWithURLString:currentURL];
        if (request != nil) {
            [self.webview loadRequest:request];
        }
    } else {
        [self loadHomePage];
    }
    [self persistBrowserSession];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    //loadingSpinner.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    [self webViewDidAppear];
    _displayedHintsOnLaunch = YES;
}
-(void)webViewDidAppear {
    if ([[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"] != nil) {
        NSURLRequest *request = [self requestWithURLString:[[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"]];
        if (request != nil) {
            [self.webview loadRequest:request];
        }
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"savedURLtoReopen"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    else if ([self.webview request] == nil) {
        [self loadStoredContentForTab:[self activeTab]];
    }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DontShowHintsOnLaunch"] && !_displayedHintsOnLaunch) {
        [self showHintsAlert];
    }
}
-(void)loadHomePage {
    NSURLRequest *homePageRequest = [self.navigationService homePageRequest];
    if (homePageRequest != nil) {
        [self.webview loadRequest:homePageRequest];
    }
}
-(void)initWebView {
    self.topMenuView.hidden = !self.viewModel.topNavigationBarVisible;
    
    BrowserTabViewModel *tab = [self.viewModel ensureActiveTab];
    if (tab == nil) {
        return;
    }
    
    id webView = self.webViewsByTabIdentifier[tab.identifier];
    if (webView == nil) {
        webView = [self createConfiguredWebView];
        self.webViewsByTabIdentifier[tab.identifier] = webView;
    }
    self.webview = webView;
    [self attachActiveWebView];
}
-(void)viewDidLoad {
    [super viewDidLoad];
    self.definesPresentationContext = YES;
    self.scrollViewAllowBounces = YES;
    self.menuPresenter = [[BrowserMenuPresenter alloc] initWithHost:self];
    self.navigationService = [BrowserNavigationService new];
    self.sessionStore = [BrowserSessionStore new];
    self.viewModel = [BrowserViewModel new];
    self.webViewsByTabIdentifier = [NSMutableDictionary dictionary];
    self.tabOverviewCardViews = [NSMutableArray array];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationWillTerminate:)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleGlobalSelectPressEndedNotification:)
                                                 name:kBrowserGlobalSelectPressEndedNotification
                                               object:nil];

    self.playPauseDoubleTapRecognizer = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handlePlayPauseDoubleTap:)];
    self.playPauseDoubleTapRecognizer.numberOfTapsRequired = 2;
    self.playPauseDoubleTapRecognizer.allowedPressTypes = @[[NSNumber numberWithInteger:UIPressTypePlayPause]];

    [self.view addGestureRecognizer:self.playPauseDoubleTapRecognizer];

    self.manualScrollPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleManualScrollPan:)];
    self.manualScrollPanRecognizer.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
    self.manualScrollPanRecognizer.cancelsTouchesInView = NO;
    self.manualScrollPanRecognizer.enabled = NO;
    [self.view addGestureRecognizer:self.manualScrollPanRecognizer];
    
    self.cursorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
    self.cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    self.cursorView.image = kDefaultCursor();
    [self.view addSubview:self.cursorView];
    
    
    
    // Spinner now also in Storyboard.
    /*loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    loadingSpinner.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    loadingSpinner.tintColor = [UIColor blackColor];*/
    
    self.topMenuView.loadingSpinner.hidesWhenStopped = YES;
    
    //[loadingSpinner startAnimating];
    //[self.view addSubview:loadingSpinner];
    //[self.browserContainerView addSubview:loadingSpinner]; // Now in Storyboard

    //[self.view bringSubviewToFront:loadingSpinner];
    //ENABLE CURSOR MODE INITIALLY
    self.cursorMode = YES;
    self.cursorView.hidden = NO;
    
    [self setupTabOverview];
    if (![self restoreBrowserSession]) {
        [self createNewTabLoadingHomePage:NO];
    } else {
        [self initWebView];
        [self refreshActiveTabUI];
    }
}

- (void)dealloc {
    [self stopManualScrollInertia];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopManualScrollInertia];
}

#pragma mark - Font Size
- (NSUInteger)textFontSize {
    return self.viewModel.textFontSize;
}

- (void)setTextFontSize:(NSUInteger)textFontSize {
    if (textFontSize == self.viewModel.textFontSize) {
        return;
    }
    self.viewModel.textFontSize = textFontSize;
}

- (void)updateTextFontSize {
    NSString *jsString = [[NSString alloc] initWithFormat:
                          @"(function(){"
                           "var value='%lu%%';"
                           "var multiplier=%lu/100;"
                           "if (document.documentElement && document.documentElement.style) {"
                               "document.documentElement.style.setProperty('-webkit-text-size-adjust', value, 'important');"
                               "document.documentElement.style.setProperty('text-size-adjust', value, 'important');"
                           "}"
                           "if (document.body && document.body.style) {"
                               "document.body.style.setProperty('-webkit-text-size-adjust', value, 'important');"
                               "document.body.style.setProperty('text-size-adjust', value, 'important');"
                           "}"
                           "if (!document.body || !window.getComputedStyle) { return value; }"
                           "var elements = document.querySelectorAll('body, body *');"
                           "for (var i = 0; i < elements.length; i++) {"
                               "var element = elements[i];"
                               "if (!element || !element.tagName) { continue; }"
                               "var tagName = element.tagName.toLowerCase();"
                               "if (tagName === 'script' || tagName === 'style' || tagName === 'noscript') { continue; }"
                               "var originalSize = element.getAttribute('data-browser-original-font-size');"
                               "if (!originalSize) {"
                                   "var computedSize = window.getComputedStyle(element).fontSize || '';"
                                   "if (computedSize.indexOf('px') === -1) { continue; }"
                                   "var parsedSize = parseFloat(computedSize);"
                                   "if (!isFinite(parsedSize) || parsedSize <= 0) { continue; }"
                                   "originalSize = String(parsedSize);"
                                   "element.setAttribute('data-browser-original-font-size', originalSize);"
                               "}"
                               "var baseSize = parseFloat(originalSize);"
                               "if (!isFinite(baseSize) || baseSize <= 0) { continue; }"
                               "element.style.setProperty('font-size', (baseSize * multiplier) + 'px', 'important');"
                           "}"
                           "return value;"
                          "})()",
                          (unsigned long)self.textFontSize,
                          (unsigned long)self.textFontSize];
    [self.webview stringByEvaluatingJavaScriptFromString:jsString];
}

#pragma mark - Top Navigation Bar

- (BOOL)topMenuShowing {
    return self.viewModel.topNavigationBarVisible;
}

- (CGFloat)topMenuBrowserOffset {
    if (self.topMenuShowing) {
        return self.topMenuView.frame.size.height;
    } else {
        return 0;
    }
}

-(void)hideTopNav
{
    self.viewModel.topNavigationBarVisible = NO;
    [self.topMenuView setHidden:YES];
    
    [self updateTopNavAndWebView];
}

-(void)showTopNav
{
    self.viewModel.topNavigationBarVisible = YES;
    [self.topMenuView setHidden:NO];
    
    [self updateTopNavAndWebView];
}

-(void)updateTopNavAndWebView
{
    if (self.topMenuShowing) {
        [self.webview setFrame:CGRectMake(self.view.bounds.origin.x, self.view.bounds.origin.y + self.topMenuBrowserOffset, self.view.bounds.size.width, self.view.bounds.size.height - self.topMenuBrowserOffset)];
    } else {
        [self.webview setFrame:self.view.bounds];
    }
}

- (void)setupTabOverview {
    self.tabOverviewOverlayView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.tabOverviewOverlayView.frame = self.view.bounds;
    self.tabOverviewOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tabOverviewOverlayView.hidden = YES;
    self.tabOverviewOverlayView.alpha = 0.97;
    self.tabOverviewOverlayView.userInteractionEnabled = NO;
    
    self.tabOverviewPanelView = [[UIView alloc] initWithFrame:CGRectMake((CGRectGetWidth(self.view.bounds) - kTabOverviewPanelWidth) / 2.0,
                                                                         160.0,
                                                                         kTabOverviewPanelWidth,
                                                                         kTabOverviewPanelHeight)];
    self.tabOverviewPanelView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    self.tabOverviewPanelView.layer.cornerRadius = 26.0;
    self.tabOverviewPanelView.clipsToBounds = YES;
    self.tabOverviewPanelView.userInteractionEnabled = NO;
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(48.0, 32.0, 600.0, 46.0)];
    titleLabel.text = @"Tabs";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    [self.tabOverviewPanelView addSubview:titleLabel];
    
    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(48.0, 80.0, 720.0, 34.0)];
    subtitleLabel.text = @"Switch tabs, close tabs, or open something new.";
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [self.tabOverviewPanelView addSubview:subtitleLabel];
    
    self.tabOverviewAddButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.tabOverviewAddButton.frame = CGRectMake(CGRectGetWidth(self.tabOverviewPanelView.bounds) - 112.0, 32.0, 64.0, 64.0);
    [self.tabOverviewAddButton setImage:[UIImage imageNamed:@"plus"] forState:UIControlStateNormal];
    self.tabOverviewAddButton.tag = 9001;
    self.tabOverviewAddButton.userInteractionEnabled = NO;
    [self.tabOverviewPanelView addSubview:self.tabOverviewAddButton];
    
    CGFloat addTabLabelWidth = 180.0;
    CGFloat addTabLabelX = CGRectGetMidX(self.tabOverviewAddButton.frame) - (addTabLabelWidth / 2.0);
    UILabel *addTabLabel = [[UILabel alloc] initWithFrame:CGRectMake(addTabLabelX, 98.0, addTabLabelWidth, 28.0)];
    addTabLabel.text = @"New Tab";
    addTabLabel.textAlignment = NSTextAlignmentCenter;
    addTabLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    addTabLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    [self.tabOverviewPanelView addSubview:addTabLabel];
    
    self.tabOverviewScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(48.0,
                                                                                148.0,
                                                                                kTabOverviewPanelWidth - 96.0,
                                                                                kTabOverviewPanelHeight - 196.0)];
    self.tabOverviewScrollView.showsHorizontalScrollIndicator = NO;
    self.tabOverviewScrollView.showsVerticalScrollIndicator = NO;
    self.tabOverviewScrollView.alwaysBounceHorizontal = YES;
    self.tabOverviewScrollView.alwaysBounceVertical = NO;
    self.tabOverviewScrollView.userInteractionEnabled = NO;
    [self.tabOverviewPanelView addSubview:self.tabOverviewScrollView];
    
    [self.tabOverviewOverlayView.contentView addSubview:self.tabOverviewPanelView];
    [self.view addSubview:self.tabOverviewOverlayView];
}

- (void)reloadTabOverview {
    for (UIView *subview in self.tabOverviewScrollView.subviews) {
        [subview removeFromSuperview];
    }
    [self.tabOverviewCardViews removeAllObjects];
    
    CGFloat currentX = kTabCardGlowInset;
    CGFloat usableWidth = CGRectGetWidth(self.tabOverviewScrollView.bounds);
    for (NSInteger index = 0; index < self.viewModel.tabs.count; index++) {
        BrowserTabViewModel *tab = self.viewModel.tabs[index];
        UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(currentX, kTabCardGlowInset, kTabCardWidth, kTabCardHeight)];
        cardView.tag = 1000 + index;
        cardView.backgroundColor = UIColor.clearColor;
        cardView.layer.cornerRadius = 24.0;
        cardView.clipsToBounds = NO;
        if (index == self.viewModel.activeTabIndex) {
            cardView.layer.shadowColor = [UIColor colorWithRed:0.23 green:0.57 blue:1.0 alpha:1.0].CGColor;
            cardView.layer.shadowOffset = CGSizeZero;
            cardView.layer.shadowOpacity = 0.75;
            cardView.layer.shadowRadius = 9.0;
        } else {
            cardView.layer.shadowOpacity = 0.0;
        }
        
        UIView *cardContentView = [[UIView alloc] initWithFrame:cardView.bounds];
        cardContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cardContentView.backgroundColor = [UIColor colorWithWhite:index == self.viewModel.activeTabIndex ? 0.18 : 0.14 alpha:1.0];
        cardContentView.layer.cornerRadius = 24.0;
        cardContentView.clipsToBounds = YES;
        [cardView addSubview:cardContentView];
        
        UIImageView *thumbnailView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, kTabCardWidth, 150.0)];
        thumbnailView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        thumbnailView.clipsToBounds = YES;
        thumbnailView.image = tab.snapshotImage;
        [cardContentView addSubview:thumbnailView];
        
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 164.0, kTabCardWidth - 36.0, 26.0)];
        titleLabel.text = tab.title.length > 0 ? tab.title : @"New Tab";
        titleLabel.textColor = UIColor.whiteColor;
        titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        [cardContentView addSubview:titleLabel];
        
        UILabel *urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 194.0, kTabCardWidth - 36.0, 32.0)];
        urlLabel.text = tab.URLString.length > 0 ? tab.URLString : @"Home page";
        urlLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        urlLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        urlLabel.numberOfLines = 2;
        [cardContentView addSubview:urlLabel];
        
        if (self.viewModel.tabs.count > 1) {
            UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
            closeButton.frame = CGRectMake(kTabCardWidth - 86.0, 14.0, 72.0, 30.0);
            closeButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.42];
            [closeButton setTitle:@"Close" forState:UIControlStateNormal];
            [closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            closeButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
            closeButton.layer.cornerRadius = 15.0;
            closeButton.tag = 2000 + index;
            [cardContentView addSubview:closeButton];
        }
        
        [self.tabOverviewScrollView addSubview:cardView];
        [self.tabOverviewCardViews addObject:cardView];
        currentX += kTabCardWidth + kTabCardSpacing;
    }
    
    CGFloat contentWidth = MAX(usableWidth, currentX - kTabCardSpacing + kTabCardGlowInset);
    self.tabOverviewScrollView.contentSize = CGSizeMake(contentWidth, kTabCardHeight + (kTabCardGlowInset * 2.0));
}

- (void)showTabOverview {
    [self captureSnapshotForTab:[self activeTab]];
    [self reloadTabOverview];
    self.cursorModeBeforeShowingTabOverview = self.cursorMode;
    self.tabOverviewVisible = YES;
    self.tabOverviewOverlayView.hidden = NO;
    [self setCursorModeEnabled:YES];
    [self.view bringSubviewToFront:self.tabOverviewOverlayView];
    if (!self.topMenuView.isHidden) {
        [self.view bringSubviewToFront:self.topMenuView];
    }
    [self.view bringSubviewToFront:self.cursorView];
}

- (void)dismissTabOverview {
    if (!self.tabOverviewVisible) {
        return;
    }
    
    self.tabOverviewVisible = NO;
    self.tabOverviewOverlayView.hidden = YES;
    [self setCursorModeEnabled:self.cursorModeBeforeShowingTabOverview];
}

- (BOOL)tabOverviewContainsPoint:(CGPoint)viewPoint {
    if (!self.tabOverviewVisible) {
        return NO;
    }
    
    CGPoint overlayPoint = [self.view convertPoint:viewPoint toView:self.tabOverviewOverlayView.contentView];
    return CGRectContainsPoint(self.tabOverviewPanelView.frame, overlayPoint);
}

- (void)handleWebViewPanGesture:(UIPanGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state != UIGestureRecognizerStateEnded &&
        gestureRecognizer.state != UIGestureRecognizerStateCancelled &&
        gestureRecognizer.state != UIGestureRecognizerStateFailed) {
        return;
    }

    UIView *gestureView = gestureRecognizer.view;
    if (![gestureView isKindOfClass:[UIScrollView class]]) {
        return;
    }

    UIScrollView *scrollView = (UIScrollView *)gestureView;
    if (scrollView != [self.webview scrollView]) {
        return;
    }

    [self persistBrowserSession];
}

- (void)handleManualScrollPan:(UIPanGestureRecognizer *)gestureRecognizer {
    if (self.cursorMode || self.tabOverviewVisible) {
        return;
    }

    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [self stopManualScrollInertia];
    }

    CGPoint translation = [gestureRecognizer translationInView:self.view];
    if (!CGPointEqualToPoint(translation, CGPointZero)) {
        [self applyManualScrollDelta:CGPointMake(-translation.x, -translation.y)];
        [gestureRecognizer setTranslation:CGPointZero inView:self.view];
        self.manualScrollLastMovementTimestamp = CACurrentMediaTime();
    }

    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        CFTimeInterval timeSinceLastMovement = CACurrentMediaTime() - self.manualScrollLastMovementTimestamp;
        CGPoint velocity = [gestureRecognizer velocityInView:self.view];
        if (timeSinceLastMovement < 0.08) {
            [self startManualScrollInertiaWithVelocity:CGPointMake(-velocity.x, -velocity.y)];
        } else {
            [self stopManualScrollInertia];
        }
        [self persistBrowserSession];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateCancelled ||
               gestureRecognizer.state == UIGestureRecognizerStateFailed) {
        [self stopManualScrollInertia];
        [self persistBrowserSession];
    }
}

- (BOOL)handleTabOverviewSelectionAtPoint:(CGPoint)viewPoint {
    if (!self.tabOverviewVisible) {
        return NO;
    }
    
    CGPoint overlayPoint = [self.view convertPoint:viewPoint toView:self.tabOverviewOverlayView.contentView];
    if (!CGRectContainsPoint(self.tabOverviewPanelView.frame, overlayPoint)) {
        [self dismissTabOverview];
        return YES;
    }
    
    CGPoint panelPoint = [self.view convertPoint:viewPoint toView:self.tabOverviewPanelView];
    if (CGRectContainsPoint(self.tabOverviewAddButton.frame, panelPoint)) {
        [self createNewTabLoadingHomePage:YES];
        [self dismissTabOverview];
        return YES;
    }
    
    CGPoint scrollPoint = [self.view convertPoint:viewPoint toView:self.tabOverviewScrollView];
    for (UIView *cardView in self.tabOverviewCardViews) {
        if (!CGRectContainsPoint(cardView.frame, scrollPoint)) {
            continue;
        }
        
        NSInteger tabIndex = cardView.tag - 1000;
        UIView *closeButton = [cardView viewWithTag:2000 + tabIndex];
        if (closeButton != nil) {
            CGRect closeButtonFrame = [cardView convertRect:closeButton.frame toView:self.tabOverviewScrollView];
            if (CGRectContainsPoint(closeButtonFrame, scrollPoint)) {
                [self closeTabAtIndex:tabIndex];
                [self reloadTabOverview];
                return YES;
            }
        }
        
        [self switchToTabAtIndex:tabIndex];
        [self dismissTabOverview];
        return YES;
    }
    
    return YES;
}

#pragma mark - Gesture
-(void)handlePlayPauseDoubleTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        if (self.tabOverviewVisible) {
            [self dismissTabOverview];
            return;
        }
        [self showAdvancedMenu];
    }
}
-(void)handleTouchSurfaceDoubleTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        if (self.tabOverviewVisible) {
            return;
        }
        [self toggleMode];
    }
}

-(void)showInputURLorSearchGoogle
{
    UIAlertController *alertController2 = [UIAlertController
                                           alertControllerWithTitle:@"Enter URL or Search Terms"
                                           message:@""
                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController2 addTextFieldWithConfigurationHandler:^(UITextField *textField)
     {
         textField.keyboardType = UIKeyboardTypeURL;
         textField.placeholder = @"Enter URL or Search Terms";
         textField.textColor = kTextColor();
         [textField setReturnKeyType:UIReturnKeyDone];
         [textField addTarget:self
                       action:@selector(alertTextFieldShouldReturn:)
             forControlEvents:UIControlEventEditingDidEnd];
         
     }];
    
    
    UIAlertAction *goAction = [UIAlertAction
                               actionWithTitle:@"Go To Website"
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action)
                               {
                                   UITextField *urltextfield = alertController2.textFields[0];
                                   NSString *toMod = urltextfield.text;
                                   /*
                                    if ([toMod containsString:@" "] || ![temporaryURL containsString:@"."]) {
                                    toMod = [toMod stringByReplacingOccurrencesOfString:@" " withString:@"+"];
                                    toMod = [toMod stringByReplacingOccurrencesOfString:@"." withString:@"+"];
                                    toMod = [toMod stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
                                    toMod = [toMod stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
                                    toMod = [toMod stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
                                    toMod = [toMod stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                                    if (toMod != nil) {
                                    [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/search?q=%@", toMod]]]];
                                    }
                                    else {
                                    [self requestURLorSearchInput];
                                    }
                                    }
                                    else {
                                   */
                                   if (![toMod isEqualToString:@""]) {
                                       NSURLRequest *navigationRequest = [self.navigationService requestForEnteredAddressString:toMod];
                                       if (navigationRequest != nil) {
                                           [self.webview loadRequest:navigationRequest];
                                       }
                                       else {
                                           [self requestURLorSearchInput];
                                       }
                                   }
                                   else {
                                       [self requestURLorSearchInput];
                                   }
                                   //}
                                   
                               }];
    
    UIAlertAction *searchAction = [UIAlertAction
                                   actionWithTitle:@"Search Google"
                                   style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action)
                                   {
                                       UITextField *urltextfield = alertController2.textFields[0];
                                       NSURLRequest *searchRequest = [self.navigationService googleSearchRequestForQuery:urltextfield.text];
                                       if (searchRequest != nil) {
                                           [self.webview loadRequest:searchRequest];
                                       }
                                       else {
                                           [self requestURLorSearchInput];
                                       }
                                   }];
    
    UIAlertAction *cancelAction = [UIAlertAction
                                   actionWithTitle:nil
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    
    [alertController2 addAction:searchAction];
    [alertController2 addAction:goAction];
    [alertController2 addAction:cancelAction];
    
    [self presentViewController:alertController2 animated:YES completion:nil];
    
    NSURLRequest *request = [self.webview request];

    
    if (request == nil) {
        UITextField *loginTextField = alertController2.textFields[0];
        [loginTextField becomeFirstResponder];
    }
    else if (![request.URL.absoluteString  isEqual: @""]) {
        UITextField *loginTextField = alertController2.textFields[0];
        [loginTextField becomeFirstResponder];
    }
    
    
    
    
}

-(void)requestURLorSearchInput
{
    
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:@"Quick Menu"
                                          message:@""
                                          preferredStyle:UIAlertControllerStyleAlert];
    
    
    
    
    
    
    
    
    
    UIAlertAction *forwardAction = [UIAlertAction
                                   actionWithTitle:@"Go Forward"
                                   style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action)
                                   {
                                       [self.webview goForward];
                                   }];
    
    
    UIAlertAction *reloadAction = [UIAlertAction
                                   actionWithTitle:@"Reload Page"
                                   style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action)
                                   {
                                       self.previousURL = @"";
                                       [self.webview reload];
                                   }];
    
    
    UIAlertAction *cancelAction = [UIAlertAction
                                   actionWithTitle:nil
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    
    UIAlertAction *inputAction = [UIAlertAction
                                  actionWithTitle:@"Input URL or Search with Google"
                                  style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction *action)
                                  {
                                      
                                      [self showInputURLorSearchGoogle];
                                      
                                  }];
    
    
    if([self.webview canGoForward])
        [alertController addAction:forwardAction];
    
    [alertController addAction:inputAction];
    
    NSURLRequest *request = [self.webview request];
    if (request != nil) {
        if (![request.URL.absoluteString  isEqual: @""]) {
            [alertController addAction:reloadAction];
        }
    }
    [alertController addAction:cancelAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
    
    
    
    
    
    
}
#pragma mark - UIWebViewDelegate
-(void) webViewDidStartLoad:(id)webView {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return;
    }
    
    if (tab == [self activeTab] && ![tab.previousURL isEqualToString:tab.requestURL]) {
        [self.topMenuView.loadingSpinner startAnimating];
    }
    tab.previousURL = tab.requestURL;
}
-(void) webViewDidFinishLoad:(id)webView {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return;
    }
    
    if (tab == [self activeTab]) {
        [self.topMenuView.loadingSpinner stopAnimating];
    }
    
    NSString *theTitle=[webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    NSURLRequest *request = [webView request];
    NSString *currentURL = request.URL.absoluteString ?: @"";
    [self.navigationService updateTab:tab withPageTitle:theTitle currentURLString:currentURL];
    
    if (tab == [self activeTab]) {
        [self refreshActiveTabUI];
    }
    [self restoreSavedScrollOffsetForTab:tab webView:webView];
    if (!tab.needsScrollRestore) {
        [self captureSnapshotForTab:tab];
        [self persistBrowserSession];
    }
}

- (void)showAdvancedMenu {
    [self.menuPresenter showAdvancedMenu];
}

- (BOOL)webView:(id)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return YES;
    }
    if (![self isPrimaryDocumentRequest:request]) {
        return YES;
    }
    NSString *requestURL = request.URL.absoluteString ?: @"";
    if (tab.URLString.length > 0 && ![tab.URLString isEqualToString:requestURL]) {
        tab.savedScrollOffset = CGPointZero;
        tab.hasSavedScrollOffset = NO;
        tab.needsScrollRestore = NO;
    }
    tab.requestURL = request.URL.absoluteString;
    return YES;
}

- (void)webView:(id)webView didFailLoadWithError:(NSError *)error {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return;
    }

    NSURL *failingURL = error.userInfo[NSURLErrorFailingURLErrorKey];
    NSURLRequest *currentRequest = [webView request];
    NSString *currentRequestURLString = currentRequest.URL.absoluteString ?: @"";
    if (failingURL != nil && currentRequestURLString.length > 0 && ![failingURL.absoluteString isEqualToString:currentRequestURLString]) {
        return;
    }
    
    if (tab == [self activeTab]) {
        [self.topMenuView.loadingSpinner stopAnimating];
    }
    
    if (tab != [self activeTab]) {
        return;
    }
    
    if (![self.navigationService shouldIgnoreLoadError:error]) {
        UIAlertController *alertController = [UIAlertController
                                              alertControllerWithTitle:@"Could Not Load Webpage"
                                              message:[error localizedDescription]
                                              preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *searchAction = [UIAlertAction
                                       actionWithTitle:@"Google This Page"
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action)
                                       {
                                           if (tab.requestURL != nil) {
                                               NSURLRequest *searchRequest = [self.navigationService googleSearchRequestForFailedRequestURLString:tab.requestURL];
                                               if (searchRequest != nil) {
                                                   [self.webview loadRequest:searchRequest];
                                               }
                                           }
                                           
                                       }];
        UIAlertAction *reloadAction = [UIAlertAction
                                       actionWithTitle:@"Reload Page"
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action)
                                       {
                                           self.previousURL = @"";
                                           [self.webview reload];
                                       }];
        UIAlertAction *newurlAction = [UIAlertAction
                                       actionWithTitle:@"Enter a URL or Search"
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action)
                                       {
                                           [self requestURLorSearchInput];
                                       }];
        UIAlertAction *cancelAction = [UIAlertAction
                                       actionWithTitle:nil
                                       style:UIAlertActionStyleCancel
                                       handler:nil];
        if (tab.requestURL != nil) {
            if ([tab.requestURL length] > 1) {
                [alertController addAction:searchAction];
            }
        }
        NSURLRequest *request = [self.webview request];
        if (request != nil) {
            if (![request.URL.absoluteString  isEqual: @""]) {
                [alertController addAction:reloadAction];
            }
            else {
                [alertController addAction:newurlAction];
            }
        }
        else {
            [alertController addAction:newurlAction];
        }
        
        [alertController addAction:cancelAction];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}
#pragma mark - Helper
-(void)toggleMode
{
    [self setCursorModeEnabled:!self.cursorMode];
}
- (void)showHintsAlert
{
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:@"Usage Guide"
                                          message:@"Double press the touch area to switch between cursor & scroll mode.\nPress the touch area while in cursor mode to click.\nSingle tap to Menu button to Go Back, or Exit on root page.\nSingle tap the Play/Pause button to: Go Forward, Enter URL or Reload Page.\nDouble tap the Play/Pause to show the Advanced Menu with more options.\nUse the tabs icon in the top bar to open the tab overview."
                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *hideForeverAction = [UIAlertAction
                                        actionWithTitle:@"Don't Show This Again"
                                        style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *action)
                                        {
                                            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DontShowHintsOnLaunch"];
                                            [[NSUserDefaults standardUserDefaults] synchronize];
                                        }];
    UIAlertAction *showForeverAction = [UIAlertAction
                                        actionWithTitle:@"Always Show On Launch"
                                        style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *action)
                                        {
                                            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DontShowHintsOnLaunch"];
                                            [[NSUserDefaults standardUserDefaults] synchronize];
                                        }];
    UIAlertAction *cancelAction = [UIAlertAction
                                   actionWithTitle:@"Dismiss"
                                   style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction *action)
                                   {
                                   }];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DontShowHintsOnLaunch"]) {
        [alertController addAction:showForeverAction];
    }
    else {
        [alertController addAction:hideForeverAction];
    }
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
    
    
}
- (void)alertTextFieldShouldReturn:(UITextField *)sender
{
    /*
     _inputViewVisible = NO;
     UIAlertController *alertController = (UIAlertController *)self.presentedViewController;
     if (alertController)
     {
     [alertController dismissViewControllerAnimated:true completion:nil];
     if ([temporaryURL containsString:@" "] || ![temporaryURL containsString:@"."]) {
     temporaryURL = [temporaryURL stringByReplacingOccurrencesOfString:@" " withString:@"+"];
     temporaryURL = [temporaryURL stringByReplacingOccurrencesOfString:@"." withString:@"+"];
     temporaryURL = [temporaryURL stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
     temporaryURL = [temporaryURL stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
     temporaryURL = [temporaryURL stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
     temporaryURL = [temporaryURL stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
     if (temporaryURL != nil) {
     [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/search?q=%@", temporaryURL]]]];
     }
     else {
     [self requestURLorSearchInput];
     }
     temporaryURL = nil;
     }
     else {
     if (temporaryURL != nil) {
     if ([temporaryURL containsString:@"http://"] || [temporaryURL containsString:@"https://"]) {
     [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", temporaryURL]]]];
     temporaryURL = nil;
     }
     else {
     [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@", temporaryURL]]]];
     temporaryURL = nil;
     }
     }
     else {
     [self requestURLorSearchInput];
     }
     }
     
     }
     */
}
#pragma mark - Remote Button
- (void)browserHandleSelectPressAction {
    if(!self.cursorMode)
    {
        return;
    }
    else
    {
        CGPoint point = [self.view convertPoint:self.cursorView.frame.origin toView:self.webview];
        
        if(point.y < 0)
        {
            point = [self.view convertPoint:self.cursorView.frame.origin toView:self.topMenuView];
            CGRect backBtnFrameExtra = [self.topMenuView interactiveFrameForView:self.topMenuView.backImageView];
            backBtnFrameExtra.origin.y = 0;
            backBtnFrameExtra.size.height = backBtnFrameExtra.size.height + 8.0;

            if(CGRectContainsPoint(backBtnFrameExtra, point))
            {
                [self.webview goBack];
            }
            else if(CGRectContainsPoint([self.topMenuView interactiveFrameForView:self.topMenuView.refreshImageView], point))
            {
                [self.webview reload];
            }
            else if(CGRectContainsPoint([self.topMenuView interactiveFrameForView:self.topMenuView.forwardImageView], point))
            {
                [self.webview goForward];
            }
            else if(CGRectContainsPoint([self.topMenuView interactiveFrameForView:self.topMenuView.homeImageView], point))
            {
                [self loadHomePage];
            }
            else if(CGRectContainsPoint([self.topMenuView interactiveFrameForView:self.topMenuView.tabsImageView], point))
            {
                [self showTabOverview];
            }
            else if(CGRectContainsPoint([self.topMenuView interactiveFrameForView:self.topMenuView.URLLabel], point))
            {
                [self showInputURLorSearchGoogle];
            }
            else if(CGRectContainsPoint([self.topMenuView interactiveFrameForView:self.topMenuView.fullscreenImageView], point))
            {
                if(self.topMenuShowing)
                    [self hideTopNav];
                else
                    [self showTopNav];
            }
            
            CGRect menuBtnFrameExtra = [self.topMenuView interactiveFrameForView:self.topMenuView.menuImageView];
            menuBtnFrameExtra.origin.y = 0;
            menuBtnFrameExtra.size.width = menuBtnFrameExtra.size.width + 100.0;
            menuBtnFrameExtra.size.height = menuBtnFrameExtra.size.height + 100.0;

            if(CGRectContainsPoint(menuBtnFrameExtra, point))
            {
                [self showAdvancedMenu];
            }
        }
        else
        {
            point = [self browserDOMPointForCursor];
            NSString *fieldType = [self evaluateResolvedElementJavaScriptAtPoint:point
                                                                            body:@"function browserEditableTargetAtPoint() {"
                                                                                 "var candidate = editableElement;"
                                                                                 "if (!candidate && resolvedElement && resolvedElement.matches) {"
                                                                                     "if (resolvedElement.matches(editableSelector) || resolvedElement.matches('textarea, select')) {"
                                                                                         "candidate = resolvedElement;"
                                                                                     "}"
                                                                                 "}"
                                                                                 "if (!candidate) { return null; }"
                                                                                 "window.__browserLastEditableElement = candidate;"
                                                                                 "return candidate;"
                                                                                 "}"
                                                                                 "var target = browserEditableTargetAtPoint();"
                                                                                 "if (!target) { return ''; }"
                                                                                 "var tagName = target.tagName ? target.tagName.toLowerCase() : '';"
                                                                                 "var type = (target.type || '').toLowerCase();"
                                                                                 "if (tagName === 'textarea' || target.isContentEditable) { return 'text'; }"
                                                                                 "if (tagName === 'input' && !type) { return 'text'; }"
                                                                                 "return type;"];
            [self evaluateResolvedElementJavaScriptAtPoint:point
                                                      body:@"var target = editableElement || interactiveElement || resolvedElement;"
                                                           "if (!target) { return 'false'; }"
                                                           "try { if (target.focus) { target.focus(); } } catch (error) {}"
                                                           "function dispatchPointerLikeEvent(type, constructorName) {"
                                                               "try {"
                                                                   "var Constructor = window[constructorName];"
                                                                   "if (Constructor) {"
                                                                       "var event = new Constructor(type, { bubbles: true, cancelable: true, composed: true, view: window, clientX: x, clientY: y, screenX: x, screenY: y, button: 0, buttons: 1, pointerType: 'mouse' });"
                                                                       "return target.dispatchEvent(event);"
                                                                   "}"
                                                               "} catch (error) {}"
                                                               "var mouseEvent = document.createEvent('MouseEvents');"
                                                               "mouseEvent.initMouseEvent(type, true, true, window, 1, x, y, x, y, false, false, false, false, 0, null);"
                                                               "return target.dispatchEvent(mouseEvent);"
                                                           "}"
                                                           "dispatchPointerLikeEvent('pointerdown', 'PointerEvent');"
                                                           "dispatchPointerLikeEvent('mousedown', 'MouseEvent');"
                                                           "dispatchPointerLikeEvent('pointerup', 'PointerEvent');"
                                                           "dispatchPointerLikeEvent('mouseup', 'MouseEvent');"
                                                           "if (typeof target.click === 'function') { target.click(); }"
                                                           "else { dispatchPointerLikeEvent('click', 'MouseEvent'); }"
                                                           "return 'true';"];
            fieldType = fieldType.lowercaseString;
            if ([fieldType isEqualToString:@"date"] || [fieldType isEqualToString:@"datetime"] || [fieldType isEqualToString:@"datetime-local"] || [fieldType isEqualToString:@"email"] || [fieldType isEqualToString:@"month"] || [fieldType isEqualToString:@"number"] || [fieldType isEqualToString:@"password"] || [fieldType isEqualToString:@"search"] || [fieldType isEqualToString:@"tel"] || [fieldType isEqualToString:@"text"] || [fieldType isEqualToString:@"time"] || [fieldType isEqualToString:@"url"] || [fieldType isEqualToString:@"week"]) {
                NSString *fieldTitle = [self evaluateEditableElementJavaScriptAtPoint:point
                                                                                 body:@"var target = browserEditableTarget();"
                                                                                      "if (!target) { return ''; }"
                                                                                      "return target.title || target.getAttribute('aria-label') || target.name || target.placeholder || '';"];
                if ([fieldTitle isEqualToString:@""]) {
                    fieldTitle = fieldType;
                }
                NSString *placeholder = [self evaluateEditableElementJavaScriptAtPoint:point
                                                                                  body:@"var target = browserEditableTarget();"
                                                                                       "if (!target) { return ''; }"
                                                                                       "return target.placeholder || target.getAttribute('aria-label') || '';"];
                if ([placeholder isEqualToString:@""]) {
                    if (![fieldTitle isEqualToString:fieldType]) {
                        placeholder = [NSString stringWithFormat:@"%@ Input", fieldTitle];
                    }
                    else {
                        placeholder = @"Text Input";
                    }
                }
                NSString *testedFormResponse = [self evaluateEditableElementJavaScriptAtPoint:point
                                                                                        body:@"var target = browserEditableTarget();"
                                                                                             "return (target && target.form && target.form.hasAttribute('onsubmit')) ? 'true' : 'false';"];
                UIAlertController *alertController = [UIAlertController
                                                      alertControllerWithTitle:@"Input Text"
                                                      message: [fieldTitle capitalizedString]
                                                      preferredStyle:UIAlertControllerStyleAlert];
                
                [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField)
                 {
                     if ([fieldType isEqualToString:@"url"]) {
                         textField.keyboardType = UIKeyboardTypeURL;
                     }
                     else if ([fieldType isEqualToString:@"email"]) {
                         textField.keyboardType = UIKeyboardTypeEmailAddress;
                     }
                     else if ([fieldType isEqualToString:@"tel"] || [fieldType isEqualToString:@"number"] || [fieldType isEqualToString:@"date"] || [fieldType isEqualToString:@"datetime"] || [fieldType isEqualToString:@"datetime-local"]) {
                         textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
                     }
                     else {
                         textField.keyboardType = UIKeyboardTypeDefault;
                     }
                     textField.placeholder = [placeholder capitalizedString];
                     if ([fieldType isEqualToString:@"password"]) {
                         textField.secureTextEntry = YES;
                     }
                     textField.text = [self evaluateEditableElementJavaScriptAtPoint:point
                                                                                body:@"var target = browserEditableTarget();"
                                                                                     "if (!target) { return ''; }"
                                                                                     "if (typeof target.value !== 'undefined') { return target.value; }"
                                                                                     "return target.textContent || '';"];
                     textField.textColor = kTextColor();
                     [textField setReturnKeyType:UIReturnKeyDone];
                     [textField addTarget:self
                                   action:@selector(alertTextFieldShouldReturn:)
                         forControlEvents:UIControlEventEditingDidEnd];
                 }];
                UIAlertAction *inputAndSubmitAction = [UIAlertAction
                                                       actionWithTitle:@"Submit"
                                                       style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action)
                                                       {
                                                           UITextField *inputViewTextField = alertController.textFields[0];
                                                           NSString *escapedText = [self javaScriptEscapedString:inputViewTextField.text];
                                                           [self evaluateEditableElementJavaScriptAtPoint:point
                                                                                                    body:[NSString stringWithFormat:@"var target = browserEditableTarget();"
                                                                                                          "if (!target) { return 'false'; }"
                                                                                                          "if (typeof target.value !== 'undefined') { target.value = '%@'; }"
                                                                                                          "else { target.textContent = '%@'; }"
                                                                                                          "if (target.dispatchEvent) {"
                                                                                                              "target.dispatchEvent(new Event('input', { bubbles: true }));"
                                                                                                              "target.dispatchEvent(new Event('change', { bubbles: true }));"
                                                                                                          "}"
                                                                                                          "if (target.form) { target.form.submit(); }"
                                                                                                          "return 'true';", escapedText, escapedText]];
                                                       }];
                UIAlertAction *inputAction = [UIAlertAction
                                              actionWithTitle:@"Done"
                                              style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action)
                                              {
                                                  UITextField *inputViewTextField = alertController.textFields[0];
                                                  NSString *escapedText = [self javaScriptEscapedString:inputViewTextField.text];
                                                  [self evaluateEditableElementJavaScriptAtPoint:point
                                                                                           body:[NSString stringWithFormat:@"var target = browserEditableTarget();"
                                                                                                 "if (!target) { return 'false'; }"
                                                                                                 "if (typeof target.value !== 'undefined') { target.value = '%@'; }"
                                                                                                 "else { target.textContent = '%@'; }"
                                                                                                 "if (target.dispatchEvent) {"
                                                                                                     "target.dispatchEvent(new Event('input', { bubbles: true }));"
                                                                                                     "target.dispatchEvent(new Event('change', { bubbles: true }));"
                                                                                                 "}"
                                                                                                 "return 'true';", escapedText, escapedText]];
                                              }];
                UIAlertAction *cancelAction = [UIAlertAction
                                               actionWithTitle:nil
                                               style:UIAlertActionStyleCancel
                                               handler:nil];
                [alertController addAction:inputAction];
                if (testedFormResponse != nil) {
                    if ([testedFormResponse isEqualToString:@"true"]) {
                        [alertController addAction:inputAndSubmitAction];
                    }
                }
                [alertController addAction:cancelAction];
                [self presentViewController:alertController animated:YES completion:nil];
                UITextField *inputViewTextField = alertController.textFields[0];
                if ([[inputViewTextField.text stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString:@""]) {
                    [inputViewTextField becomeFirstResponder];
                }
            }
        }
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    [super pressesBegan:presses withEvent:event];
}

-(void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    UIPress *press = presses.anyObject;
    if (press == nil) {
        return;
    }

    if (press.type == UIPressTypeSelect) {
        self.lastDirectSelectPressTimestamp = CACurrentMediaTime();
        [self handleSelectPressEndedWithSource:@"direct"];
        return;
    }
    
    if (self.tabOverviewVisible) {
        if (press.type == UIPressTypeMenu || press.type == UIPressTypePlayPause) {
            [self dismissTabOverview];
            return;
        }
        if (press.type == UIPressTypeSelect) {
            [self handleTabOverviewSelectionAtPoint:self.cursorView.frame.origin];
            return;
        }
    }
    
    if (press.type == UIPressTypeMenu)
    {
        UIAlertController *alertController = (UIAlertController *)self.presentedViewController;
        if (alertController)
        {
            [self.presentedViewController dismissViewControllerAnimated:true completion:nil];
        }
        else if ([self.webview canGoBack]) {
            [self.webview goBack];
        }
        else
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Exit App?" message:nil preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Exit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                exit(EXIT_SUCCESS);
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        /*
        else {
            [self requestURLorSearchInput];
        }*/
        
    }
    else if (press.type == UIPressTypeUpArrow)
    {
        // Zoom testing (needs work) (requires old remote for up arrow)
        //UIScrollView * sv = self.webview.scrollView;
        //[sv setZoomScale:30];
    }
    else if (press.type == UIPressTypeDownArrow)
    {
    }
    else if (press.type == UIPressTypePlayPause)
    {
        UIAlertController *alertController = (UIAlertController *)self.presentedViewController;
        if (alertController)
        {
            [self.presentedViewController dismissViewControllerAnimated:true completion:nil];
        }
        else {
            [self requestURLorSearchInput];
        }
    }
}

#pragma mark - Cursor Input

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!self.cursorMode && !self.tabOverviewVisible) {
        [super touchesBegan:touches withEvent:event];
        return;
    }

    self.lastTouchLocation = CGPointMake(-1, -1);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!self.cursorMode && !self.tabOverviewVisible) {
        [super touchesMoved:touches withEvent:event];
        return;
    }

    for (UITouch *touch in touches)
    {
        CGPoint location = [touch locationInView:self.webview];
        
        if(self.lastTouchLocation.x == -1 && self.lastTouchLocation.y == -1)
        {
            // Prevent cursor from recentering
            self.lastTouchLocation = location;
        }
        else
        {
            CGFloat xDiff = location.x - self.lastTouchLocation.x;
            CGFloat yDiff = location.y - self.lastTouchLocation.y;
            CGRect rect = self.cursorView.frame;
            
            if(rect.origin.x + xDiff >= 0 && rect.origin.x + xDiff <= 1920)
                rect.origin.x += xDiff;//location.x - self.startPos.x;//+= xDiff; //location.x;
            
            if(rect.origin.y + yDiff >= 0 && rect.origin.y + yDiff <= 1080)
                rect.origin.y += yDiff;//location.y - self.startPos.y;//+= yDiff; //location.y;
            
            self.cursorView.frame = rect;
            self.lastTouchLocation = location;
        }
        
        // Try to make mouse cursor become pointer icon when pointer element is clickable
        self.cursorView.image = kDefaultCursor();
        if (self.tabOverviewVisible) {
            if ([self tabOverviewContainsPoint:self.cursorView.frame.origin]) {
                self.cursorView.image = kPointerCursor();
            }
            break;
        }
        if ([self.webview request] == nil) {
            return;
        }
        if (self.cursorMode) {
            CGPoint point = [self browserDOMPointForCursor];
            if(point.y < 0) {
                return;
            }

            NSString *containsLink = [self evaluateHoverStateJavaScriptAtPoint:point];
            if ([containsLink isEqualToString:@"true"]) {
                self.cursorView.image = kPointerCursor();
            }
        }
        
        // We only use one touch, break the loop
        break;
    }
    
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    self.lastTouchLocation = CGPointMake(-1, -1);
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    self.lastTouchLocation = CGPointMake(-1, -1);
    [super touchesCancelled:touches withEvent:event];
}



@end
