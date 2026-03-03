//
//  ViewController.m
//  Browser
//
//  Created by Steven Troughton-Smith on 20/09/2015.
//  Improved by Jip van Akker on 14/10/2015 through 10/01/2019
//

// Icons made by https://www.flaticon.com/authors/daniel-bruce Daniel Bruce from https://www.flaticon.com/ Flaticon" is licensed by  http://creativecommons.org/licenses/by/3.0/  CC 3.0 BY


#import "BrowserMenuPresenter.h"
#import "BrowserSessionStore.h"
#import "ViewController.h"
#import "BrowserNavigationService.h"
#import "BrowserTabViewModel.h"
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

@interface ViewController () <BrowserMenuPresenterHost>

@property id webview;
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
@property UITapGestureRecognizer *touchSurfaceDoubleTapRecognizer;
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

@end

@implementation ViewController

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

- (id)browserWebView {
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

- (id)createConfiguredWebView {
    if (@available(tvOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }
    
    id webView = [[NSClassFromString(@"UIWebView") alloc] init];
    [webView setTranslatesAutoresizingMaskIntoConstraints:false];
    [webView setClipsToBounds:false];
    [webView setDelegate:self];
    [webView setLayoutMargins:UIEdgeInsetsZero];
    
    UIScrollView *scrollView = [webView scrollView];
    [scrollView setLayoutMargins:UIEdgeInsetsZero];
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scrollView.contentOffset = CGPointZero;
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.clipsToBounds = NO;
    scrollView.bounces = self.scrollViewAllowBounces;
    scrollView.panGestureRecognizer.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
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
        self.lblUrlBar.text = @"";
        return;
    }
    
    NSURLRequest *request = [self.webview request];
    NSString *currentURL = tab.URLString.length > 0 ? tab.URLString : request.URL.absoluteString;
    self.lblUrlBar.text = currentURL.length > 0 ? currentURL : @"New Tab";
    
    if (request != nil) {
        [self updateTextFontSize];
    }
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
    
    [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:URLString]]];
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
    [self.loadingSpinner stopAnimating];
    [self.browserContainerView addSubview:self.webview];
    [self updateTopNavAndWebView];
    
    UIScrollView *scrollView = [self.webview scrollView];
    scrollView.frame = self.view.bounds;
    [scrollView setNeedsLayout];
    [scrollView layoutIfNeeded];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    scrollView.bounces = self.scrollViewAllowBounces;
    scrollView.scrollEnabled = !self.cursorMode && !self.tabOverviewVisible;
    [self.webview setUserInteractionEnabled:!self.cursorMode && !self.tabOverviewVisible];
    
    [self refreshActiveTabUI];
}

