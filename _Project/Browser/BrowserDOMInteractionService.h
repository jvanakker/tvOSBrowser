#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class BrowserWebView;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserDOMInteractionService : NSObject

- (CGPoint)DOMPointForCursorOrigin:(CGPoint)cursorOrigin
                            inView:(UIView *)containerView
                           webView:(BrowserWebView *)webView;
- (NSString *)evaluateResolvedElementJavaScriptAtPoint:(CGPoint)point
                                                webView:(BrowserWebView *)webView
                                                   body:(NSString *)body;
- (NSString *)evaluateEditableElementJavaScriptAtPoint:(CGPoint)point
                                                webView:(BrowserWebView *)webView
                                                   body:(NSString *)body;
- (NSString *)evaluateHoverStateJavaScriptAtPoint:(CGPoint)point
                                           webView:(BrowserWebView *)webView;
- (NSString *)javaScriptEscapedString:(NSString *)string;
- (NSDictionary *)videoInfoAtDOMPoint:(CGPoint)point
                               webView:(BrowserWebView *)webView;
- (NSDictionary *)linkInfoAtDOMPoint:(CGPoint)point
                              webView:(BrowserWebView *)webView;
- (NSDictionary *)directVideoInfoAtDOMPoint:(CGPoint)point
                                     webView:(BrowserWebView *)webView;
- (BOOL)isVideoActivationTargetAtDOMPoint:(CGPoint)point
                                   webView:(BrowserWebView *)webView;
- (BOOL)isVideoDismissTargetAtDOMPoint:(CGPoint)point
                                webView:(BrowserWebView *)webView;
- (NSDictionary *)primedVideoInfoAtDOMPoint:(CGPoint)point
                                     webView:(BrowserWebView *)webView;
- (NSDictionary *)activateVideoTargetAtDOMPoint:(CGPoint)point
                                         webView:(BrowserWebView *)webView
                                         timeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
