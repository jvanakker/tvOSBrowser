#import "BrowserWebView.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const kBrowserWebViewClassName = @"WKWebView";
static NSString * const kBrowserWebViewConfigurationClassName = @"WKWebViewConfiguration";
static NSString * const kBrowserWebsiteDataStoreClassName = @"WKWebsiteDataStore";
static NSString * const kBrowserUserContentControllerClassName = @"WKUserContentController";
static NSString * const kBrowserUserScriptClassName = @"WKUserScript";

static void BrowserEnsureWebKitRuntimeLoaded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (NSClassFromString(kBrowserWebViewClassName) != Nil) {
            return;
        }

        NSArray<NSString *> *candidatePaths = @[
            @"/System/Library/Frameworks/WebKit.framework/WebKit",
            @"/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
            @"/System/Library/StagedFrameworks/Safari/WebKit.framework/WebKit",
        ];

        for (NSString *candidatePath in candidatePaths) {
            if (dlopen(candidatePath.UTF8String, RTLD_NOW | RTLD_GLOBAL) != NULL && NSClassFromString(kBrowserWebViewClassName) != Nil) {
                break;
            }
        }
    });
}

static void BrowserPumpRunLoopUntil(BOOL *done) {
    while (!*done) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
}

static NSString *BrowserStringFromJavaScriptResult(id result) {
    if (result == nil || result == [NSNull null]) {
        return nil;
    }
    if ([result isKindOfClass:[NSString class]]) {
        return result;
    }
    if ([result respondsToSelector:@selector(stringValue)]) {
        return [result stringValue];
    }
    return [result description];
}

static BOOL BrowserSelectorNameMatchesMediaFilter(NSString *selectorName) {
    static NSArray<NSString *> *keywords = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            @"mediasource",
            @"managedmediasource",
            @"sourcebuffer",
            @"media",
            @"video",
            @"inline",
            @"autoplay",
            @"fullscreen",
            @"pictureinpicture",
            @"airplay",
            @"webm",
            @"vp9",
            @"av1",
            @"hls",
            @"mse",
            @"codec",
        ];
    });

    NSString *lowercaseSelectorName = selectorName.lowercaseString;
    for (NSString *keyword in keywords) {
        if ([lowercaseSelectorName containsString:keyword]) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSString *> *BrowserFilteredSelectorNamesForClass(Class klass) {
    if (klass == Nil) {
        return @[];
    }

    NSMutableOrderedSet<NSString *> *selectorNames = [NSMutableOrderedSet orderedSet];
    for (Class currentClass = klass; currentClass != Nil && currentClass != [NSObject class]; currentClass = class_getSuperclass(currentClass)) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(currentClass, &methodCount);
        for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex += 1) {
            SEL selector = method_getName(methods[methodIndex]);
            NSString *selectorName = NSStringFromSelector(selector);
            if (selectorName.length > 0 && BrowserSelectorNameMatchesMediaFilter(selectorName)) {
                [selectorNames addObject:selectorName];
            }
        }
        free(methods);
    }

    return [selectorNames.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSString *BrowserGetterNameFromSetterName(NSString *setterName) {
    if (![setterName hasPrefix:@"set"] || ![setterName hasSuffix:@":"] || setterName.length <= 4) {
        return nil;
    }

    NSString *propertyStem = [setterName substringWithRange:NSMakeRange(3, setterName.length - 4)];
    if (propertyStem.length == 0) {
        return nil;
    }

    NSString *firstCharacter = [[propertyStem substringToIndex:1] lowercaseString];
    if (propertyStem.length == 1) {
        return firstCharacter;
    }

    return [firstCharacter stringByAppendingString:[propertyStem substringFromIndex:1]];
}

static NSString *BrowserBooleanValueDescriptionForObjectAndSelector(id object, NSString *selectorName) {
    if (object == nil || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }

    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature == nil || signature.numberOfArguments != 2) {
        return nil;
    }

    const char *returnType = signature.methodReturnType;
    if (returnType == NULL) {
        return nil;
    }

    if (returnType[0] != 'B' && returnType[0] != 'c') {
        return nil;
    }

    BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    return value ? @"YES" : @"NO";
}

