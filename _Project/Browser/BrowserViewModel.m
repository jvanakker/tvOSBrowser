#import "BrowserViewModel.h"

#import "BrowserTabViewModel.h"

static NSUInteger const kDefaultTextFontSize = 100;
static NSUInteger const kMinimumTextFontSize = 50;
static NSUInteger const kMaximumTextFontSize = 200;
static NSUInteger const kMaximumTabCount = 5;
static NSString * const kEnableFullscreenVideoPlaybackDefaultsKey = @"EnableFullscreenVideoPlayback";

@implementation BrowserViewModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _tabs = [NSMutableArray array];
        _activeTabIndex = NSNotFound;
        NSNumber *showTopNavBar = [[NSUserDefaults standardUserDefaults] objectForKey:@"ShowTopNavigationBar"];
        _topNavigationBarVisible = showTopNavBar ? showTopNavBar.boolValue : YES;
        NSNumber *textFontSizeValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"TextFontSize"];
        if (textFontSizeValue != nil) {
            NSUInteger textFontSize = textFontSizeValue.unsignedIntegerValue;
            _textFontSize = MIN(kMaximumTextFontSize, MAX(kMinimumTextFontSize, textFontSize));
        } else {
            _textFontSize = kDefaultTextFontSize;
        }
        _fullscreenVideoPlaybackEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableFullscreenVideoPlaybackDefaultsKey];
    }
    return self;
}

- (BrowserTabViewModel *)activeTab {
    if (self.activeTabIndex == NSNotFound || self.activeTabIndex < 0 || self.activeTabIndex >= self.tabs.count) {
        return nil;
    }
    return self.tabs[self.activeTabIndex];
}

- (BrowserTabViewModel *)addTab {
    if (self.tabs.count >= kMaximumTabCount) {
        return nil;
    }
    
    BrowserTabViewModel *tab = [BrowserTabViewModel new];
    [self.tabs addObject:tab];
    self.activeTabIndex = self.tabs.count - 1;
    return tab;
}

- (BrowserTabViewModel *)ensureActiveTab {
    BrowserTabViewModel *tab = [self activeTab];
    if (tab != nil) {
        return tab;
    }
    return [self addTab];
}

- (BrowserTabViewModel *)removeTabAtIndex:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex >= self.tabs.count) {
        return nil;
    }
    
    BrowserTabViewModel *removedTab = self.tabs[tabIndex];
    [self.tabs removeObjectAtIndex:tabIndex];
    
    if (self.tabs.count == 0) {
        self.activeTabIndex = NSNotFound;
    } else if (tabIndex == self.activeTabIndex) {
        self.activeTabIndex = MIN(tabIndex, self.tabs.count - 1);
    } else if (tabIndex < self.activeTabIndex) {
        self.activeTabIndex -= 1;
    }
    
    return removedTab;
}

- (void)restoreTabs:(NSArray<BrowserTabViewModel *> *)tabs activeTabIndex:(NSInteger)activeTabIndex {
    [self.tabs removeAllObjects];
    if (tabs.count > 0) {
        [self.tabs addObjectsFromArray:tabs];
    }
    
    if (self.tabs.count == 0) {
        self.activeTabIndex = NSNotFound;
        return;
    }
    
    if (activeTabIndex < 0 || activeTabIndex >= self.tabs.count) {
        self.activeTabIndex = 0;
        return;
    }
    
    self.activeTabIndex = activeTabIndex;
}

- (void)switchToTabAtIndex:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex >= self.tabs.count) {
        return;
    }
    self.activeTabIndex = tabIndex;
}

- (void)setTopNavigationBarVisible:(BOOL)topNavigationBarVisible {
    _topNavigationBarVisible = topNavigationBarVisible;
    [[NSUserDefaults standardUserDefaults] setObject:@(topNavigationBarVisible) forKey:@"ShowTopNavigationBar"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setTextFontSize:(NSUInteger)textFontSize {
    textFontSize = MIN(kMaximumTextFontSize, MAX(kMinimumTextFontSize, textFontSize));
    _textFontSize = textFontSize;
    [[NSUserDefaults standardUserDefaults] setObject:@(textFontSize) forKey:@"TextFontSize"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setFullscreenVideoPlaybackEnabled:(BOOL)fullscreenVideoPlaybackEnabled {
    _fullscreenVideoPlaybackEnabled = fullscreenVideoPlaybackEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:fullscreenVideoPlaybackEnabled forKey:kEnableFullscreenVideoPlaybackDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
