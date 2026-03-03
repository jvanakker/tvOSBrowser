#import "BrowserSessionStore.h"

#import "BrowserTabViewModel.h"
#import "BrowserViewModel.h"

static NSString * const kBrowserSessionFilename = @"BrowserSession.plist";
static NSString * const kBrowserSessionTabsKey = @"tabs";
static NSString * const kBrowserSessionActiveTabIndexKey = @"activeTabIndex";
static NSString * const kBrowserSessionVersionKey = @"version";
static NSNumber *BrowserSessionVersion(void) {
    return @1;
}

@implementation BrowserSessionStore

- (BOOL)restoreSessionIntoViewModel:(BrowserViewModel *)viewModel {
    NSDictionary *sessionRepresentation = [NSDictionary dictionaryWithContentsOfURL:[self sessionFileURL]];
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
        [[NSFileManager defaultManager] removeItemAtURL:[self sessionFileURL] error:nil];
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
    
    NSURL *sessionFileURL = [self sessionFileURL];
    [self ensureSessionDirectoryExists];
    [sessionRepresentation writeToURL:sessionFileURL atomically:YES];
}

- (NSURL *)sessionFileURL {
    NSURL *applicationSupportDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                                inDomains:NSUserDomainMask] firstObject];
    return [applicationSupportDirectory URLByAppendingPathComponent:kBrowserSessionFilename];
}

- (void)ensureSessionDirectoryExists {
    NSURL *sessionFileURL = [self sessionFileURL];
    NSURL *directoryURL = [sessionFileURL URLByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
}

@end
