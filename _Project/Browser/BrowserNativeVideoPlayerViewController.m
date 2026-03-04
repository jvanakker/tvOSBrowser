#import "BrowserNativeVideoPlayerViewController.h"
#import "BrowserNativeVideoAssetLoader.h"

#import <AVFoundation/AVFoundation.h>

static NSString * const kBrowserNativeVideoPlayerLogPrefix = @"[NativeVideoPlayer]";

@interface BrowserNativeVideoPlayerView : UIView

@property (nonatomic, strong) AVPlayer *player;

@end

@implementation BrowserNativeVideoPlayerView

+ (Class)layerClass {
    return [AVPlayerLayer class];
}

- (AVPlayerLayer *)playerLayer {
    return (AVPlayerLayer *)self.layer;
}

- (void)setPlayer:(AVPlayer *)player {
    _player = player;
    self.playerLayer.player = player;
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
}

@end

@interface BrowserNativeVideoPlayerViewController ()

@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, copy) NSString *videoTitle;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *requestHeaders;
@property (nonatomic, copy) NSArray<NSHTTPCookie *> *requestCookies;
@property (nonatomic, strong) BrowserNativeVideoAssetLoader *assetLoader;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) BrowserNativeVideoPlayerView *playerView;
@property (nonatomic, strong) UIView *chromeView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *hintLabel;

@end

@implementation BrowserNativeVideoPlayerViewController

- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"%@ %@", kBrowserNativeVideoPlayerLogPrefix, message);
}

- (instancetype)initWithURL:(NSURL *)URL title:(NSString *)title {
    return [self initWithURL:URL title:title requestHeaders:nil cookies:nil];
}

- (instancetype)initWithURL:(NSURL *)URL
                      title:(NSString *)title
             requestHeaders:(NSDictionary<NSString *,NSString *> *)requestHeaders
                    cookies:(NSArray<NSHTTPCookie *> *)cookies {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _videoURL = URL;
        _videoTitle = [title copy] ?: @"";
        _requestHeaders = [requestHeaders copy] ?: @{};
        _requestCookies = [cookies copy] ?: @[];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)loadView {
    self.playerView = [[BrowserNativeVideoPlayerView alloc] initWithFrame:CGRectZero];
    self.playerView.backgroundColor = UIColor.blackColor;
    self.view = self.playerView;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.blackColor;
    AVPlayerItem *playerItem = nil;
    if (self.requestHeaders.count > 0 || self.requestCookies.count > 0) {
        NSMutableDictionary *assetOptions = [NSMutableDictionary dictionary];
        if (self.requestHeaders.count > 0) {
            assetOptions[@"AVURLAssetHTTPHeaderFieldsKey"] = self.requestHeaders;
            NSString *userAgent = self.requestHeaders[@"User-Agent"];
            if (userAgent.length > 0) {
                assetOptions[@"AVURLAssetHTTPUserAgentKey"] = userAgent;
            }
        }
        if (self.requestCookies.count > 0) {
            assetOptions[@"AVURLAssetHTTPCookiesKey"] = self.requestCookies;
        }
        self.assetLoader = [[BrowserNativeVideoAssetLoader alloc] initWithRequestHeaders:self.requestHeaders cookies:self.requestCookies];
        NSURL *assetURL = [self.assetLoader assetURLForPlaybackURL:self.videoURL];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL options:assetOptions];
        [self.assetLoader attachToAsset:asset];
        playerItem = [AVPlayerItem playerItemWithAsset:asset];
        [self log:@"using request headers %@ cookies=%lu", self.requestHeaders, (unsigned long)self.requestCookies.count];
    } else {
        playerItem = [AVPlayerItem playerItemWithURL:self.videoURL];
    }
    self.player = [AVPlayer playerWithPlayerItem:playerItem];
    self.playerView.player = self.player;
    [self log:@"created player url=%@", self.videoURL.absoluteString ?: @""];

    self.chromeView = [[UIView alloc] initWithFrame:CGRectZero];
    self.chromeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chromeView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.chromeView.layer.cornerRadius = 18.0;
    [self.view addSubview:self.chromeView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:34.0];
    self.titleLabel.text = self.videoTitle.length > 0 ? self.videoTitle : self.videoURL.absoluteString;
    [self.chromeView addSubview:self.titleLabel];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.hintLabel.numberOfLines = 2;
    self.hintLabel.font = [UIFont systemFontOfSize:24.0];
    self.hintLabel.text = @"Menu: Close   Play/Pause or Select: Toggle";
    [self.chromeView addSubview:self.hintLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.chromeView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:54.0],
        [self.chromeView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:34.0],
        [self.chromeView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-54.0],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.chromeView.leadingAnchor constant:24.0],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.chromeView.topAnchor constant:18.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.chromeView.trailingAnchor constant:-24.0],

        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.chromeView.leadingAnchor constant:24.0],
        [self.hintLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:10.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.chromeView.trailingAnchor constant:-24.0],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:self.chromeView.bottomAnchor constant:-18.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePlayerItemFailedToPlayToEndTime:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:self.player.currentItem];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePlayerItemNewErrorLogEntry:)
                                                 name:AVPlayerItemNewErrorLogEntryNotification
                                               object:self.player.currentItem];

    [self.player.currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    if (@available(tvOS 10.0, *)) {
        [self.player addObserver:self
                      forKeyPath:@"timeControlStatus"
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:NULL];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self log:@"viewDidAppear play"];
    [self.player play];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self log:@"viewWillDisappear pause"];
    [self.player pause];
}

