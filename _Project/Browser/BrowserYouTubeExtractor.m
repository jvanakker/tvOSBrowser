#import "BrowserYouTubeExtractor.h"

#import "BrowserWebView.h"

NSString * const BrowserYouTubeExtractorErrorDomain = @"BrowserYouTubeExtractorErrorDomain";

static NSString * const kBrowserYouTubeSafariUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15";
static NSString * const kBrowserYouTubeFallbackClientVersion = @"2.20260114.08.00";
static NSString * const kBrowserYouTubeExtractorLogPrefix = @"[YouTubeExtractor]";
static NSString * const kBrowserYouTubeIOSUserAgent = @"com.google.ios.youtube/19.09.3 (iPhone16,2; U; CPU iOS 17_4_1 like Mac OS X;)";
static NSString * const kBrowserYouTubeIOSClientVersion = @"19.09.3";
static NSString * const kBrowserYouTubeMWEBClientVersion = @"2.20260303.00.00";
static NSString * const kBrowserYouTubeTVUserAgent = @"Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version";
static NSString * const kBrowserYouTubeTVClientVersion = @"7.20210204";
static NSString * const kBrowserYouTubeTVEmbeddedClientVersion = @"2.0";

@interface BrowserYouTubeExtractionResult ()

@property (nonatomic, strong, readwrite) NSURL *playbackURL;
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *sourceDescription;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *requestHeaders;

@end

@implementation BrowserYouTubeExtractionResult

- (instancetype)initWithPlaybackURL:(NSURL *)playbackURL
                              title:(NSString *)title
                  sourceDescription:(NSString *)sourceDescription
                     requestHeaders:(NSDictionary<NSString *,NSString *> *)requestHeaders {
    self = [super init];
    if (self) {
        _playbackURL = playbackURL;
        _title = [title copy] ?: @"";
        _sourceDescription = [sourceDescription copy] ?: @"";
        _requestHeaders = [requestHeaders copy] ?: @{};
    }
    return self;
}

@end

@interface BrowserYouTubeExtractor ()

@property (nonatomic, strong) NSURLSession *session;

@end

@implementation BrowserYouTubeExtractor

- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"%@ %@", kBrowserYouTubeExtractorLogPrefix, message);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (BOOL)canExtractFromPageURL:(NSURL *)pageURL {
    NSString *host = pageURL.host.lowercaseString;
    if (host.length == 0) {
        return NO;
    }
    return [host containsString:@"youtube.com"] || [host isEqualToString:@"youtu.be"] || [host hasSuffix:@".youtube.com"];
}

- (NSError *)errorWithCode:(BrowserYouTubeExtractorErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:BrowserYouTubeExtractorErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"Unknown YouTube extractor error."}];
}

- (NSString *)videoIDFromPageURL:(NSURL *)pageURL {
    if (pageURL == nil) {
        return nil;
    }

    NSString *host = pageURL.host.lowercaseString ?: @"";
    if ([host isEqualToString:@"youtu.be"]) {
        NSString *path = pageURL.path ?: @"";
        NSString *videoID = [path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
        return videoID.length > 0 ? videoID : nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:pageURL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *queryItem in components.queryItems ?: @[]) {
        if ([queryItem.name isEqualToString:@"v"] && queryItem.value.length > 0) {
            return queryItem.value;
        }
    }

    NSArray<NSString *> *pathComponents = [pageURL.pathComponents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *value, __unused NSDictionary *bindings) {
        return ![value isEqualToString:@"/"] && value.length > 0;
    }]];
    if (pathComponents.count >= 2) {
        NSString *prefix = pathComponents[0];
        if ([prefix isEqualToString:@"shorts"] || [prefix isEqualToString:@"live"] || [prefix isEqualToString:@"embed"] || [prefix isEqualToString:@"v"]) {
            return pathComponents[1];
        }
    }

    return nil;
}

- (NSDictionary *)JSONObjectFromJavaScriptString:(NSString *)string {
    if (string.length == 0) {
        return nil;
    }

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return object;
}

