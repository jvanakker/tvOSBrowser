#import "BrowserMenuPresenter.h"

static UIColor *MenuTextColor(void) {
    if (@available(tvOS 13, *)) {
        return UIColor.labelColor;
    } else {
        return UIColor.blackColor;
    }
}

@interface BrowserMenuPresenter ()

@property (nonatomic, weak) id<BrowserMenuPresenterHost> host;

@end

@implementation BrowserMenuPresenter

- (instancetype)initWithHost:(id<BrowserMenuPresenterHost>)host {
    self = [super init];
    if (self) {
        _host = host;
    }
    return self;
}

- (void)showAdvancedMenu {
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Advanced Menu" message:@""];
    for (UIAlertAction *action in [self advancedMenuActions]) {
        [alertController addAction:action];
    }
    [self.host browserPresentViewController:alertController];
}

- (UIAlertController *)browserAlertControllerWithTitle:(NSString *)title message:(NSString *)message {
    return [UIAlertController alertControllerWithTitle:title
                                               message:message
                                        preferredStyle:UIAlertControllerStyleAlert];
}

- (UIAlertAction *)browserActionWithTitle:(NSString *)title
                                    style:(UIAlertActionStyle)style
                                  handler:(void (^ __nullable)(UIAlertAction *action))handler {
    return [UIAlertAction actionWithTitle:title style:style handler:handler];
}

- (UIAlertAction *)browserCancelAction {
    return [self browserActionWithTitle:nil style:UIAlertActionStyleCancel handler:nil];
}

- (BOOL)stringHasVisibleContent:(NSString *)string {
    NSString *trimmedString = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmedString.length > 0;
}

- (NSString *)displayTitleForStoredTitle:(NSString *)storedTitle
                               URLString:(NSString *)URLString
                              includeURL:(BOOL)includeURL {
    NSString *displayTitle = [self stringHasVisibleContent:storedTitle] ? storedTitle : URLString;
    if (includeURL && [self stringHasVisibleContent:storedTitle] && [self stringHasVisibleContent:URLString]) {
        return [NSString stringWithFormat:@"%@ - %@", storedTitle, URLString];
    }
    return displayTitle ?: @"";
}

- (void)loadStoredURLString:(NSString *)URLString {
    if (![self stringHasVisibleContent:URLString]) {
        return;
    }
    [[self.host browserWebView] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:URLString]]];
}

