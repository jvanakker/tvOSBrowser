#import <Foundation/Foundation.h>

@class BrowserWebView;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BrowserYouTubeExtractorErrorDomain;

typedef NS_ENUM(NSInteger, BrowserYouTubeExtractorErrorCode) {
    BrowserYouTubeExtractorErrorCodeUnsupportedURL = 1,
    BrowserYouTubeExtractorErrorCodeMissingVideoID = 2,
    BrowserYouTubeExtractorErrorCodeMissingPageConfig = 3,
    BrowserYouTubeExtractorErrorCodeNetworkFailure = 4,
    BrowserYouTubeExtractorErrorCodeInvalidResponse = 5,
    BrowserYouTubeExtractorErrorCodeNoPlayableURL = 6,
};

@interface BrowserYouTubeExtractionResult : NSObject

@property (nonatomic, strong, readonly) NSURL *playbackURL;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *sourceDescription;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *requestHeaders;

- (instancetype)initWithPlaybackURL:(NSURL *)playbackURL
                              title:(nullable NSString *)title
                  sourceDescription:(nullable NSString *)sourceDescription
                     requestHeaders:(nullable NSDictionary<NSString *, NSString *> *)requestHeaders NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface BrowserYouTubeExtractor : NSObject

- (BOOL)canExtractFromPageURL:(nullable NSURL *)pageURL;

- (void)extractPlaybackInfoFromPageURL:(NSURL *)pageURL
                               webView:(BrowserWebView *)webView
                            completion:(void (^)(BrowserYouTubeExtractionResult * _Nullable result,
                                                 NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