- (NSDictionary *)pageConfigurationFromWebView:(BrowserWebView *)webView {
    NSString *script = @"(function(){"
                        "var cfg=(window.ytcfg&&window.ytcfg.data_)||{};"
                        "var response=window.ytInitialPlayerResponse||null;"
                        "if (!response && window.ytplayer && window.ytplayer.config && window.ytplayer.config.args && window.ytplayer.config.args.player_response) {"
                            "try { response=JSON.parse(window.ytplayer.config.args.player_response); } catch (error) {}"
                        "}"
                        "return JSON.stringify({"
                            "apiKey: String(cfg.INNERTUBE_API_KEY || ''),"
                            "clientVersion: String(cfg.INNERTUBE_CLIENT_VERSION || ''),"
                            "visitorData: String(cfg.VISITOR_DATA || ''),"
                            "poToken: String(((window.__browserYouTubeIntegrity||{}).poToken) || (cfg.PO_TOKEN || '') || ((cfg.SERVICE_INTEGRITY_DIMENSIONS||{}).poToken || (cfg.SERVICE_INTEGRITY_DIMENSIONS||{}).po_token || '') || ((((cfg.WEB_PLAYER_CONTEXT_CONFIGS||{}).WEB_PLAYER_CONTEXT_CONFIG_ID_KEVLAR_WATCH||{}).serviceIntegrityDimensions||{}).poToken || '') || ''),"
                            "requestClientName: String(((window.__browserYouTubeIntegrity||{}).requestClientName) || ''),"
                            "requestClientVersion: String(((window.__browserYouTubeIntegrity||{}).requestClientVersion) || ''),"
                            "firstPlayerRequestURL: String(((window.__browserYouTubeIntegrity||{}).firstPlayerRequestURL) || ''),"
                            "firstPlayerRequestBody: String(((window.__browserYouTubeIntegrity||{}).firstPlayerRequestBody) || ''),"
                            "firstPlayerRequestHeaders: String(((window.__browserYouTubeIntegrity||{}).firstPlayerRequestHeaders) || ''),"
                            "firstPlayerRequestTransport: String(((window.__browserYouTubeIntegrity||{}).firstPlayerRequestTransport) || ''),"
                            "lastPlayerRequestURL: String(((window.__browserYouTubeIntegrity||{}).lastPlayerRequestURL) || ''),"
                            "lastPlayerRequestBody: String(((window.__browserYouTubeIntegrity||{}).lastPlayerRequestBody) || ''),"
                            "lastPlayerRequestHeaders: String(((window.__browserYouTubeIntegrity||{}).lastPlayerRequestHeaders) || ''),"
                            "lastPlayerRequestTransport: String(((window.__browserYouTubeIntegrity||{}).lastPlayerRequestTransport) || ''),"
                            "sts: Number(cfg.STS || 0),"
                            "hl: String(cfg.HL || 'en'),"
                            "gl: String(cfg.GL || 'US'),"
                            "pageTitle: String((response && response.videoDetails && response.videoDetails.title) || document.title || ''),"
                            "pageHlsManifestUrl: String((response && response.streamingData && response.streamingData.hlsManifestUrl) || '')"
                        "});"
                       "})()";
    NSString *resultString = [webView stringByEvaluatingJavaScriptFromString:script];
    NSDictionary *configuration = [self JSONObjectFromJavaScriptString:resultString];
    NSString *firstBody = [configuration[@"firstPlayerRequestBody"] isKindOfClass:[NSString class]] ? configuration[@"firstPlayerRequestBody"] : @"";
    NSString *lastBody = [configuration[@"lastPlayerRequestBody"] isKindOfClass:[NSString class]] ? configuration[@"lastPlayerRequestBody"] : @"";
    NSString *firstHeaders = [configuration[@"firstPlayerRequestHeaders"] isKindOfClass:[NSString class]] ? configuration[@"firstPlayerRequestHeaders"] : @"";
    NSString *lastHeaders = [configuration[@"lastPlayerRequestHeaders"] isKindOfClass:[NSString class]] ? configuration[@"lastPlayerRequestHeaders"] : @"";
    [self log:@"page config apiKey=%@ clientVersion=%@ requestClient=%@/%@ sts=%@ visitorData=%@ poToken=%@ firstRequest=%@/%@ headers=%@ serviceIntegrity=%@ lastRequest=%@/%@ headers=%@ serviceIntegrity=%@ pageHLS=%@ title=%@",
     [configuration[@"apiKey"] length] > 0 ? @"yes" : @"no",
     configuration[@"clientVersion"] ?: @"",
     configuration[@"requestClientName"] ?: @"",
     configuration[@"requestClientVersion"] ?: @"",
     configuration[@"sts"] ?: @0,
     [configuration[@"visitorData"] length] > 0 ? @"yes" : @"no",
     [configuration[@"poToken"] length] > 0 ? @"yes" : @"no",
     configuration[@"firstPlayerRequestTransport"] ?: @"",
     [configuration[@"firstPlayerRequestURL"] length] > 0 ? @"yes" : @"no",
     firstHeaders.length > 0 ? @"yes" : @"no",
     [firstBody containsString:@"serviceIntegrityDimensions"] ? @"yes" : @"no",
     configuration[@"lastPlayerRequestTransport"] ?: @"",
     [configuration[@"lastPlayerRequestURL"] length] > 0 ? @"yes" : @"no",
     lastHeaders.length > 0 ? @"yes" : @"no",
     [lastBody containsString:@"serviceIntegrityDimensions"] ? @"yes" : @"no",
     configuration[@"pageHlsManifestUrl"] ?: @"",
     configuration[@"pageTitle"] ?: @""];
    if (firstBody.length > 0) {
        [self log:@"first player request body=%@", firstBody];
    }
    if (firstHeaders.length > 0) {
        [self log:@"first player request headers=%@", firstHeaders];
    }
    if (lastBody.length > 0 && ![lastBody isEqualToString:firstBody]) {
        [self log:@"last player request body=%@", lastBody];
    }
    if (lastHeaders.length > 0 && ![lastHeaders isEqualToString:firstHeaders]) {
        [self log:@"last player request headers=%@", lastHeaders];
    }
    return configuration;
}

- (NSURL *)URLFromPotentialString:(NSString *)potentialURLString {
    if (![potentialURLString isKindOfClass:[NSString class]] || potentialURLString.length == 0) {
        return nil;
    }
    NSURL *URL = [NSURL URLWithString:potentialURLString];
    NSString *scheme = URL.scheme.lowercaseString;
    if (URL == nil || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return nil;
    }
    return URL;
}

- (NSDictionary<NSString *, NSString *> *)playbackRequestHeadersForPageURL:(NSURL *)pageURL {
    NSString *originHost = pageURL.host.length > 0 ? pageURL.host : @"www.youtube.com";
    NSString *originScheme = pageURL.scheme.length > 0 ? pageURL.scheme : @"https";
    return @{
        @"User-Agent": kBrowserYouTubeSafariUserAgent,
        @"Referer": pageURL.absoluteString ?: @"https://www.youtube.com/watch",
        @"Origin": [NSString stringWithFormat:@"%@://%@", originScheme, originHost],
        @"Accept": @"*/*",
        @"Accept-Language": @"en-US,en;q=0.9",
    };
}