- (void)saveFavoritesArray:(NSArray *)favorites {
    [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"FAVORITES"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)presentDeleteFavoriteMenu {
    NSArray *favorites = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"];
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Delete a Favorite"
                                                                       message:@"Select a Favorite to Delete"];
    __weak typeof(self) weakSelf = self;
    
    [favorites enumerateObjectsUsingBlock:^(NSArray *entry, NSUInteger index, BOOL *stop) {
        NSString *URLString = entry.count > 0 ? entry[0] : @"";
        NSString *title = entry.count > 1 ? entry[1] : @"";
        if (![weakSelf stringHasVisibleContent:URLString]) {
            return;
        }
        
        NSString *displayTitle = [weakSelf displayTitleForStoredTitle:title URLString:URLString includeURL:NO];
        [alertController addAction:[weakSelf browserActionWithTitle:displayTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(__unused UIAlertAction *action) {
            NSMutableArray *updatedFavorites = [favorites mutableCopy];
            [updatedFavorites removeObjectAtIndex:index];
            [weakSelf saveFavoritesArray:updatedFavorites];
        }]];
    }];
    
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)presentAddFavoritePrompt {
    NSString *pageTitle = [[self.host browserWebView] stringByEvaluatingJavaScriptFromString:@"document.title"];
    NSURLRequest *request = [[self.host browserWebView] request];
    NSString *currentURL = request.URL.absoluteString ?: @"";
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Name New Favorite"
                                                                       message:currentURL];
    __weak typeof(self) weakSelf = self;
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.placeholder = @"Name New Favorite";
        textField.text = pageTitle;
        textField.textColor = MenuTextColor();
        [textField setReturnKeyType:UIReturnKeyDone];
    }];
    
    [alertController addAction:[self browserActionWithTitle:@"Save"
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(__unused UIAlertAction *action) {
        UITextField *titleTextField = alertController.textFields.firstObject;
        NSString *savedTitle = titleTextField.text;
        if (![weakSelf stringHasVisibleContent:savedTitle]) {
            savedTitle = currentURL;
        }
        
        NSArray *favoriteEntry = @[currentURL, savedTitle ?: @""];
        NSMutableArray *favorites = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"] mutableCopy];
        if (favorites == nil) {
            favorites = [NSMutableArray array];
        }
        [favorites addObject:favoriteEntry];
        [weakSelf saveFavoritesArray:favorites];
    }]];
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)presentFavoritesMenu {
    NSArray *favorites = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"];
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Favorites" message:@""];
    __weak typeof(self) weakSelf = self;
    
    [favorites enumerateObjectsUsingBlock:^(NSArray *entry, NSUInteger index, BOOL *stop) {
        NSString *URLString = entry.count > 0 ? entry[0] : @"";
        NSString *title = entry.count > 1 ? entry[1] : @"";
        NSString *displayTitle = [weakSelf displayTitleForStoredTitle:title URLString:URLString includeURL:NO];
        if (![weakSelf stringHasVisibleContent:displayTitle]) {
            return;
        }
        
        [alertController addAction:[weakSelf browserActionWithTitle:displayTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(__unused UIAlertAction *action) {
            [weakSelf loadStoredURLString:URLString];
        }]];
    }];
    
    if (favorites.count > 0) {
        [alertController addAction:[self browserActionWithTitle:@"Delete a Favorite"
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(__unused UIAlertAction *action) {
            [weakSelf presentDeleteFavoriteMenu];
        }]];
    }
    
    [alertController addAction:[self browserActionWithTitle:@"Add Current Page to Favorites"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction *action) {
        [weakSelf presentAddFavoritePrompt];
    }]];
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)presentHistoryMenu {
    NSArray *historyEntries = [[NSUserDefaults standardUserDefaults] arrayForKey:@"HISTORY"];
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"History" message:@""];
    __weak typeof(self) weakSelf = self;
    
    if (historyEntries.count > 0) {
        [alertController addAction:[self browserActionWithTitle:@"Clear History"
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(__unused UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"HISTORY"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }]];
    }
    
    [historyEntries enumerateObjectsUsingBlock:^(NSArray *entry, NSUInteger index, BOOL *stop) {
        NSString *URLString = entry.count > 0 ? entry[0] : @"";
        NSString *title = entry.count > 1 ? entry[1] : @"";
        NSString *displayTitle = [weakSelf displayTitleForStoredTitle:title URLString:URLString includeURL:YES];
        if (![weakSelf stringHasVisibleContent:displayTitle]) {
            return;
        }
        
        [alertController addAction:[weakSelf browserActionWithTitle:displayTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(__unused UIAlertAction *action) {
            [weakSelf loadStoredURLString:URLString];
        }]];
    }];
    
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)applyUserAgent:(NSString *)userAgent mobileMode:(BOOL)mobileMode {
    NSDictionary *userAgentDefaults = @{ @"UserAgent": userAgent };
    [[NSUserDefaults standardUserDefaults] registerDefaults:userAgentDefaults];
    [[NSUserDefaults standardUserDefaults] setBool:mobileMode forKey:@"MobileMode"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSURLRequest *request = [[self.host browserWebView] request];
    if (request != nil && [self stringHasVisibleContent:request.URL.absoluteString]) {
        [self.host browserCaptureSnapshotForCurrentTab];
    }
    
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies]) {
        [storage deleteCookie:cookie];
    }
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    __weak typeof(self) weakSelf = self;
    [[NSURLSession sharedSession] resetWithCompletionHandler:^{
        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.host browserRecreateActiveWebViewPreservingCurrentURL];
            [weakSelf.host browserBringCursorToFront];
        });
    }];
}

- (void)setPageScalingEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"ScalePagesToFit"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[self.host browserWebView] setScalesPageToFit:enabled];
    if (enabled) {
        [[self.host browserWebView] setContentMode:UIViewContentModeScaleAspectFit];
    }
    [[self.host browserWebView] reload];
}

- (void)clearCacheAndReload {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.host.browserPreviousURL = @"";
    [[self.host browserWebView] reload];
}

- (void)clearCookiesAndReload {
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies]) {
        [storage deleteCookie:cookie];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.host.browserPreviousURL = @"";
    [[self.host browserWebView] reload];
}

