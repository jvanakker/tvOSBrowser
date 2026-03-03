#import <UIKit/UIKit.h>

@protocol BrowserMenuPresenterHost <NSObject>

@property (nonatomic, readonly) id browserWebView;
@property (nonatomic, copy) NSString *browserPreviousURL;
@property (nonatomic) NSUInteger browserTextFontSize;
@property (nonatomic, readonly) BOOL browserTopMenuShowing;

- (void)browserPresentViewController:(UIViewController *)viewController;
- (void)browserLoadHomePage;
- (void)browserShowHints;
- (void)browserShowTabOverview;
- (void)browserCreateNewTabLoadingHomePage:(BOOL)loadHomePage;
- (void)browserHideTopNav;
- (void)browserShowTopNav;
- (void)browserUpdateTextFontSize;
- (void)browserCaptureSnapshotForCurrentTab;
- (void)browserRecreateActiveWebViewPreservingCurrentURL;
- (void)browserBringCursorToFront;

@end

@interface BrowserMenuPresenter : NSObject

- (instancetype)initWithHost:(id<BrowserMenuPresenterHost>)host;
- (void)showAdvancedMenu;

@end