- (NSArray<NSDictionary *> *)clientProfilesForPageConfiguration:(NSDictionary *)pageConfiguration {
    NSString *webClientVersion = [pageConfiguration[@"clientVersion"] isKindOfClass:[NSString class]] && [pageConfiguration[@"clientVersion"] length] > 0
        ? pageConfiguration[@"clientVersion"]
        : kBrowserYouTubeFallbackClientVersion;
    NSString *hl = [pageConfiguration[@"hl"] isKindOfClass:[NSString class]] && [pageConfiguration[@"hl"] length] > 0 ? pageConfiguration[@"hl"] : @"en";
    NSString *gl = [pageConfiguration[@"gl"] isKindOfClass:[NSString class]] && [pageConfiguration[@"gl"] length] > 0 ? pageConfiguration[@"gl"] : @"US";

    return @[
        @{
            @"label": @"web",
            @"clientName": @"WEB",
            @"clientVersion": webClientVersion,
            @"clientHeaderName": @"1",
            @"userAgent": kBrowserYouTubeSafariUserAgent,
            @"hl": hl,
            @"gl": gl,
            @"sendOrigin": @YES,
            @"sendReferer": @YES,
        },
        @{
            @"label": @"mweb",
            @"clientName": @"MWEB",
            @"clientVersion": kBrowserYouTubeMWEBClientVersion,
            @"clientHeaderName": @"2",
            @"userAgent": kBrowserYouTubeSafariUserAgent,
            @"hl": hl,
            @"gl": gl,
            @"sendOrigin": @YES,
            @"sendReferer": @YES,
        },
        @{
            @"label": @"web_safari",
            @"clientName": @"WEB",
            @"clientVersion": webClientVersion,
            @"clientHeaderName": @"1",
            @"userAgent": kBrowserYouTubeSafariUserAgent,
            @"hl": hl,
            @"gl": gl,
            @"sendOrigin": @YES,
            @"sendReferer": @YES,
        },
        @{
            @"label": @"ios",
            @"clientName": @"IOS",
            @"clientVersion": kBrowserYouTubeIOSClientVersion,
            @"clientHeaderName": @"5",
            @"userAgent": kBrowserYouTubeIOSUserAgent,
            @"hl": hl,
            @"gl": gl,
            @"osName": @"iPhone",
            @"osVersion": @"17.4.1.21E236",
            @"deviceModel": @"iPhone16,2",
            @"sendOrigin": @NO,
            @"sendReferer": @NO,
        },
        @{
            @"label": @"tv",
            @"clientName": @"TVHTML5",
            @"clientVersion": kBrowserYouTubeTVClientVersion,
            @"clientHeaderName": @"7",
            @"userAgent": kBrowserYouTubeTVUserAgent,
            @"hl": hl,
            @"gl": gl,
            @"sendOrigin": @NO,
            @"sendReferer": @NO,
        },
        @{
            @"label": @"tv_embedded",
            @"clientName": @"TVHTML5_SIMPLY_EMBEDDED_PLAYER",
            @"clientVersion": kBrowserYouTubeTVEmbeddedClientVersion,
            @"clientHeaderName": @"85",
            @"userAgent": kBrowserYouTubeTVUserAgent,
            @"hl": hl,
            @"gl": gl,
            @"sendOrigin": @NO,
            @"sendReferer": @NO,
        },
    ];
}

- (NSDictionary *)capturedPlayerRequestBodyFromPageConfiguration:(NSDictionary *)pageConfiguration {
    NSString *bodyString = [pageConfiguration[@"firstPlayerRequestBody"] isKindOfClass:[NSString class]] ? pageConfiguration[@"firstPlayerRequestBody"] : @"";
    NSDictionary *body = [self JSONObjectFromJavaScriptString:bodyString];
    return [body isKindOfClass:[NSDictionary class]] ? body : nil;
}

- (NSDictionary<NSString *, NSString *> *)capturedPlayerRequestHeadersFromPageConfiguration:(NSDictionary *)pageConfiguration {
    NSString *headersString = [pageConfiguration[@"firstPlayerRequestHeaders"] isKindOfClass:[NSString class]] ? pageConfiguration[@"firstPlayerRequestHeaders"] : @"";
    NSDictionary *headers = [self JSONObjectFromJavaScriptString:headersString];
    if (![headers isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSMutableDictionary<NSString *, NSString *> *normalizedHeaders = [NSMutableDictionary dictionary];
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, __unused BOOL *stop) {
        if ([key isKindOfClass:[NSString class]]) {
            normalizedHeaders[(NSString *)key] = [obj isKindOfClass:[NSString class]] ? obj : [obj description];
        }
    }];
    return normalizedHeaders;
}

- (BOOL)cookie:(NSHTTPCookie *)cookie matchesHost:(NSString *)host {
    if (cookie == nil || host.length == 0) {
        return NO;
    }

    NSString *cookieDomain = cookie.domain.lowercaseString ?: @"";
    NSString *lowercaseHost = host.lowercaseString;
    if (cookieDomain.length == 0) {
        return NO;
    }

    if ([cookieDomain hasPrefix:@"."]) {
        cookieDomain = [cookieDomain substringFromIndex:1];
    }

    return [lowercaseHost isEqualToString:cookieDomain] || [lowercaseHost hasSuffix:[@"." stringByAppendingString:cookieDomain]];
}