- (UIAlertAction *)topNavigationVisibilityAction {
    NSString *title = self.host.browserTopMenuShowing ? @"Hide Top Navigation bar" : @"Show Top Navigation bar";
    return [self browserActionWithTitle:title
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        if (self.host.browserTopMenuShowing) {
            [self.host browserHideTopNav];
        } else {
            [self.host browserShowTopNav];
        }
    }];
}

- (UIAlertAction *)homePageAction {
    return [self browserActionWithTitle:@"Go To Home Page"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self.host browserLoadHomePage];
    }];
}

- (UIAlertAction *)setCurrentPageAsHomePageAction {
    return [self browserActionWithTitle:@"Set Current Page As Home Page"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        NSURLRequest *request = [[self.host browserWebView] request];
        if (request != nil && [self stringHasVisibleContent:request.URL.absoluteString]) {
            [[NSUserDefaults standardUserDefaults] setObject:request.URL.absoluteString forKey:@"homepage"];
        }
    }];
}

- (UIAlertAction *)usageGuideAction {
    return [self browserActionWithTitle:@"Usage Guide"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self.host browserShowHints];
    }];
}

- (UIAlertAction *)showTabsAction {
    return [self browserActionWithTitle:@"Show Tabs"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self.host browserShowTabOverview];
    }];
}

- (UIAlertAction *)newTabMenuAction {
    return [self browserActionWithTitle:@"Open New Tab"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self.host browserCreateNewTabLoadingHomePage:YES];
    }];
}

- (UIAlertAction *)favoritesMenuAction {
    return [self browserActionWithTitle:@"Favorites"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self presentFavoritesMenu];
    }];
}

- (UIAlertAction *)historyMenuAction {
    return [self browserActionWithTitle:@"History"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self presentHistoryMenu];
    }];
}

- (UIAlertAction *)userAgentModeAction {
    BOOL mobileModeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"MobileMode"];
    NSString *title = mobileModeEnabled ? @"Switch To Desktop Mode" : @"Switch To Mobile Mode";
    NSString *userAgent = mobileModeEnabled
        ? @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0 Safari/605.1.15"
        : @"Mozilla/5.0 (iPad; CPU OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0 Mobile/15E148 Safari/604.1";
    BOOL mobileMode = !mobileModeEnabled;
    
    return [self browserActionWithTitle:title
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self applyUserAgent:userAgent mobileMode:mobileMode];
    }];
}

- (UIAlertAction *)pageScalingAction {
    BOOL scalesPageToFit = [[self.host browserWebView] scalesPageToFit];
    NSString *title = scalesPageToFit ? @"Stop Scaling Pages to Fit" : @"Scale Pages to Fit";
    return [self browserActionWithTitle:title
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        [self setPageScalingEnabled:!scalesPageToFit];
    }];
}

- (NSArray<UIAlertAction *> *)advancedMenuActions {
    return @[
        [self favoritesMenuAction],
        [self historyMenuAction],
        [self showTabsAction],
        [self newTabMenuAction],
        [self homePageAction],
        [self setCurrentPageAsHomePageAction],
        [self userAgentModeAction],
        [self topNavigationVisibilityAction],
        [self pageScalingAction],
        [self browserActionWithTitle:@"Increase Font Size"
                               style:UIAlertActionStyleDefault
                             handler:^(__unused UIAlertAction *action) {
            self.host.browserTextFontSize += 5;
            [self.host browserUpdateTextFontSize];
        }],
        [self browserActionWithTitle:@"Decrease Font Size"
                               style:UIAlertActionStyleDefault
                             handler:^(__unused UIAlertAction *action) {
            self.host.browserTextFontSize -= 5;
            [self.host browserUpdateTextFontSize];
        }],
        [self browserActionWithTitle:@"Clear Cache"
                               style:UIAlertActionStyleDestructive
                             handler:^(__unused UIAlertAction *action) {
            [self clearCacheAndReload];
        }],
        [self browserActionWithTitle:@"Clear Cookies"
                               style:UIAlertActionStyleDestructive
                             handler:^(__unused UIAlertAction *action) {
            [self clearCookiesAndReload];
        }],
        [self usageGuideAction],
        [self browserCancelAction]
    ];
}

@end