- (void)dealloc {
    @try {
        [self.player.currentItem removeObserver:self forKeyPath:@"status"];
    } @catch (__unused NSException *exception) {}
    @try {
        [self.player removeObserver:self forKeyPath:@"timeControlStatus"];
    } @catch (__unused NSException *exception) {}
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)togglePlayback {
    if (self.player.rate > 0.0) {
        [self log:@"toggle pause"];
        [self.player pause];
    } else {
        [self log:@"toggle play"];
        [self.player play];
    }
}

- (void)closePlayer {
    [self log:@"close player"];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handlePlayerItemFailedToPlayToEndTime:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self log:@"failedToPlayToEnd error=%@", error];
}

- (void)handlePlayerItemNewErrorLogEntry:(NSNotification *)notification {
    AVPlayerItemErrorLog *errorLog = self.player.currentItem.errorLog;
    AVPlayerItemErrorLogEvent *lastEvent = errorLog.events.lastObject;
    [self log:@"errorLog domain=%@ status=%ld comment=%@ serverAddress=%@ playbackSessionID=%@",
     lastEvent.errorDomain ?: @"",
     (long)lastEvent.errorStatusCode,
     lastEvent.errorComment ?: @"",
     lastEvent.serverAddress ?: @"",
     lastEvent.playbackSessionID ?: @""];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (object == self.player.currentItem && [keyPath isEqualToString:@"status"]) {
        switch (self.player.currentItem.status) {
            case AVPlayerItemStatusUnknown:
                [self log:@"item status=unknown error=%@", self.player.currentItem.error];
                break;
            case AVPlayerItemStatusReadyToPlay:
                [self log:@"item status=ready duration=%f likelyToKeepUp=%d bufferEmpty=%d",
                 CMTimeGetSeconds(self.player.currentItem.duration),
                 self.player.currentItem.isPlaybackLikelyToKeepUp,
                 self.player.currentItem.isPlaybackBufferEmpty];
                break;
            case AVPlayerItemStatusFailed:
                [self log:@"item status=failed error=%@", self.player.currentItem.error];
                break;
        }
        return;
    }

    if (object == self.player && [keyPath isEqualToString:@"timeControlStatus"]) {
        if (@available(tvOS 10.0, *)) {
            NSString *status = @"unknown";
            switch (self.player.timeControlStatus) {
                case AVPlayerTimeControlStatusPaused:
                    status = @"paused";
                    break;
                case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                    status = @"waiting";
                    break;
                case AVPlayerTimeControlStatusPlaying:
                    status = @"playing";
                    break;
            }
            [self log:@"timeControlStatus=%@ reason=%@", status, self.player.reasonForWaitingToPlay ?: @""];
            return;
        }
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses) {
        switch (press.type) {
            case UIPressTypeMenu:
                [self closePlayer];
                handled = YES;
                break;
            case UIPressTypePlayPause:
            case UIPressTypeSelect:
                [self togglePlayback];
                handled = YES;
                break;
            default:
                break;
        }
    }

    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

@end