- (NSArray<NSHTTPCookie *> *)cookiesForPlaybackURL:(NSURL *)playbackURL pageURL:(NSURL *)pageURL {
    NSMutableArray<NSHTTPCookie *> *matchingCookies = [NSMutableArray array];
    NSMutableSet<NSString *> *seenCookieKeys = [NSMutableSet set];
    NSArray<NSHTTPCookie *> *allCookies = [BrowserWebView allCookies];
    NSString *pageHost = pageURL.host.lowercaseString ?: @"";
    NSString *playbackHost = playbackURL.host.lowercaseString ?: @"";

    for (NSHTTPCookie *cookie in allCookies) {
        BOOL matches = [self cookie:cookie matchesHost:pageHost] ||
        [self cookie:cookie matchesHost:playbackHost] ||
        [self cookie:cookie matchesHost:@"youtube.com"] ||
        [self cookie:cookie matchesHost:@"googlevideo.com"];
        if (!matches) {
            continue;
        }

        NSString *cookieKey = [NSString stringWithFormat:@"%@|%@|%@", cookie.domain ?: @"", cookie.path ?: @"", cookie.name ?: @""];
        if ([seenCookieKeys containsObject:cookieKey]) {
            continue;
        }
        [seenCookieKeys addObject:cookieKey];
        [matchingCookies addObject:cookie];
    }

    return matchingCookies;
}

- (void)validatePlaybackResult:(BrowserYouTubeExtractionResult *)result
                       pageURL:(NSURL *)pageURL
                    completion:(void (^)(BrowserYouTubeExtractionResult * _Nullable result,
                                         NSError * _Nullable error))completion {
    if (result.playbackURL == nil) {
        completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeNoPlayableURL description:@"No playback URL was available to validate."]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:result.playbackURL];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20.0;
    [result.requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
        if (value.length > 0) {
            [request setValue:value forHTTPHeaderField:key];
        }
    }];

    NSArray<NSHTTPCookie *> *cookies = [self cookiesForPlaybackURL:result.playbackURL pageURL:pageURL];
    NSString *cookieHeader = nil;
    if (cookies.count > 0) {
        NSDictionary<NSString *, NSString *> *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        cookieHeader = cookieHeaders[@"Cookie"];
        if (cookieHeader.length > 0) {
            [request setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
        }
    }

    [self log:@"preflight playback url=%@ source=%@ headers=%@ cookies=%lu",
     result.playbackURL.absoluteString ?: @"",
     result.sourceDescription ?: @"",
     result.requestHeaders ?: @{},
     (unsigned long)cookies.count];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error != nil) {
            [self log:@"preflight network error %@", error];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeNetworkFailure description:error.localizedDescription]);
            });
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSString *contentType = [httpResponse valueForHTTPHeaderField:@"Content-Type"] ?: @"";
        NSString *bodyPreview = data.length > 0 ? [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN((NSUInteger)200, data.length))] encoding:NSUTF8StringEncoding] : @"";
        [self log:@"preflight response status=%ld contentType=%@ bytes=%lu preview=%@",
         (long)httpResponse.statusCode,
         contentType,
         (unsigned long)data.length,
         bodyPreview ?: @""];

        if (![httpResponse isKindOfClass:[NSHTTPURLResponse class]] || httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSString *description = httpResponse.statusCode == 403
                ? @"YouTube returned HTTP 403 for the extracted playback URL before AVPlayer even tried to play it. This usually means the URL still needs a different client context or a PO token."
                : @"The extracted playback URL could not be fetched successfully.";
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeInvalidResponse description:description]);
            });
            return;
        }

        NSURL *manifestURL = result.playbackURL;
        NSString *manifestString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        NSMutableArray<NSString *> *nonCommentEntries = [NSMutableArray array];
        [manifestString enumerateLinesUsingBlock:^(NSString *line, __unused BOOL *stop) {
            NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmedLine.length > 0 && ![trimmedLine hasPrefix:@"#"]) {
                [nonCommentEntries addObject:trimmedLine];
            }
        }];

        NSString *variantEntry = nonCommentEntries.firstObject;
        if (variantEntry.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result, nil);
            });
            return;
        }

        NSURL *variantURL = [NSURL URLWithString:variantEntry relativeToURL:manifestURL].absoluteURL;
        if (variantURL == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result, nil);
            });
            return;
        }

        NSMutableURLRequest *variantRequest = [NSMutableURLRequest requestWithURL:variantURL];
        variantRequest.HTTPMethod = @"GET";
        variantRequest.timeoutInterval = 20.0;
        [result.requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
            if (value.length > 0) {
                [variantRequest setValue:value forHTTPHeaderField:key];
            }
        }];
        if (cookieHeader.length > 0) {
            [variantRequest setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
        }

        NSURLSessionDataTask *variantTask = [self.session dataTaskWithRequest:variantRequest completionHandler:^(NSData *variantData, NSURLResponse *variantResponse, NSError *variantError) {
            if (variantError != nil) {
                [self log:@"variant preflight error %@", variantError];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeNetworkFailure description:variantError.localizedDescription]);
                });
                return;
            }

            NSHTTPURLResponse *variantHTTPResponse = (NSHTTPURLResponse *)variantResponse;
            NSString *variantString = [[NSString alloc] initWithData:variantData encoding:NSUTF8StringEncoding] ?: @"";
            NSMutableArray<NSString *> *segmentEntries = [NSMutableArray array];
            [variantString enumerateLinesUsingBlock:^(NSString *line, __unused BOOL *stop) {
                NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmedLine.length > 0 && ![trimmedLine hasPrefix:@"#"]) {
                    [segmentEntries addObject:trimmedLine];
                }
            }];

            NSString *segmentEntry = segmentEntries.firstObject;
            NSURL *segmentURL = [NSURL URLWithString:segmentEntry relativeToURL:variantURL].absoluteURL;
            [self log:@"variant preflight status=%ld firstSegment=%@",
             (long)variantHTTPResponse.statusCode,
             segmentURL.absoluteString ?: @""];
            if (segmentURL == nil || variantHTTPResponse.statusCode < 200 || variantHTTPResponse.statusCode >= 300) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeInvalidResponse description:@"YouTube HLS variant playlist could not be validated."]);
                });
                return;
            }

            NSMutableURLRequest *segmentRequest = [NSMutableURLRequest requestWithURL:segmentURL];
            segmentRequest.HTTPMethod = @"GET";
            segmentRequest.timeoutInterval = 20.0;
            [segmentRequest setValue:@"bytes=0-2047" forHTTPHeaderField:@"Range"];
            [result.requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
                if (value.length > 0) {
                    NSString *host = segmentURL.host.lowercaseString ?: @"";
                    if ([host containsString:@"googlevideo.com"] && [key caseInsensitiveCompare:@"Origin"] == NSOrderedSame) {
                        return;
                    }
                    [segmentRequest setValue:value forHTTPHeaderField:key];
                }
            }];

            NSArray<NSHTTPCookie *> *segmentCookies = [self cookiesForPlaybackURL:segmentURL pageURL:pageURL];
            NSDictionary<NSString *, NSString *> *segmentCookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:segmentCookies];
            NSString *segmentCookieHeader = segmentCookieHeaders[@"Cookie"];
            if (segmentCookieHeader.length > 0) {
                [segmentRequest setValue:segmentCookieHeader forHTTPHeaderField:@"Cookie"];
            }

            NSURLSessionDataTask *segmentTask = [self.session dataTaskWithRequest:segmentRequest completionHandler:^(NSData *segmentData, NSURLResponse *segmentResponse, NSError *segmentError) {
                if (segmentError != nil) {
                    [self log:@"segment preflight error %@", segmentError];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeNetworkFailure description:segmentError.localizedDescription]);
                    });
                    return;
                }

                NSHTTPURLResponse *segmentHTTPResponse = (NSHTTPURLResponse *)segmentResponse;
                NSString *segmentType = [segmentHTTPResponse valueForHTTPHeaderField:@"Content-Type"] ?: @"";
                [self log:@"segment preflight status=%ld contentType=%@ bytes=%lu url=%@",
                 (long)segmentHTTPResponse.statusCode,
                 segmentType,
                 (unsigned long)segmentData.length,
                 segmentURL.absoluteString ?: @""];

                if (segmentHTTPResponse.statusCode < 200 || segmentHTTPResponse.statusCode >= 299) {
                    NSString *description = segmentHTTPResponse.statusCode == 403
                        ? @"YouTube allowed the manifest but rejected the first media segment for this client path."
                        : @"YouTube media segment validation failed.";
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeInvalidResponse description:description]);
                    });
                    return;
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(result, nil);
                });
            }];
            [segmentTask resume];
        }];
        [variantTask resume];
    }];
    [task resume];
}