static id BrowserObjectResultForGetter(id object, NSString *selectorName) {
    if (object == nil || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }

    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature == nil || signature.numberOfArguments != 2) {
        return nil;
    }

    const char *returnType = signature.methodReturnType;
    if (returnType == NULL || returnType[0] != '@') {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *BrowserPreviewString(NSString *string, NSUInteger maxLength) {
    if (string.length <= maxLength) {
        return string;
    }
    return [[string substringToIndex:maxLength] stringByAppendingString:@"\n…"];
}

static NSString *BrowserStringValueForKnownSelectors(id object, NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        id result = BrowserObjectResultForGetter(object, selectorName);
        if (result == nil || result == [NSNull null]) {
            continue;
        }
        NSString *stringResult = nil;
        if ([result isKindOfClass:[NSString class]]) {
            stringResult = result;
        } else if ([result respondsToSelector:@selector(stringValue)]) {
            stringResult = [result stringValue];
        } else {
            stringResult = [result description];
        }

        if (stringResult.length > 0) {
            return stringResult;
        }
    }
    return nil;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *BrowserFeatureEntriesForPreferences(id preferences) {
    if (preferences == nil) {
        return @[];
    }

    NSArray<NSString *> *collectionSelectors = @[
        @"_experimentalFeatures",
        @"_internalDebugFeatures",
        @"_features",
    ];

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *entries = [NSMutableArray array];
    for (NSString *collectionSelectorName in collectionSelectors) {
        id collection = BrowserObjectResultForGetter(preferences, collectionSelectorName);
        if (![collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
            continue;
        }

        for (id feature in collection) {
            NSString *name = BrowserStringValueForKnownSelectors(feature, @[@"name", @"key", @"identifier", @"title", @"details"]);
            if (name.length == 0) {
                continue;
            }

            NSString *lowercaseName = name.lowercaseString;
            if (![lowercaseName containsString:@"media"] &&
                ![lowercaseName containsString:@"source"] &&
                ![lowercaseName containsString:@"vp9"] &&
                ![lowercaseName containsString:@"av1"] &&
                ![lowercaseName containsString:@"webm"] &&
                ![lowercaseName containsString:@"video"] &&
                ![lowercaseName containsString:@"mse"] &&
                ![lowercaseName containsString:@"managed"]) {
                continue;
            }

            NSString *enabledValue = BrowserBooleanValueDescriptionForObjectAndSelector(feature, @"enabled");
            if (enabledValue == nil) {
                enabledValue = BrowserBooleanValueDescriptionForObjectAndSelector(feature, @"isEnabled");
            }
            if (enabledValue == nil) {
                enabledValue = @"unknown";
            }

            NSString *key = BrowserStringValueForKnownSelectors(feature, @[@"key", @"identifier"]);
            NSString *source = [collectionSelectorName stringByReplacingOccurrencesOfString:@"_" withString:@""];
            [entries addObject:@{
                @"source": source ?: @"features",
                @"name": name,
                @"enabled": enabledValue,
                @"key": key ?: @"",
            }];
        }
    }

    return entries;
}

static void BrowserSetBooleanSelectorIfAvailable(id object, NSString *selectorName, BOOL value) {
    if (object == nil || selectorName.length == 0) {
        return;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if ([object respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
    }
}

static void BrowserConfigurePrivateMediaPreferences(id configuration) {
    if (configuration == nil) {
        return;
    }

    SEL preferencesSelector = NSSelectorFromString(@"preferences");
    if (![configuration respondsToSelector:preferencesSelector]) {
        return;
    }

    id preferences = ((id (*)(id, SEL))objc_msgSend)(configuration, preferencesSelector);
    if (preferences == nil) {
        return;
    }

    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setMediaSourceEnabled:", YES);
    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setManagedMediaSourceEnabled:", YES);
    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setMediaCapabilityGrantsEnabled:", YES);
    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setVideoQualityIncludesDisplayCompositingEnabled:", YES);
}

static NSString *BrowserYouTubeRequestCaptureScript(void) {
    return
    @"(function(){"
        "if (window.__browserYouTubeHookInstalled) { return; }"
        "window.__browserYouTubeHookInstalled = true;"
        "window.__browserYouTubeIntegrity = window.__browserYouTubeIntegrity || {};"
        "function assignIfPresent(key, value) {"
            "if (value === undefined || value === null) { return; }"
            "var stringValue = String(value || '');"
            "if (!stringValue) { return; }"
            "window.__browserYouTubeIntegrity[key] = stringValue;"
        "}"
        "function capturePayload(payload) {"
            "try {"
                "if (!payload || typeof payload !== 'object') { return; }"
                "if (payload.serviceIntegrityDimensions) {"
                    "assignIfPresent('poToken', payload.serviceIntegrityDimensions.poToken || payload.serviceIntegrityDimensions.po_token);"
                "}"
                "if (payload.context && payload.context.serviceIntegrityDimensions) {"
                    "assignIfPresent('poToken', payload.context.serviceIntegrityDimensions.poToken || payload.context.serviceIntegrityDimensions.po_token);"
                "}"
                "if (payload.context && payload.context.client) {"
                    "assignIfPresent('requestClientName', payload.context.client.clientName);"
                    "assignIfPresent('requestClientVersion', payload.context.client.clientVersion);"
                "}"
            "} catch (error) {}"
        "}"
        "function toHeaderObject(headers) {"
            "var result = {};"
            "try {"
                "if (!headers) { return result; }"
                "if (typeof Headers !== 'undefined' && headers instanceof Headers) {"
                    "headers.forEach(function(value, key) { result[String(key)] = String(value); });"
                    "return result;"
                "}"
                "if (Array.isArray(headers)) {"
                    "headers.forEach(function(entry) {"
                        "if (Array.isArray(entry) && entry.length >= 2) { result[String(entry[0])] = String(entry[1]); }"
                    "});"
                    "return result;"
                "}"
                "if (typeof headers === 'object') {"
                    "Object.keys(headers).forEach(function(key) { result[String(key)] = String(headers[key]); });"
                "}"
            "} catch (error) {}"
            "return result;"
        "}"
        "function rememberRequest(url, body, headers, transport) {"
            "try {"
                "var integrity = window.__browserYouTubeIntegrity;"
                "integrity.lastPlayerRequestURL = String(url || '');"
                "integrity.lastPlayerRequestBody = String(body || '');"
                "integrity.lastPlayerRequestHeaders = JSON.stringify(headers || {});"
                "integrity.lastPlayerRequestTransport = String(transport || '');"
                "if (!integrity.firstPlayerRequestURL) {"
                    "integrity.firstPlayerRequestURL = integrity.lastPlayerRequestURL;"
                    "integrity.firstPlayerRequestBody = integrity.lastPlayerRequestBody;"
                    "integrity.firstPlayerRequestHeaders = integrity.lastPlayerRequestHeaders;"
                    "integrity.firstPlayerRequestTransport = integrity.lastPlayerRequestTransport;"
                "}"
            "} catch (error) {}"
        "}"
        "function captureBodyStringAsync(source, bodyString, headers, transport) {"
            "try {"
                "if (bodyString && bodyString !== '[object ReadableStream]') {"
                    "rememberRequest(source.url || '', bodyString, headers || {}, transport || '');"
                    "try { capturePayload(JSON.parse(bodyString)); } catch (error) {}"
                    "return;"
                "}"
                "if (source && typeof source.clone === 'function' && typeof source.text === 'function') {"
                    "source.clone().text().then(function(text) {"
                        "rememberRequest(source.url || '', text || '', headers || {}, transport || '');"
                        "try { capturePayload(JSON.parse(text || '')); } catch (error) {}"
                    "}).catch(function(){});"
                "}"
            "} catch (error) {}"
        "}"
        "function captureRequest(input, init) {"
            "try {"
                "var url = '';"
                "if (typeof input === 'string') { url = input; }"
                "else if (input && typeof input.url === 'string') { url = input.url; }"
                "if (url.indexOf('/youtubei/v1/player') === -1) { return; }"
                "var body = (init && init.body) || (input && input.body) || null;"
                "var bodyString = '';"
                "if (typeof body === 'string') { bodyString = body; }"
                "else if (body && typeof body === 'object' && typeof body.toString === 'function') { bodyString = String(body); }"
                "var headers = toHeaderObject((init && init.headers) || (input && input.headers) || null);"
                "rememberRequest(url, bodyString, headers, 'fetch');"
                "captureBodyStringAsync((input && typeof input.clone === 'function') ? input : null, bodyString, headers, 'fetch');"
                "if (typeof bodyString !== 'string' || !bodyString || bodyString === '[object ReadableStream]') { return; }"
                "try { capturePayload(JSON.parse(bodyString)); } catch (error) {}"
            "} catch (error) {}"
        "}"
        "function captureXHRRequest(xhr, body) {"
            "try {"
                "var url = String((xhr && xhr.__browserYouTubeURL) || '');"
                "if (url.indexOf('/youtubei/v1/player') === -1) { return; }"
                "var bodyString = '';"
                "if (typeof body === 'string') { bodyString = body; }"
                "else if (body && typeof body === 'object' && typeof body.toString === 'function') { bodyString = String(body); }"
                "var headers = xhr && xhr.__browserYouTubeHeaders ? xhr.__browserYouTubeHeaders : {};"
                "rememberRequest(url, bodyString, headers, 'xhr');"
                "if (typeof bodyString !== 'string' || !bodyString) { return; }"
                "try { capturePayload(JSON.parse(bodyString)); } catch (error) {}"
            "try { capturePayload(JSON.parse(body)); } catch (error) {}"
            "} catch (error) {}"
        "}"
        "var cfg = (window.ytcfg && window.ytcfg.data_) || {};"
        "assignIfPresent('poToken', cfg.PO_TOKEN || cfg.po_token || cfg.POTOKEN);"
        "if (cfg.SERVICE_INTEGRITY_DIMENSIONS) {"
            "assignIfPresent('poToken', cfg.SERVICE_INTEGRITY_DIMENSIONS.poToken || cfg.SERVICE_INTEGRITY_DIMENSIONS.po_token);"
        "}"
        "if (cfg.WEB_PLAYER_CONTEXT_CONFIGS) {"
            "var watchConfig = cfg.WEB_PLAYER_CONTEXT_CONFIGS.WEB_PLAYER_CONTEXT_CONFIG_ID_KEVLAR_WATCH || {};"
            "if (watchConfig.serviceIntegrityDimensions) {"
                "assignIfPresent('poToken', watchConfig.serviceIntegrityDimensions.poToken || watchConfig.serviceIntegrityDimensions.po_token);"
            "}"
        "}"
        "if (window.fetch) {"
            "var originalFetch = window.fetch;"
            "window.fetch = function(input, init) {"
                "captureRequest(input, init);"
                "return originalFetch.apply(this, arguments);"
            "};"
        "}"
        "if (window.XMLHttpRequest && window.XMLHttpRequest.prototype) {"
            "var originalOpen = window.XMLHttpRequest.prototype.open;"
            "var originalSend = window.XMLHttpRequest.prototype.send;"
            "var originalSetRequestHeader = window.XMLHttpRequest.prototype.setRequestHeader;"
            "window.XMLHttpRequest.prototype.open = function(method, url) {"
                "this.__browserYouTubeURL = String(url || '');"
                "this.__browserYouTubeHeaders = {};"
                "return originalOpen.apply(this, arguments);"
            "};"
            "window.XMLHttpRequest.prototype.setRequestHeader = function(key, value) {"
                "try {"
                    "if (!this.__browserYouTubeHeaders) { this.__browserYouTubeHeaders = {}; }"
                    "this.__browserYouTubeHeaders[String(key)] = String(value);"
                "} catch (error) {}"
                "return originalSetRequestHeader.apply(this, arguments);"
            "};"
            "window.XMLHttpRequest.prototype.send = function(body) {"
                "captureXHRRequest(this, body);"
                "return originalSend.apply(this, arguments);"
            "};"
        "}"
    "})();";
}

static void BrowserInstallYouTubeCaptureUserScript(id configuration) {
    if (configuration == nil) {
        return;
    }

    Class userContentControllerClass = NSClassFromString(kBrowserUserContentControllerClassName);
    Class userScriptClass = NSClassFromString(kBrowserUserScriptClassName);
    if (userContentControllerClass == Nil || userScriptClass == Nil) {
        return;
    }

    SEL userContentControllerGetter = NSSelectorFromString(@"userContentController");
    SEL setUserContentControllerSelector = NSSelectorFromString(@"setUserContentController:");
    id userContentController = nil;
    if ([configuration respondsToSelector:userContentControllerGetter]) {
        userContentController = ((id (*)(id, SEL))objc_msgSend)(configuration, userContentControllerGetter);
    }

    if (userContentController == nil && [configuration respondsToSelector:setUserContentControllerSelector]) {
        userContentController = ((id (*)(id, SEL))objc_msgSend)((id)userContentControllerClass, @selector(new));
        ((void (*)(id, SEL, id))objc_msgSend)(configuration, setUserContentControllerSelector, userContentController);
    }

    SEL addUserScriptSelector = NSSelectorFromString(@"addUserScript:");
    SEL userScriptInitializer = NSSelectorFromString(@"initWithSource:injectionTime:forMainFrameOnly:");
    if (userContentController == nil ||
        ![userContentController respondsToSelector:addUserScriptSelector] ||
        ![userScriptClass instancesRespondToSelector:userScriptInitializer]) {
        return;
    }

    id userScript = ((id (*)(id, SEL))objc_msgSend)((id)userScriptClass, @selector(alloc));
    userScript = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(userScript, userScriptInitializer, BrowserYouTubeRequestCaptureScript(), 0, NO);
    if (userScript != nil) {
        ((void (*)(id, SEL, id))objc_msgSend)(userContentController, addUserScriptSelector, userScript);
    }
}

@interface BrowserWebView ()

@property (nullable, nonatomic, strong) id runtimeWebView;
@property (nullable, nonatomic, strong) NSURLRequest *lastRequest;
@property (nullable, nonatomic, copy) NSString *lastTitle;
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic) BOOL loading;

@end

@implementation BrowserWebView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithUserAgent:nil allowsInlineMediaPlayback:YES];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInitWithUserAgent:nil allowsInlineMediaPlayback:YES];
    }
    return self;
}

