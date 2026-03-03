#import "BrowserNavigationService.h"

#import "BrowserTabViewModel.h"

static NSString * const kHistoryDefaultsKey = @"HISTORY";
static NSString * const kHomepageDefaultsKey = @"homepage";
static NSUInteger const kMaximumHistoryCount = 100;

@implementation BrowserNavigationService

- (NSURLRequest *)homePageRequest {
    NSString *homePageURLString = [[NSUserDefaults standardUserDefaults] stringForKey:kHomepageDefaultsKey];
    if (homePageURLString.length == 0) {
        homePageURLString = @"http://www.google.com";
    }
    return [self requestForURLString:homePageURLString];
}

- (NSURLRequest *)requestForEnteredAddressString:(NSString *)addressString {
    NSString *trimmedAddress = [self trimmedString:addressString];
    if (trimmedAddress.length == 0) {
        return nil;
    }
    
    if (![trimmedAddress hasPrefix:@"http://"] && ![trimmedAddress hasPrefix:@"https://"]) {
        trimmedAddress = [@"http://" stringByAppendingString:trimmedAddress];
    }
    return [self requestForURLString:trimmedAddress];
}

- (NSURLRequest *)googleSearchRequestForQuery:(NSString *)query {
    NSString *sanitizedQuery = [self sanitizedSearchQuery:query];
    if (sanitizedQuery.length == 0) {
        return nil;
    }
    
    NSString *searchURLString = [NSString stringWithFormat:@"https://www.google.com/search?q=%@", sanitizedQuery];
    return [self requestForURLString:searchURLString];
}

- (NSURLRequest *)googleSearchRequestForFailedRequestURLString:(NSString *)requestURLString {
    NSString *searchQuery = [self trimmedString:requestURLString];
    if (searchQuery.length == 0) {
        return nil;
    }
    
    if ([searchQuery hasSuffix:@"/"]) {
        searchQuery = [searchQuery substringToIndex:searchQuery.length - 1];
    }
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"https://" withString:@""];
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"www." withString:@""];
    
    return [self googleSearchRequestForQuery:searchQuery];
}

- (void)updateTab:(BrowserTabViewModel *)tab
    withPageTitle:(NSString *)pageTitle
  currentURLString:(NSString *)currentURLString {
    if (tab == nil) {
        return;
    }
    
    NSString *safeTitle = pageTitle ?: @"";
    NSString *safeURLString = currentURLString ?: @"";
    tab.title = safeTitle.length > 0 ? safeTitle : @"New Tab";
    tab.URLString = safeURLString;
    
    [self persistHistoryItemWithURLString:safeURLString title:safeTitle];
}

- (BOOL)shouldIgnoreLoadError:(NSError *)error {
    NSInteger errorCode = error.code;
    return errorCode == 999 || errorCode == 204;
}

- (NSURLRequest *)requestForURLString:(NSString *)URLString {
    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL == nil) {
        return nil;
    }
    return [NSURLRequest requestWithURL:URL];
}

- (NSString *)trimmedString:(NSString *)string {
    if (string == nil) {
        return @"";
    }
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)sanitizedSearchQuery:(NSString *)query {
    NSString *trimmedQuery = [self trimmedString:query];
    if (trimmedQuery.length == 0) {
        return @"";
    }
    
    NSString *searchQuery = [trimmedQuery stringByReplacingOccurrencesOfString:@" " withString:@"+"];
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"." withString:@"+"];
    while ([searchQuery containsString:@"++"]) {
        searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
    }
    
    return [searchQuery stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
}

- (void)persistHistoryItemWithURLString:(NSString *)URLString title:(NSString *)title {
    if (URLString.length == 0) {
        return;
    }
    
    NSArray *historyItem = @[URLString, title ?: @""];
    NSMutableArray *historyItems = [NSMutableArray arrayWithObject:historyItem];
    NSArray *storedHistory = [[NSUserDefaults standardUserDefaults] arrayForKey:kHistoryDefaultsKey];
    if (storedHistory.count > 0) {
        NSArray *latestItem = storedHistory.firstObject;
        if ([latestItem isKindOfClass:[NSArray class]] && latestItem.count > 0 && [latestItem[0] isEqualToString:URLString]) {
            [historyItems removeObjectAtIndex:0];
        }
        [historyItems addObjectsFromArray:storedHistory];
    }
    
    while (historyItems.count > kMaximumHistoryCount) {
        [historyItems removeLastObject];
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:historyItems forKey:kHistoryDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