- (BrowserYouTubeExtractionResult *)resultFromFormats:(NSArray *)formats title:(NSString *)title source:(NSString *)sourcePrefix {
    if (![formats isKindOfClass:[NSArray class]]) {
        [self log:@"no candidate formats for source=%@", sourcePrefix];
        return nil;
    }

    NSDictionary *bestFormat = nil;
    NSInteger bestHeight = -1;
    NSInteger bestBitrate = -1;
    for (id entry in formats) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *format = (NSDictionary *)entry;
        NSURL *url = [self URLFromPotentialString:format[@"url"]];
        if (url == nil) {
            if ([format[@"signatureCipher"] isKindOfClass:[NSString class]] || [format[@"cipher"] isKindOfClass:[NSString class]]) {
                [self log:@"skipping ciphered format id=%@ quality=%@ because signature decipher is not implemented yet",
                 format[@"itag"] ?: format[@"format_id"] ?: @"",
                 format[@"qualityLabel"] ?: @""];
            }
            continue;
        }

        NSString *mimeType = [format[@"mimeType"] isKindOfClass:[NSString class]] ? format[@"mimeType"] : @"";
        if (![mimeType containsString:@"video/mp4"] && mimeType.length > 0) {
            continue;
        }

        NSInteger height = [format[@"height"] respondsToSelector:@selector(integerValue)] ? [format[@"height"] integerValue] : 0;
        NSInteger bitrate = [format[@"bitrate"] respondsToSelector:@selector(integerValue)] ? [format[@"bitrate"] integerValue] : 0;
        if (bestFormat == nil || height > bestHeight || (height == bestHeight && bitrate > bestBitrate)) {
            bestFormat = format;
            bestHeight = height;
            bestBitrate = bitrate;
        }
    }

    if (bestFormat == nil) {
        [self log:@"no playable muxed mp4 format found for source=%@", sourcePrefix];
        return nil;
    }

    NSURL *playbackURL = [self URLFromPotentialString:bestFormat[@"url"]];
    if (playbackURL == nil) {
        return nil;
    }

    NSString *qualityLabel = [bestFormat[@"qualityLabel"] isKindOfClass:[NSString class]] ? bestFormat[@"qualityLabel"] : @"";
    NSString *source = qualityLabel.length > 0 ? [NSString stringWithFormat:@"%@ %@", sourcePrefix, qualityLabel] : sourcePrefix;
    [self log:@"selected format source=%@ itag=%@ quality=%@ mime=%@ url=%@",
     source,
     bestFormat[@"itag"] ?: bestFormat[@"format_id"] ?: @"",
     qualityLabel,
     bestFormat[@"mimeType"] ?: @"",
     playbackURL.absoluteString ?: @""];
    return [[BrowserYouTubeExtractionResult alloc] initWithPlaybackURL:playbackURL
                                                                 title:title
                                                     sourceDescription:source
                                                        requestHeaders:@{
                                                            @"User-Agent": kBrowserYouTubeSafariUserAgent,
                                                            @"Accept": @"*/*",
                                                            @"Accept-Language": @"en-US,en;q=0.9",
                                                        }];
}