- (void)setCursorModeEnabled:(BOOL)cursorMode {
    self.cursorMode = cursorMode;
    UIScrollView *scrollView = [self.webview scrollView];
    BOOL shouldAllowWebInteraction = !cursorMode && !self.tabOverviewVisible;
    scrollView.scrollEnabled = shouldAllowWebInteraction;
    [self.webview setUserInteractionEnabled:shouldAllowWebInteraction];
    self.cursorView.hidden = self.tabOverviewVisible ? NO : !cursorMode;
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
        [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:currentURL]]];
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
        [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"]]]];
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

    self.touchSurfaceDoubleTapRecognizer = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handleTouchSurfaceDoubleTap:)];
    self.touchSurfaceDoubleTapRecognizer.numberOfTapsRequired = 2;
    self.touchSurfaceDoubleTapRecognizer.allowedPressTypes = @[[NSNumber numberWithInteger:UIPressTypeSelect]];
    [self.view addGestureRecognizer:self.touchSurfaceDoubleTapRecognizer];
    
    self.playPauseDoubleTapRecognizer = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handlePlayPauseDoubleTap:)];
    self.playPauseDoubleTapRecognizer.numberOfTapsRequired = 2;
    self.playPauseDoubleTapRecognizer.allowedPressTypes = @[[NSNumber numberWithInteger:UIPressTypePlayPause]];

    [self.view addGestureRecognizer:self.playPauseDoubleTapRecognizer];
    
    self.cursorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
    self.cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    self.cursorView.image = kDefaultCursor();
    [self.view addSubview:self.cursorView];
    
    
    
    // Spinner now also in Storyboard.
    /*loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    loadingSpinner.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    loadingSpinner.tintColor = [UIColor blackColor];*/
    
    self.loadingSpinner.hidesWhenStopped = true;
    
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%lu%%'",
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
    
    UILabel *addTabLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetWidth(self.tabOverviewPanelView.bounds) - 178.0, 98.0, 180.0, 28.0)];
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
        [self.loadingSpinner startAnimating];
    }
    tab.previousURL = tab.requestURL;
}
-(void) webViewDidFinishLoad:(id)webView {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return;
    }
    
    if (tab == [self activeTab]) {
        [self.loadingSpinner stopAnimating];
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
    
    if (tab == [self activeTab]) {
        [self.loadingSpinner stopAnimating];
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
-(void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    UIPress *press = presses.anyObject;
    if (press == nil) {
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
    
    
    else if (press.type == UIPressTypeSelect) // Handle the normal single Touchpad press with our virtual cursor
    {
        if(!self.cursorMode)
        {
            //[self toggleMode]; // This is now done in Double-tap
        }
        else
        {
            // Handle the virtual cursor
            
            

            CGPoint point = [self.view convertPoint:self.cursorView.frame.origin toView:self.webview];
            
            if(point.y < 0)
            {
                // Handle menu buttons press
                point = [self.view convertPoint:self.cursorView.frame.origin toView:self.topMenuView];
                CGRect backBtnFrameExtra = self.btnImageBack.frame;
                backBtnFrameExtra.origin.y = 0; // Enable cursor in upper right corner
                backBtnFrameExtra.size.height = backBtnFrameExtra.size.height+ 8;// Enable cursor in upper right corner

                
                if(CGRectContainsPoint(backBtnFrameExtra, point))
                {
                    [self.webview goBack];
                }
                else if(CGRectContainsPoint(self.btnImageRefresh.frame, point))
                {
                    [self.webview reload];
                }
                else if(CGRectContainsPoint(self.btnImageForward.frame, point))
                {
                    [self.webview goForward];
                }
                else if(CGRectContainsPoint(self.btnImageHome.frame, point))
                {
                    [self loadHomePage];
                }
                else if(CGRectContainsPoint(self.btnImageTabs.frame, point))
                {
                    [self showTabOverview];
                }
                else if(CGRectContainsPoint(self.lblUrlBar.frame, point))
                {
                    [self showInputURLorSearchGoogle];
                }

                
                else if(CGRectContainsPoint(self.btnImageFullScreen.frame, point))
                {
                    // Hide/show top bar:
                    
                    if(self.topMenuShowing)
                        [self hideTopNav];
                    else
                        [self showTopNav];
                }
                
                CGRect menuBtnFrameExtra = self.btnImgMenu.frame;
                menuBtnFrameExtra.origin.y = 0; // Enable cursor in upper right corner
                menuBtnFrameExtra.size.width = menuBtnFrameExtra.size.width + 100; // Enable cursor in upper right corner
                menuBtnFrameExtra.size.height = menuBtnFrameExtra.size.height+ 100;// Enable cursor in upper right corner

                if(CGRectContainsPoint(menuBtnFrameExtra, point))
                {
                    // Show advanced menu:
                    [self showAdvancedMenu];
                }
                
               

                    
            }
            else // Handle Press in the Browser view
            {
            
            int displayWidth = [[self.webview stringByEvaluatingJavaScriptFromString:@"window.innerWidth"] intValue];
            CGFloat scale = [self.webview frame].size.width / displayWidth;
            
            point.x /= scale;
            point.y /= scale;

            [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).click()", (int)point.x, (int)point.y]];
            // Make the UIWebView method call
            NSString *fieldType = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).type;", (int)point.x, (int)point.y]];
            /*
             if (fieldType == nil) {
             NSString *contentEditible = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).getAttribute('contenteditable');", (int)point.x, (int)point.y]];
             NSLog(contentEditible);
             if ([contentEditible isEqualToString:@"true"]) {
             fieldType = @"text";
             }
             }
             else if ([[fieldType stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString: @""]) {
             NSString *contentEditible = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).getAttribute('contenteditable');", (int)point.x, (int)point.y]];
             NSLog(contentEditible);
             if ([contentEditible isEqualToString:@"true"]) {
             fieldType = @"text";
             }
             }
             NSLog(fieldType);
             */
            fieldType = fieldType.lowercaseString;
            if ([fieldType isEqualToString:@"date"] || [fieldType isEqualToString:@"datetime"] || [fieldType isEqualToString:@"datetime-local"] || [fieldType isEqualToString:@"email"] || [fieldType isEqualToString:@"month"] || [fieldType isEqualToString:@"number"] || [fieldType isEqualToString:@"password"] || [fieldType isEqualToString:@"search"] || [fieldType isEqualToString:@"tel"] || [fieldType isEqualToString:@"text"] || [fieldType isEqualToString:@"time"] || [fieldType isEqualToString:@"url"] || [fieldType isEqualToString:@"week"]) {
                NSString *fieldTitle = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).title;", (int)point.x, (int)point.y]];
                if ([fieldTitle isEqualToString:@""]) {
                    fieldTitle = fieldType;
                }
                NSString *placeholder = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).placeholder;", (int)point.x, (int)point.y]];
                if ([placeholder isEqualToString:@""]) {
                    if (![fieldTitle isEqualToString:fieldType]) {
                        placeholder = [NSString stringWithFormat:@"%@ Input", fieldTitle];
                    }
                    else {
                        placeholder = @"Text Input";
                    }
                }
                NSString *testedFormResponse = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).form.hasAttribute('onsubmit');", (int)point.x, (int)point.y]];
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
                     textField.text = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).value;", (int)point.x, (int)point.y]];
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
                                                           NSString *javaScript = [NSString stringWithFormat:@"var textField = document.elementFromPoint(%i, %i);"
                                                                                   "textField.value = '%@';"
                                                                                   "textField.form.submit();"
                                                                                   //"var ev = document.createEvent('KeyboardEvent');"
                                                                                   //"ev.initKeyEvent('keydown', true, true, window, false, false, false, false, 13, 0);"
                                                                                   //"document.body.dispatchEvent(ev);"
                                                                                   , (int)point.x, (int)point.y, inputViewTextField.text];
                                                           [self.webview stringByEvaluatingJavaScriptFromString:javaScript];
                                                       }];
                UIAlertAction *inputAction = [UIAlertAction
                                              actionWithTitle:@"Done"
                                              style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action)
                                              {
                                                  UITextField *inputViewTextField = alertController.textFields[0];
                                                  NSString *javaScript = [NSString stringWithFormat:@"var textField = document.elementFromPoint(%i, %i);"
                                                                          "textField.value = '%@';", (int)point.x, (int)point.y, inputViewTextField.text];
                                                  [self.webview stringByEvaluatingJavaScriptFromString:javaScript];
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
            else {
                //[self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).click()", (int)point.x, (int)point.y]];
            }
            //[self toggleMode];
                
            }
        }
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
    self.lastTouchLocation = CGPointMake(-1, -1);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
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
            CGPoint point = [self.view convertPoint:self.cursorView.frame.origin toView:self.webview];
            if(point.y < 0) {
                return;
            }
            
            int displayWidth = [[self.webview stringByEvaluatingJavaScriptFromString:@"window.innerWidth"] intValue];
            CGFloat scale = [self.webview frame].size.width / displayWidth;
            
            point.x /= scale;
            point.y /= scale;
            
            // Seems not so low, check everytime when touchesMoved
            NSString *containsLink = [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.elementFromPoint(%i, %i).closest('a, input') !== null", (int)point.x, (int)point.y]];
            if ([containsLink isEqualToString:@"true"]) {
                self.cursorView.image = kPointerCursor();
            }
        }
        
        // We only use one touch, break the loop
        break;
    }
    
}



@end
