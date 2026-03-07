#import "BrowserSessionStore.h"

#import "BrowserNavigationService.h"
#import "BrowserTabViewModel.h"
#import "BrowserViewModel.h"

static NSString * const kBrowserSessionDefaultsKey = @"BrowserSession";
static NSString * const kBrowserSessionTabsKey = @"tabs";
static NSString * const kBrowserSessionActiveTabIndexKey = @"activeTabIndex";
static NSString * const kBrowserSessionVersionKey = @"version";
static NSString * const kBrowserSavedURLToReopenDefaultsKey = @"savedURLtoReopen";
static NSNumber *BrowserSessionVersion(void) {
    return @1;
}

@implementation BrowserSessionStore

- (BOOL)restoreSessionIntoViewModel:(BrowserViewModel *)viewModel {
    NSDictionary *sessionRepresentation = [self restoredSessionRepresentation];
    if (![sessionRepresentation isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    NSArray *tabRepresentations = [sessionRepresentation[kBrowserSessionTabsKey] isKindOfClass:[NSArray class]] ? sessionRepresentation[kBrowserSessionTabsKey] : nil;
    if (tabRepresentations.count == 0) {
        return NO;
    }
    
    NSMutableArray<BrowserTabViewModel *> *tabs = [NSMutableArray array];
    for (NSDictionary *tabRepresentation in tabRepresentations) {
        if (![tabRepresentation isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        BrowserTabViewModel *tab = [[BrowserTabViewModel alloc] initWithSessionRepresentation:tabRepresentation];
        if (tab != nil) {
            [tabs addObject:tab];
        }
    }
    
    if (tabs.count == 0) {
        return NO;
    }
    
    NSInteger activeTabIndex = [sessionRepresentation[kBrowserSessionActiveTabIndexKey] respondsToSelector:@selector(integerValue)] ? [sessionRepresentation[kBrowserSessionActiveTabIndexKey] integerValue] : 0;
    [viewModel restoreTabs:tabs activeTabIndex:activeTabIndex];
    return YES;
}

- (void)saveSessionForViewModel:(BrowserViewModel *)viewModel {
    if (viewModel.tabs.count == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBrowserSessionDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return;
    }
    
    NSMutableArray *tabRepresentations = [NSMutableArray arrayWithCapacity:viewModel.tabs.count];
    for (BrowserTabViewModel *tab in viewModel.tabs) {
        [tabRepresentations addObject:[tab sessionRepresentation]];
    }
    
    NSDictionary *sessionRepresentation = @{
        kBrowserSessionVersionKey: BrowserSessionVersion(),
        kBrowserSessionActiveTabIndexKey: @(viewModel.activeTabIndex),
        kBrowserSessionTabsKey: tabRepresentations
    };

    [[NSUserDefaults standardUserDefaults] setObject:sessionRepresentation forKey:kBrowserSessionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDictionary *)restoredSessionRepresentation {
    NSDictionary *defaultsRepresentation = [[NSUserDefaults standardUserDefaults] objectForKey:kBrowserSessionDefaultsKey];
    if ([defaultsRepresentation isKindOfClass:[NSDictionary class]]) {
        return defaultsRepresentation;
    }

    return nil;
}

- (NSURLRequest *)consumeSavedURLToReopenRequestWithNavigationService:(BrowserNavigationService *)navigationService {
    NSString *savedURLString = [[NSUserDefaults standardUserDefaults] stringForKey:kBrowserSavedURLToReopenDefaultsKey];
    if (savedURLString.length == 0) {
        return nil;
    }

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBrowserSavedURLToReopenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (navigationService == nil) {
        return nil;
    }
    return [navigationService requestForURLString:savedURLString];
}

@end