- (BrowserYouTubeExtractionResult *)resultFromPlayerResponse:(NSDictionary *)playerResponse
                                               fallbackTitle:(NSString *)fallbackTitle
                                                     pageURL:(NSURL *)pageURL
                                                 sourceLabel:(NSString *)sourceLabel
                                              requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders {
    if (![playerResponse isKindOfClass:[NSDictionary class]]) {
        [self log:@"player response was not a dictionary"];
        return nil;
    }

    NSDictionary *playabilityStatus = [playerResponse[@"playabilityStatus"] isKindOfClass:[NSDictionary class]] ? playerResponse[@"playabilityStatus"] : nil;
    NSString *status = [playabilityStatus[@"status"] isKindOfClass:[NSString class]] ? playabilityStatus[@"status"] : @"";
    NSString *reason = [playabilityStatus[@"reason"] isKindOfClass:[NSString class]] ? playabilityStatus[@"reason"] : @"";
    if (status.length > 0) {
        [self log:@"player response playabilityStatus=%@ reason=%@", status, reason];
    }

    NSDictionary *videoDetails = [playerResponse[@"videoDetails"] isKindOfClass:[NSDictionary class]] ? playerResponse[@"videoDetails"] : nil;
    NSString *title = [videoDetails[@"title"] isKindOfClass:[NSString class]] ? videoDetails[@"title"] : fallbackTitle;
    NSDictionary *streamingData = [playerResponse[@"streamingData"] isKindOfClass:[NSDictionary class]] ? playerResponse[@"streamingData"] : nil;
    if (![streamingData isKindOfClass:[NSDictionary class]]) {
        [self log:@"player response missing streamingData"];
        return nil;
    }

    NSURL *hlsManifestURL = [self URLFromPotentialString:streamingData[@"hlsManifestUrl"]];
    if (hlsManifestURL != nil) {
        [self log:@"selected hls manifest url=%@", hlsManifestURL.absoluteString ?: @""];
        return [[BrowserYouTubeExtractionResult alloc] initWithPlaybackURL:hlsManifestURL
                                                                     title:title
                                                         sourceDescription:[NSString stringWithFormat:@"youtube %@ hls", sourceLabel ?: @"unknown"]
                                                            requestHeaders:requestHeaders ?: [self playbackRequestHeadersForPageURL:pageURL]];
    }

    BrowserYouTubeExtractionResult *formatResult = [self resultFromFormats:streamingData[@"formats"]
                                                                     title:title
                                                                    source:@"youtube muxed"];
    if (formatResult != nil) {
        return formatResult;
    }

    [self log:@"player response had streamingData but no playable hls or muxed format"];
    return nil;
}

- (NSDictionary *)playerRequestBodyForVideoID:(NSString *)videoID pageConfiguration:(NSDictionary *)pageConfiguration clientProfile:(NSDictionary *)clientProfile {
    NSDictionary *capturedBody = [self capturedPlayerRequestBodyFromPageConfiguration:pageConfiguration];
    NSString *clientVersion = [clientProfile[@"clientVersion"] isKindOfClass:[NSString class]] && [clientProfile[@"clientVersion"] length] > 0
        ? clientProfile[@"clientVersion"]
        : kBrowserYouTubeFallbackClientVersion;
    NSString *hl = [clientProfile[@"hl"] isKindOfClass:[NSString class]] && [clientProfile[@"hl"] length] > 0 ? clientProfile[@"hl"] : @"en";
    NSString *gl = [clientProfile[@"gl"] isKindOfClass:[NSString class]] && [clientProfile[@"gl"] length] > 0 ? clientProfile[@"gl"] : @"US";
    NSNumber *sts = [pageConfiguration[@"sts"] respondsToSelector:@selector(integerValue)] ? @([pageConfiguration[@"sts"] integerValue]) : nil;
    NSString *poToken = [pageConfiguration[@"poToken"] isKindOfClass:[NSString class]] ? pageConfiguration[@"poToken"] : @"";

    NSMutableDictionary *client = [@{
        @"clientName": clientProfile[@"clientName"] ?: @"WEB",
        @"clientVersion": clientVersion,
        @"hl": hl,
        @"gl": gl,
        @"userAgent": [clientProfile[@"userAgent"] isKindOfClass:[NSString class]] ? clientProfile[@"userAgent"] : kBrowserYouTubeSafariUserAgent,
    } mutableCopy];
    if ([clientProfile[@"osName"] isKindOfClass:[NSString class]]) {
        client[@"osName"] = clientProfile[@"osName"];
    }
    if ([clientProfile[@"osVersion"] isKindOfClass:[NSString class]]) {
        client[@"osVersion"] = clientProfile[@"osVersion"];
    }
    if ([clientProfile[@"deviceModel"] isKindOfClass:[NSString class]]) {
        client[@"deviceModel"] = clientProfile[@"deviceModel"];
    }

    NSMutableDictionary *body = nil;
    if ([capturedBody isKindOfClass:[NSDictionary class]] && [clientProfile[@"label"] isEqualToString:@"web"]) {
        body = [capturedBody mutableCopy];
        NSMutableDictionary *context = [[capturedBody[@"context"] isKindOfClass:[NSDictionary class]] ? capturedBody[@"context"] : @{} mutableCopy];
        context[@"client"] = client;
        body[@"context"] = context;
        body[@"videoId"] = videoID;
    } else {
        body = [@{
            @"videoId": videoID,
            @"contentCheckOk": @YES,
            @"racyCheckOk": @YES,
            @"context": @{
                @"client": client,
            },
        } mutableCopy];
    }

    if (body[@"contentCheckOk"] == nil) {
        body[@"contentCheckOk"] = @YES;
    }
    if (body[@"racyCheckOk"] == nil) {
        body[@"racyCheckOk"] = @YES;
    }

    if (sts.integerValue > 0) {
        body[@"playbackContext"] = @{
            @"contentPlaybackContext": @{
                @"signatureTimestamp": sts,
            },
        };
    }

    if (poToken.length > 0) {
        body[@"serviceIntegrityDimensions"] = @{
            @"poToken": poToken,
        };
    }

    return body;
}