- (instancetype)initWithUserAgent:(NSString *)userAgent allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        [self commonInitWithUserAgent:userAgent allowsInlineMediaPlayback:allowsInlineMediaPlayback];
    }
    return self;
}

- (void)commonInitWithUserAgent:(NSString *)userAgent allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback {
    BrowserEnsureWebKitRuntimeLoaded();

    self.backgroundColor = UIColor.blackColor;
    self.userAgent = userAgent;
    self.scalesPageToFit = NO;

    Class configurationClass = NSClassFromString(kBrowserWebViewConfigurationClassName);
    Class webViewClass = NSClassFromString(kBrowserWebViewClassName);
    if (configurationClass == Nil || webViewClass == Nil) {
        return;
    }

    id configuration = ((id (*)(id, SEL))objc_msgSend)((id)configurationClass, @selector(new));
    SEL allowsInlineMediaPlaybackSelector = NSSelectorFromString(@"setAllowsInlineMediaPlayback:");
    if (configuration != nil && [configuration respondsToSelector:allowsInlineMediaPlaybackSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, allowsInlineMediaPlaybackSelector, allowsInlineMediaPlayback);
    }
    BrowserConfigurePrivateMediaPreferences(configuration);
    BrowserInstallYouTubeCaptureUserScript(configuration);

    id webViewObject = ((id (*)(id, SEL))objc_msgSend)((id)webViewClass, @selector(alloc));
    SEL initializer = NSSelectorFromString(@"initWithFrame:configuration:");
    webViewObject = ((id (*)(id, SEL, CGRect, id))objc_msgSend)(webViewObject, initializer, self.bounds, configuration);
    if (webViewObject == nil) {
        return;
    }

    self.runtimeWebView = webViewObject;
    UIView *runtimeView = (UIView *)webViewObject;
    runtimeView.frame = self.bounds;
    runtimeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    runtimeView.backgroundColor = UIColor.blackColor;

    SEL navigationDelegateSelector = NSSelectorFromString(@"setNavigationDelegate:");
    if ([webViewObject respondsToSelector:navigationDelegateSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(webViewObject, navigationDelegateSelector, self);
    }

    SEL UIDelegateSelector = NSSelectorFromString(@"setUIDelegate:");
    if ([webViewObject respondsToSelector:UIDelegateSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(webViewObject, UIDelegateSelector, self);
    }

    [self addSubview:runtimeView];
    [self setUserAgent:userAgent];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    ((UIView *)self.runtimeWebView).frame = self.bounds;
    [self applyPageScalingIfNeeded];
}

- (void)setUserInteractionEnabled:(BOOL)userInteractionEnabled {
    [super setUserInteractionEnabled:userInteractionEnabled];

    UIView *runtimeView = (UIView *)self.runtimeWebView;
    runtimeView.userInteractionEnabled = userInteractionEnabled;

    UIScrollView *scrollView = [self scrollView];
    scrollView.userInteractionEnabled = userInteractionEnabled;
}

- (UIScrollView *)scrollView {
    SEL selector = NSSelectorFromString(@"scrollView");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
}

- (NSURL *)currentURL {
    SEL selector = NSSelectorFromString(@"URL");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
}

- (NSURLRequest *)request {
    NSURL *currentURL = [self currentURL];
    if (currentURL != nil) {
        return [NSURLRequest requestWithURL:currentURL];
    }
    return self.lastRequest;
}

- (NSString *)title {
    SEL selector = NSSelectorFromString(@"title");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        return self.lastTitle;
    }
    NSString *title = ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    return title ?: self.lastTitle;
}

- (BOOL)canGoBack {
    SEL selector = NSSelectorFromString(@"canGoBack");
    return self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector] ? ((BOOL (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector) : NO;
}

- (BOOL)canGoForward {
    SEL selector = NSSelectorFromString(@"canGoForward");
    return self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector] ? ((BOOL (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector) : NO;
}

- (void)loadRequest:(NSURLRequest *)request {
    if (request == nil || self.runtimeWebView == nil) {
        return;
    }
    self.lastRequest = request;
    SEL selector = NSSelectorFromString(@"loadRequest:");
    if ([self.runtimeWebView respondsToSelector:selector]) {
        ((id (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, selector, request);
    }
}

- (void)reload {
    SEL selector = NSSelectorFromString(@"reload");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    }
}

- (void)goBack {
    SEL selector = NSSelectorFromString(@"goBack");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    }
}

- (void)goForward {
    SEL selector = NSSelectorFromString(@"goForward");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    }
}

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (script.length == 0 || self.runtimeWebView == nil) {
        return nil;
    }

    SEL selector = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    if (![self.runtimeWebView respondsToSelector:selector]) {
        return nil;
    }

    __block id evaluationResult = nil;
    __block NSError *evaluationError = nil;
    __block BOOL finished = NO;
    ((void (*)(id, SEL, id, id))objc_msgSend)(self.runtimeWebView, selector, script, ^(id result, NSError *error) {
        evaluationResult = result;
        evaluationError = error;
        finished = YES;
    });
    BrowserPumpRunLoopUntil(&finished);

    if (evaluationError != nil) {
        return nil;
    }
    return BrowserStringFromJavaScriptResult(evaluationResult);
}

- (void)pauseAllMediaPlayback {
    if (self.runtimeWebView == nil) {
        return;
    }

    // Prefer WebKit's internal media pause APIs when available.
    SEL pauseWithCompletionHandlerSelector = NSSelectorFromString(@"pauseAllMediaPlaybackWithCompletionHandler:");
    if ([self.runtimeWebView respondsToSelector:pauseWithCompletionHandlerSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, pauseWithCompletionHandlerSelector, nil);
    } else {
        SEL pauseSelector = NSSelectorFromString(@"pauseAllMediaPlayback:");
        if ([self.runtimeWebView respondsToSelector:pauseSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, pauseSelector, nil);
        } else {
            SEL privatePauseSelector = NSSelectorFromString(@"_pauseAllMediaPlayback");
            if ([self.runtimeWebView respondsToSelector:privatePauseSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(self.runtimeWebView, privatePauseSelector);
            }
        }
    }

    // JS fallback for page media elements and common iframe-based players.
    NSString *pauseScript =
        @"(function(){"
            "function safe(fn){ try { fn(); } catch (error) {} }"
            "var media = document.querySelectorAll('video,audio');"
            "for (var i = 0; i < media.length; i++) {"
                "var element = media[i];"
                "safe(function(){ element.pause(); });"
                "safe(function(){ element.autoplay = false; });"
                "safe(function(){ element.removeAttribute('autoplay'); });"
            "}"
            "var iframePlayers = document.querySelectorAll('iframe');"
            "for (var j = 0; j < iframePlayers.length; j++) {"
                "var frame = iframePlayers[j];"
                "var src = String(frame.src || '').toLowerCase();"
                "if (!src) { continue; }"
                "safe(function(){"
                    "if (src.indexOf('youtube.com') !== -1 || src.indexOf('youtube-nocookie.com') !== -1) {"
                        "frame.contentWindow.postMessage(JSON.stringify({event:'command',func:'pauseVideo',args:''}), '*');"
                    "}"
                "});"
                "safe(function(){"
                    "if (src.indexOf('vimeo.com') !== -1) {"
                        "frame.contentWindow.postMessage(JSON.stringify({method:'pause'}), '*');"
                    "}"
                "});"
            "}"
        "})();";
    [self stringByEvaluatingJavaScriptFromString:pauseScript];
}

- (NSString *)runtimeMediaPreferenceReport {
    if (self.runtimeWebView == nil) {
        return @"Runtime web view unavailable.";
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *objectSelectors = @[
        @{@"label": @"WKWebView", @"selector": @""},
        @{@"label": @"Configuration", @"selector": @"configuration"},
        @{@"label": @"Configuration._preferences", @"selector": @"configuration._preferences"},
        @{@"label": @"Configuration.preferences", @"selector": @"configuration.preferences"},
        @{@"label": @"Configuration.defaultWebpagePreferences", @"selector": @"configuration.defaultWebpagePreferences"},
        @{@"label": @"Configuration.websiteDataStore", @"selector": @"configuration.websiteDataStore"},
        @{@"label": @"WKWebView._configuration", @"selector": @"_configuration"},
        @{@"label": @"WKWebView._page", @"selector": @"_page"},
    ];

    NSMutableDictionary<NSValue *, NSString *> *seenObjects = [NSMutableDictionary dictionary];
    NSMutableString *report = [NSMutableString string];

    for (NSDictionary<NSString *, NSString *> *entry in objectSelectors) {
        NSString *label = entry[@"label"] ?: @"Object";
        NSString *selectorPath = entry[@"selector"] ?: @"";
        id currentObject = self.runtimeWebView;

        if (selectorPath.length > 0) {
            NSArray<NSString *> *components = [selectorPath componentsSeparatedByString:@"."];
            for (NSString *component in components) {
                currentObject = BrowserObjectResultForGetter(currentObject, component);
                if (currentObject == nil) {
                    break;
                }
            }
        }

        if (currentObject == nil) {
            [report appendFormat:@"[%@] unavailable\n\n", label];
            continue;
        }

        NSValue *objectKey = [NSValue valueWithNonretainedObject:currentObject];
        NSString *previousLabel = seenObjects[objectKey];
        if (previousLabel != nil) {
            [report appendFormat:@"[%@] same object as %@ (%@)\n\n", label, previousLabel, NSStringFromClass([currentObject class])];
            continue;
        }
        seenObjects[objectKey] = label;

        NSArray<NSString *> *selectorNames = BrowserFilteredSelectorNamesForClass([currentObject class]);
        NSMutableArray<NSString *> *booleanLines = [NSMutableArray array];
        for (NSString *selectorName in selectorNames) {
            NSString *getterName = nil;
            if ([selectorName hasPrefix:@"set"] && [selectorName hasSuffix:@":"]) {
                getterName = BrowserGetterNameFromSetterName(selectorName);
            } else {
                getterName = selectorName;
            }

            NSString *valueDescription = BrowserBooleanValueDescriptionForObjectAndSelector(currentObject, getterName);
            if (valueDescription != nil) {
                [booleanLines addObject:[NSString stringWithFormat:@"%@ = %@", getterName, valueDescription]];
            }
        }

        [report appendFormat:@"[%@] %@\n", label, NSStringFromClass([currentObject class])];
        if (booleanLines.count > 0) {
            [report appendString:@"Boolean getters:\n"];
            for (NSString *line in booleanLines) {
                [report appendFormat:@"- %@\n", line];
            }
        } else {
            [report appendString:@"Boolean getters:\n- none resolved\n"];
        }

        [report appendString:@"Matching selectors:\n"];
        if (selectorNames.count == 0) {
            [report appendString:@"- none\n\n"];
            continue;
        }

        for (NSString *selectorName in selectorNames) {
            [report appendFormat:@"- %@\n", selectorName];
        }

        if ([label isEqualToString:@"Configuration.preferences"]) {
            NSArray<NSDictionary<NSString *, NSString *> *> *featureEntries = BrowserFeatureEntriesForPreferences(currentObject);
            [report appendString:@"Feature entries:\n"];
            if (featureEntries.count == 0) {
                [report appendString:@"- none\n"];
            } else {
                for (NSDictionary<NSString *, NSString *> *featureEntry in featureEntries) {
                    NSString *featureSource = featureEntry[@"source"] ?: @"features";
                    NSString *featureName = featureEntry[@"name"] ?: @"Unknown";
                    NSString *featureEnabled = featureEntry[@"enabled"] ?: @"unknown";
                    NSString *featureKey = featureEntry[@"key"];
                    if (featureKey.length > 0) {
                        [report appendFormat:@"- [%@] %@ (%@) = %@\n", featureSource, featureName, featureKey, featureEnabled];
                    } else {
                        [report appendFormat:@"- [%@] %@ = %@\n", featureSource, featureName, featureEnabled];
                    }
                }
            }
        }
        [report appendString:@"\n"];
    }

    return BrowserPreviewString(report, 24000);
}

- (void)installYouTubeRequestCaptureHook {
    [self stringByEvaluatingJavaScriptFromString:BrowserYouTubeRequestCaptureScript()];
}

- (void)setUserAgent:(NSString *)userAgent {
    _userAgent = [userAgent copy];
    SEL selector = NSSelectorFromString(@"setCustomUserAgent:");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, selector, _userAgent);
    }
}

- (void)setScalesPageToFit:(BOOL)scalesPageToFit {
    _scalesPageToFit = scalesPageToFit;
    [self applyPageScalingIfNeeded];
}

- (void)applyPageScalingIfNeeded {
    if (self.runtimeWebView == nil) {
        return;
    }

    UIScrollView *scrollView = [self scrollView];
    if (scrollView == nil || CGRectIsEmpty(scrollView.bounds)) {
        return;
    }

    CGFloat zoomValue = 1.0;
    if (self.scalesPageToFit) {
        CGFloat contentWidth = scrollView.contentSize.width;
        CGFloat boundsWidth = CGRectGetWidth(scrollView.bounds);
        if (contentWidth > 1.0 && boundsWidth > 1.0) {
            zoomValue = MIN(1.0, MAX(0.25, boundsWidth / contentWidth));
        }
    }

    SEL pageZoomSelector = NSSelectorFromString(@"setPageZoom:");
    if ([self.runtimeWebView respondsToSelector:pageZoomSelector]) {
        ((void (*)(id, SEL, double))objc_msgSend)(self.runtimeWebView, pageZoomSelector, zoomValue);
        return;
    }

    NSString *script = zoomValue == 1.0
        ? @"document.documentElement.style.zoom=''; document.body.style.zoom='';"
        : [NSString stringWithFormat:@"document.documentElement.style.zoom='%0.4f'; document.body.style.zoom='%0.4f';", zoomValue, zoomValue];
    [self stringByEvaluatingJavaScriptFromString:script];
}

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    self.loading = YES;
    if ([self.delegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [self.delegate webViewDidStartLoad:self];
    }
}

- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    self.loading = NO;
    self.lastTitle = [self title];
    self.lastRequest = [self request];
    [self installYouTubeRequestCaptureHook];
    [self applyPageScalingIfNeeded];
    if ([self.delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [self.delegate webViewDidFinishLoad:self];
    }
}

- (void)webView:(id)webView didFailNavigation:(id)navigation withError:(NSError *)error {
    self.loading = NO;
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    self.loading = NO;
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
}

- (void)webViewWebContentProcessDidTerminate:(id)webView {
    self.loading = NO;
}

- (NSURLRequest *)requestFromNavigationAction:(id)navigationAction {
    if (navigationAction == nil) {
        return nil;
    }
    SEL requestSelector = NSSelectorFromString(@"request");
    if (![navigationAction respondsToSelector:requestSelector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(navigationAction, requestSelector);
}

- (NSInteger)navigationTypeFromNavigationAction:(id)navigationAction {
    if (navigationAction == nil) {
        return 0;
    }
    SEL navigationTypeSelector = NSSelectorFromString(@"navigationType");
    if (![navigationAction respondsToSelector:navigationTypeSelector]) {
        return 0;
    }
    return ((NSInteger (*)(id, SEL))objc_msgSend)(navigationAction, navigationTypeSelector);
}

- (void)webView:(id)webView decidePolicyForNavigationAction:(id)navigationAction decisionHandler:(void (^)(NSInteger policy))decisionHandler {
    NSURLRequest *request = [self requestFromNavigationAction:navigationAction];
    NSInteger navigationType = [self navigationTypeFromNavigationAction:navigationAction];
    BOOL isMainFrameRequest = YES;

    SEL targetFrameSelector = NSSelectorFromString(@"targetFrame");
    if ([navigationAction respondsToSelector:targetFrameSelector]) {
        id targetFrame = ((id (*)(id, SEL))objc_msgSend)(navigationAction, targetFrameSelector);
        SEL mainFrameSelector = NSSelectorFromString(@"isMainFrame");
        if (targetFrame != nil && [targetFrame respondsToSelector:mainFrameSelector]) {
            isMainFrameRequest = ((BOOL (*)(id, SEL))objc_msgSend)(targetFrame, mainFrameSelector);
        }
    }

    BOOL shouldAllow = YES;
    if ([self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
        shouldAllow = [self.delegate webView:self shouldStartLoadWithRequest:request navigationType:navigationType];
    }

    if (shouldAllow && isMainFrameRequest && request != nil) {
        self.lastRequest = request;
    }

    if (decisionHandler != nil) {
        decisionHandler(shouldAllow ? 1 : 0);
    }
}

- (id)webView:(id)webView
createWebViewWithConfiguration:(id)configuration
forNavigationAction:(id)navigationAction
windowFeatures:(id)windowFeatures {
    (void)webView;
    (void)configuration;
    (void)windowFeatures;

    NSURLRequest *request = [self requestFromNavigationAction:navigationAction];
    NSInteger navigationType = [self navigationTypeFromNavigationAction:navigationAction];

    BOOL delegateHandlesNewTabRequests = [self.delegate respondsToSelector:@selector(webView:shouldCreateNewTabWithRequest:navigationType:)];
    BOOL handledInTab = NO;
    if (delegateHandlesNewTabRequests) {
        handledInTab = [self.delegate webView:self shouldCreateNewTabWithRequest:request navigationType:navigationType];
    }

    if (!delegateHandlesNewTabRequests && !handledInTab && request != nil) {
        BOOL shouldAllow = YES;
        if ([self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
            shouldAllow = [self.delegate webView:self shouldStartLoadWithRequest:request navigationType:navigationType];
        }
        if (shouldAllow) {
            [self loadRequest:request];
        }
    }

    return nil;
}

+ (id)defaultWebsiteDataStore {
    BrowserEnsureWebKitRuntimeLoaded();
    Class dataStoreClass = NSClassFromString(kBrowserWebsiteDataStoreClassName);
    SEL selector = NSSelectorFromString(@"defaultDataStore");
    if (dataStoreClass == Nil || ![dataStoreClass respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)((id)dataStoreClass, selector);
}

+ (id)defaultCookieStore {
    id dataStore = [self defaultWebsiteDataStore];
    SEL selector = NSSelectorFromString(@"httpCookieStore");
    if (dataStore == nil || ![dataStore respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(dataStore, selector);
}

+ (NSArray<NSHTTPCookie *> *)allCookies {
    id cookieStore = [self defaultCookieStore];
    SEL selector = NSSelectorFromString(@"getAllCookies:");
    if (cookieStore == nil || ![cookieStore respondsToSelector:selector]) {
        return NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies ?: @[];
    }

    __block NSArray<NSHTTPCookie *> *cookies = nil;
    __block BOOL finished = NO;
    ((void (*)(id, SEL, id))objc_msgSend)(cookieStore, selector, ^(NSArray<NSHTTPCookie *> *fetchedCookies) {
        cookies = fetchedCookies;
        finished = YES;
    });
    BrowserPumpRunLoopUntil(&finished);
    return cookies ?: @[];
}

+ (NSData *)cookieDataRepresentation {
    NSArray<NSHTTPCookie *> *cookies = [self allCookies];
    NSError *error = nil;
    NSData *cookieData = [NSKeyedArchiver archivedDataWithRootObject:cookies requiringSecureCoding:NO error:&error];
    return error == nil ? cookieData : nil;
}

+ (void)restoreCookiesFromData:(NSData *)cookieData {
    if (cookieData.length == 0) {
        return;
    }

    NSError *error = nil;
    NSSet *allowedClasses = [NSSet setWithObjects:[NSArray class], [NSHTTPCookie class], nil];
    NSArray<NSHTTPCookie *> *cookies = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedClasses fromData:cookieData error:&error];
    if (![cookies isKindOfClass:[NSArray class]]) {
        return;
    }

    id cookieStore = [self defaultCookieStore];
    SEL selector = NSSelectorFromString(@"setCookie:completionHandler:");
    if (cookieStore == nil || ![cookieStore respondsToSelector:selector]) {
        for (NSHTTPCookie *cookie in cookies) {
            [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookie:cookie];
        }
        return;
    }

    __block NSInteger remainingCount = cookies.count;
    __block BOOL finished = cookies.count == 0;
    for (NSHTTPCookie *cookie in cookies) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(cookieStore, selector, cookie, ^{
            remainingCount -= 1;
            finished = remainingCount == 0;
        });
    }
    BrowserPumpRunLoopUntil(&finished);
}

+ (NSSet<NSString *> *)allWebsiteDataTypes {
    Class dataStoreClass = NSClassFromString(kBrowserWebsiteDataStoreClassName);
    SEL selector = NSSelectorFromString(@"allWebsiteDataTypes");
    if (dataStoreClass == Nil || ![dataStoreClass respondsToSelector:selector]) {
        return [NSSet set];
    }
    return ((id (*)(id, SEL))objc_msgSend)((id)dataStoreClass, selector);
}

+ (void)removeWebsiteDataTypes:(NSSet<NSString *> *)websiteDataTypes completion:(void (^)(void))completion {
    id dataStore = [self defaultWebsiteDataStore];
    SEL selector = NSSelectorFromString(@"removeDataOfTypes:modifiedSince:completionHandler:");
    if (dataStore == nil || ![dataStore respondsToSelector:selector]) {
        if (completion != nil) {
            completion();
        }
        return;
    }

    NSDate *beginningOfTime = [NSDate dateWithTimeIntervalSince1970:0];
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(dataStore, selector, websiteDataTypes, beginningOfTime, ^{
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

+ (void)clearCachedDataWithCompletion:(void (^)(void))completion {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSMutableSet<NSString *> *websiteDataTypes = [[self allWebsiteDataTypes] mutableCopy];
    for (NSString *dataType in websiteDataTypes.allObjects) {
        if ([dataType.lowercaseString containsString:@"cookie"]) {
            [websiteDataTypes removeObject:dataType];
        }
    }

    [self removeWebsiteDataTypes:websiteDataTypes completion:completion];
}

+ (void)clearCookiesWithCompletion:(void (^)(void))completion {
    id cookieStore = [self defaultCookieStore];
    SEL getAllCookiesSelector = NSSelectorFromString(@"getAllCookies:");
    SEL deleteCookieSelector = NSSelectorFromString(@"deleteCookie:completionHandler:");
    if (cookieStore == nil || ![cookieStore respondsToSelector:getAllCookiesSelector] || ![cookieStore respondsToSelector:deleteCookieSelector]) {
        NSHTTPCookieStorage *storage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        for (NSHTTPCookie *cookie in storage.cookies) {
            [storage deleteCookie:cookie];
        }
        if (completion != nil) {
            completion();
        }
        return;
    }

    ((void (*)(id, SEL, id))objc_msgSend)(cookieStore, getAllCookiesSelector, ^(NSArray<NSHTTPCookie *> *cookies) {
        if (cookies.count == 0) {
            if (completion != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion();
                });
            }
            return;
        }

        __block NSInteger remainingCount = cookies.count;
        for (NSHTTPCookie *cookie in cookies) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(cookieStore, deleteCookieSelector, cookie, ^{
                remainingCount -= 1;
                if (remainingCount == 0 && completion != nil) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion();
                    });
                }
            });
        }
    });
}

+ (void)resetWebsiteDataWithCompletion:(void (^)(void))completion {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [self removeWebsiteDataTypes:[self allWebsiteDataTypes] completion:completion];
}

@end
