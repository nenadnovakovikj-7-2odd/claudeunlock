#import "CUURLProtocol.h"

static NSString *const kCUHandled = @"ClaudeUnlockHandled";

@interface CUURLProtocol () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSURLResponse *resp;
@property (nonatomic, strong) NSMutableData *jsonBuf;
@property (nonatomic, strong) CUStreamPatcher *patcher;
@property (nonatomic, assign) BOOL passthrough;
@property (nonatomic, assign) BOOL sentResponse;
@property (nonatomic, assign) BOOL done;
@end

@implementation CUURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) return NO;
    if ([NSURLProtocol propertyForKey:kCUHandled inRequest:request]) return NO;
    NSString *host = request.URL.host.lowercaseString;
    return [host hasSuffix:@"claude.ai"] || [host hasSuffix:@"anthropic.com"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kCUHandled inRequest:req];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 120;
    self.session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.task = [self.session dataTaskWithRequest:req];
    [self.task resume];
}

- (void)stopLoading {
    self.done = YES;
    [self.task cancel];
    [self.session finishTasksAndInvalidate];
    self.session = nil;
}

- (void)forwardResponse {
    if (self.sentResponse || !self.resp) return;
    self.sentResponse = YES;
    [self.client URLProtocol:self
         didReceiveResponse:self.resp
         cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)URLSession:(NSURLSession *)s
              task:(NSURLSessionTask *)t
    didReceiveResponse:(NSURLResponse *)response
    completionHandler:(void (^)(NSURLSessionResponseDisposition))ch {
    self.resp = response;

    NSString *ct = @"";
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        id v = ((NSHTTPURLResponse *)response).allHeaderFields[@"Content-Type"];
        if ([v isKindOfClass:NSString.class]) ct = [v lowercaseString];
    }

    BOOL stream = [ct containsString:@"event-stream"] || [ct containsString:@"connect+proto"];
    BOOL json = [ct containsString:@"json"] || [ct containsString:@"javascript"];

    if (stream) {
        NSInteger mode = [ct containsString:@"connect+proto"] ? 1 : 0;
        self.patcher = [[CUStreamPatcher alloc] initWithMode:mode];
        [self forwardResponse];
    } else if (json) {
        self.jsonBuf = [NSMutableData data];
    } else {
        self.passthrough = YES;
        [self forwardResponse];
    }
    ch(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didReceiveData:(NSData *)data {
    if (self.done) return;

    if (self.passthrough) {
        [self.client URLProtocol:self didLoadData:data];
        return;
    }
    if (self.patcher) {
        NSData *out = [self.patcher consume:data];
        if (out.length) [self.client URLProtocol:self didLoadData:out];
        return;
    }
    [self.jsonBuf appendData:data];
    if (self.jsonBuf.length > (8 << 20)) {
        self.passthrough = YES;
        [self forwardResponse];
        [self.client URLProtocol:self didLoadData:self.jsonBuf];
        self.jsonBuf = nil;
    }
}

- (void)URLSession:(NSURLSession *)s
              task:(NSURLSessionTask *)t
    didCompleteWithError:(NSError *)error {
    if (self.done) return;
    self.done = YES;

    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
        [self.session finishTasksAndInvalidate];
        return;
    }

    if (self.patcher) {
        NSData *tail = [self.patcher flush];
        if (tail.length) [self.client URLProtocol:self didLoadData:tail];
        [self.client URLProtocolDidFinishLoading:self];
        [self.session finishTasksAndInvalidate];
        return;
    }

    if (self.jsonBuf) {
        NSData *patched = CUPatchJSONData(self.jsonBuf);
        NSURLResponse *final = self.resp;

        if ([self.resp isKindOfClass:NSHTTPURLResponse.class]) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)self.resp;
            NSMutableDictionary *h = [NSMutableDictionary dictionary];
            for (NSString *key in http.allHeaderFields) {
                NSString *lk = key.lowercaseString;
                if ([lk isEqualToString:@"content-length"] ||
                    [lk isEqualToString:@"content-encoding"] ||
                    [lk isEqualToString:@"transfer-encoding"]) continue;
                h[key] = http.allHeaderFields[key];
            }
            h[@"Content-Length"] = [@(patched.length) stringValue];
            final = [[NSHTTPURLResponse alloc] initWithURL:http.URL
                                               statusCode:http.statusCode
                                              HTTPVersion:@"HTTP/1.1"
                                             headerFields:h];
        }

        self.resp = final;
        [self forwardResponse];
        if (patched.length) [self.client URLProtocol:self didLoadData:patched];
        [self.client URLProtocolDidFinishLoading:self];
        [self.session finishTasksAndInvalidate];
        return;
    }

    [self forwardResponse];
    [self.client URLProtocolDidFinishLoading:self];
    [self.session finishTasksAndInvalidate];
}

@end