- (NSDictionary<NSString *, NSString *> *)requestHeadersForPageURL:(NSURL *)pageURL clientProfile:(NSDictionary *)clientProfile visitorData:(NSString *)visitorData {
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSString *userAgent = [clientProfile[@"userAgent"] isKindOfClass:[NSString class]] ? clientProfile[@"userAgent"] : kBrowserYouTubeSafariUserAgent;
    if (userAgent.length > 0) {
        headers[@"User-Agent"] = userAgent;
    }
    if ([clientProfile[@"sendOrigin"] boolValue]) {
        headers[@"Origin"] = @"https://www.youtube.com";
    }
    if ([clientProfile[@"sendReferer"] boolValue]) {
        headers[@"Referer"] = pageURL.absoluteString ?: @"https://www.youtube.com/";
    }
    headers[@"Accept"] = @"*/*";
    headers[@"Accept-Language"] = @"en-US,en;q=0.9";
    if (visitorData.length > 0) {
        headers[@"X-Goog-Visitor-Id"] = visitorData;
    }
    return headers;
}

- (NSMutableURLRequest *)playerRequestForVideoID:(NSString *)videoID pageConfiguration:(NSDictionary *)pageConfiguration clientProfile:(NSDictionary *)clientProfile {
    NSString *apiKey = [pageConfiguration[@"apiKey"] isKindOfClass:[NSString class]] ? pageConfiguration[@"apiKey"] : @"";
    if (apiKey.length == 0) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://www.youtube.com/youtubei/v1/player"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"key" value:apiKey],
        [NSURLQueryItem queryItemWithName:@"prettyPrint" value:@"false"],
    ];

    NSURL *URL = components.URL;
    if (URL == nil) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSString *clientVersion = [clientProfile[@"clientVersion"] isKindOfClass:[NSString class]] && [clientProfile[@"clientVersion"] length] > 0
        ? clientProfile[@"clientVersion"]
        : kBrowserYouTubeFallbackClientVersion;
    NSMutableDictionary<NSString *, NSString *> *requestHeaders = [[self requestHeadersForPageURL:[NSURL URLWithString:@"https://www.youtube.com/"] clientProfile:clientProfile visitorData:[pageConfiguration[@"visitorData"] isKindOfClass:[NSString class]] ? pageConfiguration[@"visitorData"] : @""] mutableCopy];
    NSDictionary<NSString *, NSString *> *capturedHeaders = [self capturedPlayerRequestHeadersFromPageConfiguration:pageConfiguration];
    if ([clientProfile[@"label"] isEqualToString:@"web"] && capturedHeaders.count > 0) {
        [capturedHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
            if (value.length > 0) {
                requestHeaders[key] = value;
            }
        }];
    }
    [requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
        if (value.length > 0) {
            [request setValue:value forHTTPHeaderField:key];
        }
    }];

    NSString *clientHeaderName = [clientProfile[@"clientHeaderName"] isKindOfClass:[NSString class]] ? clientProfile[@"clientHeaderName"] : @"1";
    [request setValue:clientHeaderName forHTTPHeaderField:@"X-YouTube-Client-Name"];
    [request setValue:clientVersion forHTTPHeaderField:@"X-YouTube-Client-Version"];

    NSDictionary *requestBody = [self playerRequestBodyForVideoID:videoID pageConfiguration:pageConfiguration clientProfile:clientProfile];
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:requestBody options:0 error:nil];
    request.HTTPBody = bodyData;
    [self log:@"issuing youtubei player request client=%@ videoID=%@ apiKey=%@ clientVersion=%@ body=%@",
     clientProfile[@"label"] ?: @"unknown",
     videoID,
     apiKey.length > 0 ? @"yes" : @"no",
     clientVersion,
     requestBody];
    return request;
}

