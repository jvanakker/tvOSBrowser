//
//  ViewController.m
//  Browser
//
//  Created by Steven Troughton-Smith on 20/09/2015.
//  Improved by Jip van Akker on 14/10/2015 through 10/01/2019
//

// Icons made by https://www.flaticon.com/authors/daniel-bruce Daniel Bruce from https://www.flaticon.com/ Flaticon" is licensed by  http://creativecommons.org/licenses/by/3.0/  CC 3.0 BY


#import "ViewController.h"

#pragma mark - UI

static UIColor *kTextColor() {
    if (@available(tvOS 13, *)) {
        return UIColor.labelColor;
    } else {
        return UIColor.blackColor;
    }
}

static UIImage *kDefaultCursor() {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Cursor"];
    });
    return image;
}

static UIImage *kPointerCursor() {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Pointer"];
    });
    return image;
}

@interface ViewController ()

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

@end

@implementation ViewController
@synthesize textFontSize = _textFontSize;
-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    //loadingSpinner.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    [self webViewDidAppear];
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"FAVORITES"] == nil) {
        NSArray *defaultFavs = @[
            // Format: @[ url, title ]
            @[@"https://tel.yandex.by/video/search?channelId=dmsuY29tO3B1YmxpYzIyOTU3ODU0Ng%3D%3D&how=tm&text=Фильмы", @"Yandex Video Search (Тел)"],
            @[@"https://w140.zona.plus/movies/", @"zona.plus movies"],
            @[@"https://rt.mk24.life/movies/", @"rt.mk24.life movies"],
            @[@"https://kinogo-films.org", @"kinogo-films.org"],
            @[@"https://kinohodot.online", @"kinohodot.online"],
            // Playable streaming examples (public HLS samples)
            @[@"https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8", @"Sintel (HLS sample)"],
            @[@"https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", @"Mux test stream (HLS)"]
        ];
        [[NSUserDefaults standardUserDefaults] setObject:defaultFavs forKey:@"FAVORITES"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // Debug log so you can confirm defaults were written at launch
        NSLog(@"Default FAVORITES created: %@", defaultFavs);
    }
    _displayedHintsOnLaunch = YES;
}
-(void)webViewDidAppear {
    if ([[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"] != nil) {
        [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"]]]];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"savedURLtoReopen"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    else if ([self.webview request] == nil) {
        //[self requestURLorSearchInput];
        [self loadHomePage];
    }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DontShowHintsOnLaunch"] && !_displayedHintsOnLaunch) {
        [self showHintsAlert];
    }
}
-(void)loadHomePage {
    if ([[NSUserDefaults standardUserDefaults] stringForKey:@"homepage"] != nil) {
        [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[[NSUserDefaults standardUserDefaults] stringForKey:@"homepage"]]]];
    }
    else {
        [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString: @"http://www.google.com"]]];
    }
}
-(void)initWebView {
    if (@available(tvOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }
    self.webview = [[NSClassFromString(@"UIWebView") alloc] init];
    [self.webview setTranslatesAutoresizingMaskIntoConstraints:false];
    [self.webview setClipsToBounds:false];
    
    //[self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.google.com"]]];
    
    //[self.view addSubview: self.webview];
    [self.browserContainerView addSubview: self.webview];

    [self.webview setFrame:self.view.bounds];
    [self.webview setDelegate:self];
    [self.webview setLayoutMargins:UIEdgeInsetsZero];
    UIScrollView *scrollView = [self.webview scrollView];
    [scrollView setLayoutMargins:UIEdgeInsetsZero];
    if (@available(tvOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } else {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    
    NSNumber *showTopNavBar = [[NSUserDefaults standardUserDefaults] objectForKey:@"ShowTopNavigationBar"];
    self.topMenuView.hidden = !(showTopNavBar ? showTopNavBar.boolValue : YES);
    [self updateTopNavAndWebView];
    //scrollView.contentOffset = CGPointMake(0, topHeight);
    scrollView.contentOffset = CGPointZero;
    
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.frame = self.view.bounds;
    scrollView.clipsToBounds = NO;
    [scrollView setNeedsLayout];
    [scrollView layoutIfNeeded];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    scrollView.bounces = self.scrollViewAllowBounces;
    scrollView.panGestureRecognizer.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
    scrollView.scrollEnabled = NO;
    
    [self.webview setUserInteractionEnabled:NO];
}
-(void)viewDidLoad {
    
    // --- Inserted: configure WKWebView for inline/autoplay media playback ---
    // Make sure to add '#import <WebKit/WebKit.h>' at the top of the file if not present.
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    if (@available(tvOS 10.0, *)) {
        cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    } else {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        cfg.requiresUserActionForMediaPlayback = NO;
    #pragma clang diagnostic pop
    }

    // If you want to construct the web view here, use:
    // self.webView = [[WKWebView alloc] initWithFrame:self.browserContainerView.bounds configuration:cfg];
    // self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // [self.browserContainerView addSubview:self.webView];
    // self.webView.navigationDelegate = self;
    // --- End inserted snippet ---
[super viewDidLoad];
    self.definesPresentationContext = YES;
    
    [self initWebView];
    self.scrollViewAllowBounces = YES;
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
}

#pragma mark - Font Size
- (NSUInteger)textFontSize {
    if (_textFontSize == 0) {
        NSNumber *textFontSizeValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"TextFontSize"];
        if (textFontSizeValue != nil) {
            // Limit font size
            NSUInteger textFontSize = textFontSizeValue.unsignedIntegerValue;
            _textFontSize = MIN(200, MAX(50, textFontSize));
        } else {
            // Default font size
            _textFontSize = 100;
        }
    }
    return _textFontSize;
}

- (void)setTextFontSize:(NSUInteger)textFontSize {
    if (textFontSize == _textFontSize) {
        return;
    }
    // Limit font size
    textFontSize = MIN(200, MAX(50, textFontSize));
    _textFontSize = textFontSize;
    [[NSUserDefaults standardUserDefaults] setObject:@(textFontSize) forKey:@"TextFontSize"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)updateTextFontSize {
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%lu%%'",
                          (unsigned long)self.textFontSize];
    [self.webview stringByEvaluatingJavaScriptFromString:jsString];
}

#pragma mark - Top Navigation Bar

- (BOOL)topMenuShowing {
    return !self.topMenuView.isHidden;
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
    [self.topMenuView setHidden:YES];
    
    [self updateTopNavAndWebView];
    [[NSUserDefaults standardUserDefaults] setObject:@(NO) forKey:@"ShowTopNavigationBar"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(void)showTopNav
{
    [self.topMenuView setHidden:NO];
    
    [self updateTopNavAndWebView];
    [[NSUserDefaults standardUserDefaults] setObject:@(YES) forKey:@"ShowTopNavigationBar"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(void)updateTopNavAndWebView
{
    if (self.topMenuShowing) {
        [self.webview setFrame:CGRectMake(self.view.bounds.origin.x, self.view.bounds.origin.y + self.topMenuBrowserOffset, self.view.bounds.size.width, self.view.bounds.size.height - self.topMenuBrowserOffset)];
    } else {
        [self.webview setFrame:self.view.bounds];
    }
}

-(void)showAdvancedMenu
{
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:@"Advanced Menu"
                                          message:@""
                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *topBarAction;
    if(self.topMenuShowing == YES)
    {
       topBarAction = [UIAlertAction
                                         actionWithTitle:@"Hide Top Navigation bar"
                                         style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action)
                                         {
                                             [self hideTopNav];
                                         }];
    }
    else
    {
        topBarAction = [UIAlertAction
                                       actionWithTitle:@"Show Top Navigation bar"
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action)
                                       {
                                           [self showTopNav];
                                       }];
    }
    
    UIAlertAction *loadHomePageAction = [UIAlertAction
                                         actionWithTitle:@"Go To Home Page"
                                         style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action)
                                         {
                                             [self loadHomePage];
                                         }];
    UIAlertAction *setHomePageAction = [UIAlertAction
                                        actionWithTitle:@"Set Current Page As Home Page"
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *action)
                                        {
                                            NSURLRequest *request = [self.webview request];
                                            if (request != nil) {
                                                if (![request.URL.absoluteString isEqual:@""]) {
                                                    [[NSUserDefaults standardUserDefaults] setObject:request.URL.absoluteString forKey:@"homepage"];
                                                }
                                            }
                                        }];
    UIAlertAction *showHintsAction = [UIAlertAction
                                      actionWithTitle:@"Usage Guide"
                                      style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *action)
                                      {
                                          [self showHintsAlert];
                                      }];
    UIAlertAction *cancelAction = [UIAlertAction
                                   actionWithTitle:nil
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    UIAlertAction *viewFavoritesAction = [UIAlertAction
                                          actionWithTitle:@"Favorites"
                                          style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *action)
                                          {
                                              NSArray *indexableArray = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"];
                                              UIAlertController *historyAlertController = [UIAlertController
                                                                                           alertControllerWithTitle:@"Favorites"
                                                                                           message:@""
                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                                              UIAlertAction *editFavoritesAction = [UIAlertAction
                                                                                    actionWithTitle:@"Delete a Favorite"
                                                                                    style:UIAlertActionStyleDestructive
                                                                                    handler:^(UIAlertAction *action)
                                                                                    {
                                                                                        NSArray *editingIndexableArray = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"];
                                                                                        UIAlertController *editHistoryAlertController = [UIAlertController
                                                                                                                                         alertControllerWithTitle:@"Delete a Favorite"
                                                                                                                                         message:@"Select a Favorite to Delete"
                                                                                                                                         preferredStyle:UIAlertControllerStyleAlert];
                                                                                        if (editingIndexableArray != nil) {
                                                                                            for (int i = 0; i < [editingIndexableArray count]; i++) {
                                                                                                NSString *objectTitle = editingIndexableArray[i][1];
                                                                                                NSString *objectSubtitle = editingIndexableArray[i][0];
                                                                                                if (![[objectSubtitle stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString: @""]) {
                                                                                                    if ([[objectTitle stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString: @""]) {
                                                                                                        objectTitle = objectSubtitle;
                                                                                                    }
                                                                                                    UIAlertAction *favoriteItem = [UIAlertAction
                                                                                                                                   actionWithTitle:objectTitle
                                                                                                                                   style:UIAlertActionStyleDefault
                                                                                                                                   handler:^(UIAlertAction *action)
                                                                                                                                   {
                                                                                                                                       NSMutableArray *editingArray = [editingIndexableArray mutableCopy];
                                                                                                                                       [editingArray removeObjectAtIndex:i];
                                                                                                                                       NSArray *toStoreArray = editingArray;
                                                                                                                                       [[NSUserDefaults standardUserDefaults] setObject:toStoreArray forKey:@"FAVORITES"];
                                                                                                                                       [[NSUserDefaults standardUserDefaults] synchronize];
                                                                                                                                   }];
                                                                                                    [editHistoryAlertController addAction:favoriteItem];
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                        [editHistoryAlertController addAction:cancelAction];
                                                                                        [self presentViewController:editHistoryAlertController animated:YES completion:nil];
                                                                                        
                                                                                    }];
                                              UIAlertAction *addToFavoritesAction = [UIAlertAction
                                                                                     actionWithTitle:@"Add Current Page to Favorites"
                                                                                     style:UIAlertActionStyleDefault
                                                                                     handler:^(UIAlertAction *action)
                                                                                     {
                                                                                         NSString *theTitle=[self.webview stringByEvaluatingJavaScriptFromString:@"document.title"];
                                                                                         NSURLRequest *request = [self.webview request];
                                                                                         NSString *currentURL = request.URL.absoluteString;
                                                                                         UIAlertController *favoritesAddToController = [UIAlertController
                                                                                                                                        alertControllerWithTitle:@"Name New Favorite"
                                                                                                                                        message:currentURL
                                                                                                                                        preferredStyle:UIAlertControllerStyleAlert];
                                                                                         
                                                                                         [favoritesAddToController addTextFieldWithConfigurationHandler:^(UITextField *textField)
                                                                                          {
                                                                                              textField.keyboardType = UIKeyboardTypeDefault;
                                                                                              textField.placeholder = @"Name New Favorite";
                                                                                              textField.text = theTitle;
                                                                                              textField.textColor = kTextColor();
                                                                                              [textField setReturnKeyType:UIReturnKeyDone];
                                                                                              [textField addTarget:self
                                                                                                            action:@selector(alertTextFieldShouldReturn:)
                                                                                                  forControlEvents:UIControlEventEditingDidEnd];
                                                                                              
                                                                                          }];
                                                                                         
                                                                                         UIAlertAction *saveAction = [UIAlertAction
                                                                                                                      actionWithTitle:@"Save"
                                                                                                                      style:UIAlertActionStyleDestructive
                                                                                                                      handler:^(UIAlertAction *action)
                                                                                                                      {
                                                                                                                          UITextField *titleTextField = favoritesAddToController.textFields[0];
                                                                                                                          NSString *savedTitle = titleTextField.text;
                                                                                                                          if ([savedTitle isEqualToString:@""]) {
                                                                                                                              // Use raw URL if no title
                                                                                                                              savedTitle = currentURL;
                                                                                                                          }
                                                                                                                          NSArray *toSaveItem = [NSArray arrayWithObjects:currentURL, savedTitle, nil];
                                                                                                                          NSMutableArray *historyArray = [NSMutableArray arrayWithObjects:toSaveItem, nil];
                                                                                                                          if ([[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"] != nil) {
                                                                                                                              historyArray = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"] mutableCopy];
                                                                                                                              [historyArray addObject:toSaveItem];
                                                                                                                          }
                                                                                                                          NSArray *toStoreArray = historyArray;
                                                                                                                          [[NSUserDefaults standardUserDefaults] setObject:toStoreArray forKey:@"FAVORITES"];
                                                                                                                          [[NSUserDefaults standardUserDefaults] synchronize];
                                                                                                                          
                                                                                                                      }];
                                                                                         [favoritesAddToController addAction:saveAction];
                                                                                         [favoritesAddToController addAction:cancelAction];
                                                                                         [self presentViewController:favoritesAddToController animated:YES completion:nil];
                                                                                         //UITextField *textFieldAlert = favoritesAddToController.textFields[0];
                                                                                         //[textFieldAlert becomeFirstResponder];
                                                                                         
                                                                                     }];
                                              if (indexableArray != nil) {
                                                  for (int i = 0; i < [indexableArray count]; i++) {
                                                      NSString *objectTitle = indexableArray[i][1];
                                                      NSString *objectURL = indexableArray[i][0];
                                                      if ([[objectTitle stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString: @""]) {
                                                          // Use raw URL if no title
                                                          objectTitle = objectURL;
                                                      }
                                                      UIAlertAction *favoriteItem = [UIAlertAction
                                                                                     actionWithTitle:objectTitle
                                                                                     style:UIAlertActionStyleDefault
                                                                                     handler:^(UIAlertAction *action)
                                                                                     {
                                                                                         [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString: objectURL]]];
                                                                                     }];
                                                      [historyAlertController addAction:favoriteItem];
                                                  }
                                              }
                                              if ([[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"] != nil) {
                                                  if ([[[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"] count] > 0) {
                                                      [historyAlertController addAction:editFavoritesAction];
                                                  }
                                              }
                                              [historyAlertController addAction:addToFavoritesAction];
                                              [historyAlertController addAction:cancelAction];
                                              [self presentViewController:historyAlertController animated:YES completion:nil];
                                          }];
    UIAlertAction *viewHistoryAction = [UIAlertAction
                                        actionWithTitle:@"History"
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *action)
                                        {
                                            NSArray *indexableArray = [[NSUserDefaults standardUserDefaults] arrayForKey:@"HISTORY"];
                                            UIAlertController *historyAlertController = [UIAlertController
                                                                                         alertControllerWithTitle:@"History"
                                                                                         message:@""
                                                                                         preferredStyle:UIAlertControllerStyleAlert];
                                            UIAlertAction *clearHistoryAction = [UIAlertAction
                                                                                 actionWithTitle:@"Clear History"
                                                                                 style:UIAlertActionStyleDestructive
                                                                                 handler:^(UIAlertAction *action)
                                                                                 {
                                                                                     [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"HISTORY"];
                                                                                     [[NSUserDefaults standardUserDefaults] synchronize];
                                                                                     
                                                                                 }];
                                            if ([[NSUserDefaults standardUserDefaults] arrayForKey:@"HISTORY"] != nil) {
                                                [historyAlertController addAction:clearHistoryAction];
                                            }
                                            for (int i = 0; i < [indexableArray count]; i++) {
                                                NSString *objectTitle = indexableArray[i][1];
                                                NSString *objectSubtitle = indexableArray[i][0];
                                                if (![[objectSubtitle stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString: @""]) {
                                                    if ([[objectTitle stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString: @""]) {
                                                        objectTitle = objectSubtitle;
                                                    }
                                                    else {
                                                        objectTitle = [NSString stringWithFormat:@"%@ - %@",objectTitle,objectSubtitle ];
                                                    }
                                                    UIAlertAction *historyItem = [UIAlertAction
                                                                                  actionWithTitle:objectTitle
                                                                                  style:UIAlertActionStyleDefault
                                                                                  handler:^(UIAlertAction *action)
                                                                                  {
                                                                                      [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString: indexableArray[i][0]]]];
                                                                                  }];
                                                    [historyAlertController addAction:historyItem];
                                                }
                                            }
                                            [historyAlertController addAction:cancelAction];
                                            [self presentViewController:historyAlertController animated:YES completion:nil];
                                        }];
    UIAlertAction *mobileModeAction = [UIAlertAction
                                       actionWithTitle:@"Switch To Mobile Mode"
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action)
                                       {
                                           NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Mozilla/5.0 (iPad; CPU OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0 Mobile/15E148 Safari/604.1", @"UserAgent", nil];
                                           [[NSUserDefaults standardUserDefaults] registerDefaults:dictionary];
                                           [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MobileMode"];
                                           [[NSUserDefaults standardUserDefaults] synchronize];
                                           NSURLRequest *request = [self.webview request];
                                           if (request != nil) {
                                               if (![request.URL.absoluteString isEqual:@""]) {
                                                   [[NSUserDefaults standardUserDefaults] setObject:request.URL.absoluteString forKey:@"savedURLtoReopen"];
                                                   [[NSUserDefaults standardUserDefaults] synchronize];
                                               }
                                           }
                                           NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
                                           for (NSHTTPCookie *cookie in [storage cookies]) {
                                               [storage deleteCookie:cookie];
                                           }
                                           [[NSURLCache sharedURLCache] removeAllCachedResponses];
                                           [[NSUserDefaults standardUserDefaults] synchronize];
                                           [[NSURLSession sharedSession] resetWithCompletionHandler:^{
                                               dispatch_sync(dispatch_get_main_queue(), ^{
                                                   [self.webview removeFromSuperview];
                                                   [self initWebView];
                                                   [self.view bringSubviewToFront:self.cursorView];
                                                   //[self.view bringSubviewToFront:self->loadingSpinner];
                                                   [self webViewDidAppear];
                                                   
                                               });
                                           }];
                                       }];
    UIAlertAction *desktopModeAction = [UIAlertAction
                                        actionWithTitle:@"Switch To Desktop Mode"
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *action)
                                        {
                                            NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0 Safari/605.1.15", @"UserAgent", nil];
                                            [[NSUserDefaults standardUserDefaults] registerDefaults:dictionary];
                                            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MobileMode"];
                                            [[NSUserDefaults standardUserDefaults] synchronize];
                                            NSURLRequest *request = [self.webview request];
                                            if (request != nil) {
                                                if (![request.URL.absoluteString isEqual:@""]) {
                                                    [[NSUserDefaults standardUserDefaults] setObject:request.URL.absoluteString forKey:@"savedURLtoReopen"];
                                                    [[NSUserDefaults standardUserDefaults] synchronize];
                                                }
                                            }
                                            NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
                                            for (NSHTTPCookie *cookie in [storage cookies]) {
                                                [storage deleteCookie:cookie];
                                            }
                                            [[NSURLCache sharedURLCache] removeAllCachedResponses];
                                            [[NSUserDefaults standardUserDefaults] synchronize];
                                            [[NSURLSession sharedSession] resetWithCompletionHandler:^{
                                                dispatch_sync(dispatch_get_main_queue(), ^{
                                                    [self.webview removeFromSuperview];
                                                    [self initWebView];
                                                    [self.view bringSubviewToFront:self.cursorView];
                                                    //[self.view bringSubviewToFront:self->loadingSpinner];
                                                    [self webViewDidAppear];
                                                    
                                                });
                                            }];
                                        }];
    UIAlertAction *scalePageToFitAction = [UIAlertAction
                                           actionWithTitle:@"Scale Pages to Fit"
                                           style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action)
                                           {
                                               [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ScalePagesToFit"];
                                               [[NSUserDefaults standardUserDefaults] synchronize];
                                               [self.webview setScalesPageToFit:YES];
                                               [self.webview setContentMode:UIViewContentModeScaleAspectFit];
                                               [self.webview reload];
                                           }];
    UIAlertAction *stopScalePageToFitAction = [UIAlertAction
                                               actionWithTitle:@"Stop Scaling Pages to Fit"
                                               style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action)
                                               {
                                                   [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ScalePagesToFit"];
                                                   [[NSUserDefaults standardUserDefaults] synchronize];
                                                   [self.webview setScalesPageToFit:NO];
                                                   [self.webview reload];
                                               }];
    
    UIAlertAction *increaseFontSizeAction = [UIAlertAction
                                             actionWithTitle:@"Increase Font Size"
                                             style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action)
                                             {
                                                 self.textFontSize += 5;
                                                 [self updateTextFontSize];
                                             }];
    
    UIAlertAction *decreaseFontSizeAction = [UIAlertAction
                                             actionWithTitle:@"Decrease Font Size"
                                             style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action)
                                             {
                                                 self.textFontSize -= 5;
                                                 [self updateTextFontSize];
                                             }];
    
    UIAlertAction *clearCacheAction = [UIAlertAction
                                       actionWithTitle:@"Clear Cache"
                                       style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *action)
                                       {
                                           [[NSURLCache sharedURLCache] removeAllCachedResponses];
                                           [[NSUserDefaults standardUserDefaults] synchronize];
                                           self.previousURL = @"";
                                           [self.webview reload];
                                           
                                       }];
    UIAlertAction *clearCookiesAction = [UIAlertAction
                                         actionWithTitle:@"Clear Cookies"
                                         style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action)
                                         {
                                             NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
                                             for (NSHTTPCookie *cookie in [storage cookies]) {
                                                 [storage deleteCookie:cookie];
                                             }
                                             [[NSUserDefaults standardUserDefaults] synchronize];
                                             self.previousURL = @"";
                                             [self.webview reload];
                                             
                                         }];
    
    
    /*
     UIAlertAction *reloadAction = [UIAlertAction
     actionWithTitle:@"Reload Page"
     style:UIAlertActionStyleDefault
     handler:^(UIAlertAction *action)
     {
     _inputViewVisible = NO;
     previousURL = @"";
     [self.webview reload];
     }];
     if (self.webview.request != nil) {
     if (![self.webview.request.URL.absoluteString  isEqual: @""]) {
     [alertController addAction:reloadAction];
     }
     }
     */

    [alertController addAction:viewFavoritesAction];
    [alertController addAction:viewHistoryAction];
    [alertController addAction:loadHomePageAction];
    [alertController addAction:setHomePageAction];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"MobileMode"]) {
        [alertController addAction:desktopModeAction];
    }
    else {
        [alertController addAction:mobileModeAction];
    }
    [alertController addAction:topBarAction];
    if ([self.webview scalesPageToFit]) {
        [alertController addAction:stopScalePageToFitAction];
    } else {
        [alertController addAction:scalePageToFitAction];
    }
    
    [alertController addAction:increaseFontSizeAction];
    [alertController addAction:decreaseFontSizeAction];
    [alertController addAction:clearCacheAction];
    [alertController addAction:clearCookiesAction];
    [alertController addAction:showHintsAction];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - Gesture
-(void)handlePlayPauseDoubleTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        [self showAdvancedMenu];
    }
}
-(void)handleTouchSurfaceDoubleTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
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
                                       if ([toMod containsString:@"http://"] || [toMod containsString:@"https://"]) {
                                           [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", toMod]]]];
                                       }
                                       else {
                                           [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@", toMod]]]];
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
                                       NSString *toMod = urltextfield.text;
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
    //[self.view bringSubviewToFront:loadingSpinner];
    if (![self.previousURL isEqualToString:self.requestURL]) {
        [self.loadingSpinner startAnimating];
    }
    self.previousURL = self.requestURL;
}
-(void) webViewDidFinishLoad:(id)webView {
    [self.loadingSpinner stopAnimating];
    //[self.view bringSubviewToFront:loadingSpinner];
    NSString *theTitle=[webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    NSURLRequest *request = [webView request];
    NSString *currentURL = request.URL.absoluteString;
    
    self.lblUrlBar.text = currentURL;
    
    // Update font size
    [self updateTextFontSize];
    
    NSArray *toSaveItem = [NSArray arrayWithObjects:currentURL, theTitle, nil];
    NSMutableArray *historyArray = [NSMutableArray arrayWithObjects:toSaveItem, nil];
    if ([[NSUserDefaults standardUserDefaults] arrayForKey:@"HISTORY"] != nil) {
        NSMutableArray *savedArray = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"HISTORY"] mutableCopy];
        if ([savedArray count] > 0) {
            if ([savedArray[0][0] isEqualToString: currentURL]) {
                [historyArray removeObjectAtIndex:0];
            }
        }
        [historyArray addObjectsFromArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"HISTORY"]];
    }
    while ([historyArray count] > 100) {
        [historyArray removeLastObject];
    }
    NSArray *toStoreArray = historyArray;
    [[NSUserDefaults standardUserDefaults] setObject:toStoreArray forKey:@"HISTORY"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (BOOL)webView:(id)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType {
    self.requestURL = request.URL.absoluteString;
    return YES;
}

- (void)webView:(id)webView didFailLoadWithError:(NSError *)error {
    [self.loadingSpinner stopAnimating];
    if (![[NSString stringWithFormat:@"%lid", (long)error.code] containsString:@"999"] && ![[NSString stringWithFormat:@"%lid", (long)error.code] containsString:@"204"]) {
        UIAlertController *alertController = [UIAlertController
                                              alertControllerWithTitle:@"Could Not Load Webpage"
                                              message:[error localizedDescription]
                                              preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *searchAction = [UIAlertAction
                                       actionWithTitle:@"Google This Page"
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action)
                                       {
                                           if (self.requestURL != nil) {
                                               if ([self.requestURL length] > 1) {
                                                   NSString *lastChar = [self.requestURL substringFromIndex: [self.requestURL length] - 1];
                                                   if ([lastChar isEqualToString:@"/"]) {
                                                       NSString *newString = [self.requestURL substringToIndex:[self.requestURL length]-1];
                                                       self.requestURL = newString;
                                                   }
                                               }
                                               self.requestURL = [self.requestURL stringByReplacingOccurrencesOfString:@"http://" withString:@""];
                                               self.requestURL = [self.requestURL stringByReplacingOccurrencesOfString:@"https://" withString:@""];
                                               self.requestURL = [self.requestURL stringByReplacingOccurrencesOfString:@"www." withString:@""];
                                               [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/search?q=%@", self.requestURL]]]];
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
        if (self.requestURL != nil) {
            if ([self.requestURL length] > 1) {
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
    self.cursorMode = !self.cursorMode;
    UIScrollView *scrollView = [self.webview scrollView];
    if (self.cursorMode)
    {
        scrollView.scrollEnabled = NO;
        [self.webview setUserInteractionEnabled:NO];
        self.cursorView.hidden = NO;
    }
    else
    {
        scrollView.scrollEnabled = YES;
        [self.webview setUserInteractionEnabled:YES];
        self.cursorView.hidden = YES;
        
        
    }
}
- (void)showHintsAlert
{
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:@"Usage Guide"
                                          message:@"Double press the touch area to switch between cursor & scroll mode.\nPress the touch area while in cursor mode to click.\nSingle tap to Menu button to Go Back, or Exit on root page.\nSingle tap the Play/Pause button to: Go Forward, Enter URL or Reload Page.\nDouble tap the Play/Pause to show the Advanced Menu with more options."
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
    
    
    if (presses.anyObject.type == UIPressTypeMenu)
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
    else if (presses.anyObject.type == UIPressTypeUpArrow)
    {
        // Zoom testing (needs work) (requires old remote for up arrow)
        //UIScrollView * sv = self.webview.scrollView;
        //[sv setZoomScale:30];
    }
    else if (presses.anyObject.type == UIPressTypeDownArrow)
    {
    }
    
    
    else if (presses.anyObject.type == UIPressTypeSelect) // Handle the normal single Touchpad press with our virtual cursor
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
    
    else if (presses.anyObject.type == UIPressTypePlayPause)
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
