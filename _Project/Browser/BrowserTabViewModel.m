#import "BrowserTabViewModel.h"

@implementation BrowserTabViewModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[[NSUUID UUID] UUIDString] copy];
        _requestURL = @"";
        _previousURL = @"";
        _title = @"New Tab";
        _URLString = @"";
        _savedScrollOffset = CGPointZero;
        _hasSavedScrollOffset = NO;
        _needsScrollRestore = NO;
    }
    return self;
}

- (instancetype)initWithSessionRepresentation:(NSDictionary *)sessionRepresentation {
    self = [self init];
    if (self == nil) {
        return nil;
    }
    
    NSString *requestURL = [sessionRepresentation[@"requestURL"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"requestURL"] : @"";
    NSString *previousURL = [sessionRepresentation[@"previousURL"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"previousURL"] : @"";
    NSString *title = [sessionRepresentation[@"title"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"title"] : @"New Tab";
    NSString *URLString = [sessionRepresentation[@"URLString"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"URLString"] : @"";
    NSNumber *scrollOffsetX = [sessionRepresentation[@"scrollOffsetX"] isKindOfClass:[NSNumber class]] ? sessionRepresentation[@"scrollOffsetX"] : nil;
    NSNumber *scrollOffsetY = [sessionRepresentation[@"scrollOffsetY"] isKindOfClass:[NSNumber class]] ? sessionRepresentation[@"scrollOffsetY"] : nil;
    
    self.requestURL = requestURL;
    self.previousURL = previousURL;
    self.title = title.length > 0 ? title : @"New Tab";
    self.URLString = URLString;
    if (scrollOffsetX != nil && scrollOffsetY != nil) {
        self.savedScrollOffset = CGPointMake(scrollOffsetX.doubleValue, scrollOffsetY.doubleValue);
        self.hasSavedScrollOffset = YES;
        self.needsScrollRestore = YES;
    }
    
    return self;
}

- (NSDictionary *)sessionRepresentation {
    NSMutableDictionary *representation = [NSMutableDictionary dictionary];
    representation[@"requestURL"] = self.requestURL ?: @"";
    representation[@"previousURL"] = self.previousURL ?: @"";
    representation[@"title"] = self.title ?: @"New Tab";
    representation[@"URLString"] = self.URLString ?: @"";
    if (self.hasSavedScrollOffset) {
        representation[@"scrollOffsetX"] = @(self.savedScrollOffset.x);
        representation[@"scrollOffsetY"] = @(self.savedScrollOffset.y);
    }
    return representation;
}

@end