- (void)attemptPlayerRequestForVideoID:(NSString *)videoID
                     pageConfiguration:(NSDictionary *)pageConfiguration
                               pageURL:(NSURL *)pageURL
                            pageTitle:(NSString *)pageTitle
                           clientIndex:(NSUInteger)clientIndex
                           completion:(void (^)(BrowserYouTubeExtractionResult * _Nullable result, NSError * _Nullable error))completion {
    NSArray<NSDictionary *> *clientProfiles = [self clientProfilesForPageConfiguration:pageConfiguration];
    if (clientIndex >= clientProfiles.count) {
        completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeNoPlayableURL description:@"No YouTube client profile produced a native-playable stream URL."]);
        return;
    }

    NSDictionary *clientProfile = clientProfiles[clientIndex];
    NSMutableURLRequest *request = [self playerRequestForVideoID:videoID pageConfiguration:pageConfiguration clientProfile:clientProfile];
    if (request == nil) {
        [self attemptPlayerRequestForVideoID:videoID pageConfiguration:pageConfiguration pageURL:pageURL pageTitle:pageTitle clientIndex:clientIndex + 1 completion:completion];
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error != nil) {
            [self log:@"client=%@ network error %@", clientProfile[@"label"] ?: @"unknown", error];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self attemptPlayerRequestForVideoID:videoID pageConfiguration:pageConfiguration pageURL:pageURL pageTitle:pageTitle clientIndex:clientIndex + 1 completion:completion];
            });
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (![httpResponse isKindOfClass:[NSHTTPURLResponse class]] || httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            [self log:@"client=%@ unexpected HTTP response status=%ld",
             clientProfile[@"label"] ?: @"unknown",
             (long)httpResponse.statusCode];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self attemptPlayerRequestForVideoID:videoID pageConfiguration:pageConfiguration pageURL:pageURL pageTitle:pageTitle clientIndex:clientIndex + 1 completion:completion];
            });
            return;
        }

        id responseObject = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        [self log:@"received player response client=%@ status=%ld bytes=%lu",
         clientProfile[@"label"] ?: @"unknown",
         (long)httpResponse.statusCode,
         (unsigned long)data.length];

        NSDictionary<NSString *, NSString *> *playbackHeaders = [self requestHeadersForPageURL:pageURL
                                                                                  clientProfile:clientProfile
                                                                                   visitorData:[pageConfiguration[@"visitorData"] isKindOfClass:[NSString class]] ? pageConfiguration[@"visitorData"] : @""];
        BrowserYouTubeExtractionResult *result = [self resultFromPlayerResponse:responseObject
                                                                  fallbackTitle:pageTitle
                                                                        pageURL:pageURL
                                                                    sourceLabel:clientProfile[@"label"]
                                                                 requestHeaders:playbackHeaders];
        if (result == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self attemptPlayerRequestForVideoID:videoID pageConfiguration:pageConfiguration pageURL:pageURL pageTitle:pageTitle clientIndex:clientIndex + 1 completion:completion];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self validatePlaybackResult:result pageURL:pageURL completion:^(BrowserYouTubeExtractionResult *validatedResult, NSError *validationError) {
                if (validatedResult != nil) {
                    completion(validatedResult, nil);
                    return;
                }

                [self log:@"client=%@ validation failed %@", clientProfile[@"label"] ?: @"unknown", validationError.localizedDescription ?: @""];
                [self attemptPlayerRequestForVideoID:videoID pageConfiguration:pageConfiguration pageURL:pageURL pageTitle:pageTitle clientIndex:clientIndex + 1 completion:completion];
            }];
        });
    }];
    [task resume];
}

- (void)extractPlaybackInfoFromPageURL:(NSURL *)pageURL
                               webView:(BrowserWebView *)webView
                            completion:(void (^)(BrowserYouTubeExtractionResult *result, NSError *error))completion {
    if (![self canExtractFromPageURL:pageURL]) {
        completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeUnsupportedURL description:@"This page is not a YouTube page."]);
        return;
    }

    NSString *videoID = [self videoIDFromPageURL:pageURL];
    if (videoID.length == 0) {
        completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeMissingVideoID description:@"Could not determine the YouTube video ID from the page URL."]);
        return;
    }
    [self log:@"starting extraction pageURL=%@ videoID=%@", pageURL.absoluteString ?: @"", videoID];

    NSDictionary *pageConfiguration = [self pageConfigurationFromWebView:webView];
    if (![pageConfiguration isKindOfClass:[NSDictionary class]]) {
        completion(nil, [self errorWithCode:BrowserYouTubeExtractorErrorCodeMissingPageConfig description:@"Could not read YouTube configuration from the current page."]);
        return;
    }

    NSString *pageTitle = [pageConfiguration[@"pageTitle"] isKindOfClass:[NSString class]] ? pageConfiguration[@"pageTitle"] : @"";
    NSURL *pageHLSURL = [self URLFromPotentialString:pageConfiguration[@"pageHlsManifestUrl"]];
    if (pageHLSURL != nil) {
        [self log:@"using page-provided hls manifest url=%@", pageHLSURL.absoluteString ?: @""];
        BrowserYouTubeExtractionResult *result = [[BrowserYouTubeExtractionResult alloc] initWithPlaybackURL:pageHLSURL
                                                                                                      title:pageTitle
                                                                                          sourceDescription:@"youtube page hls"
                                                                                             requestHeaders:[self playbackRequestHeadersForPageURL:pageURL]];
        [self validatePlaybackResult:result pageURL:pageURL completion:completion];
        return;
    }

    [self attemptPlayerRequestForVideoID:videoID
                       pageConfiguration:pageConfiguration
                                 pageURL:pageURL
                               pageTitle:pageTitle
                              clientIndex:0
                              completion:completion];
}

@end
