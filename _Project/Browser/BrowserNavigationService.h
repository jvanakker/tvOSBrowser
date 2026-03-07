#import <Foundation/Foundation.h>

@class BrowserTabViewModel;

@interface BrowserNavigationService : NSObject

- (NSURLRequest *)homePageRequest;
- (NSURLRequest *)requestForURLString:(NSString *)URLString;
- (NSURLRequest *)requestForEnteredAddressString:(NSString *)addressString;
- (NSURLRequest *)googleSearchRequestForQuery:(NSString *)query;
- (NSURLRequest *)googleSearchRequestForFailedRequestURLString:(NSString *)requestURLString;
- (void)updateTab:(BrowserTabViewModel *)tab
    withPageTitle:(NSString *)pageTitle
  currentURLString:(NSString *)currentURLString;
- (BOOL)shouldIgnoreLoadError:(NSError *)error;

@end
