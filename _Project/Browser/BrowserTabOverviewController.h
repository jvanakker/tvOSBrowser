#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class BrowserTabViewModel;
@class BrowserTopBarView;
@class BrowserViewModel;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserTabOverviewControllerHost <NSObject>

- (BOOL)browserTabOverviewControllerCursorModeEnabled;
- (void)browserTabOverviewControllerSetCursorModeEnabled:(BOOL)enabled;
- (void)browserTabOverviewControllerPresentViewController:(UIViewController *)viewController;
- (void)browserTabOverviewControllerCreateNewTabLoadingHomePage:(BOOL)loadHomePage;
- (void)browserTabOverviewControllerSwitchToTabAtIndex:(NSInteger)tabIndex;
- (void)browserTabOverviewControllerCloseTabAtIndex:(NSInteger)tabIndex;

@end

@interface BrowserTabOverviewController : NSObject

@property (nonatomic, readonly, getter=isVisible) BOOL visible;

- (instancetype)initWithHost:(id<BrowserTabOverviewControllerHost>)host
                   viewModel:(BrowserViewModel *)viewModel
                    rootView:(UIView *)rootView
                  topMenuView:(BrowserTopBarView *)topMenuView
                  cursorView:(UIImageView *)cursorView NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)show;
- (void)dismiss;
- (void)reload;
- (void)updateCardAtIndex:(NSInteger)tabIndex;
- (void)handleAlternateAction;
- (BOOL)containsPoint:(CGPoint)viewPoint;
- (BOOL)handleSelectionAtPoint:(CGPoint)viewPoint;

@end

NS_ASSUME_NONNULL_END
