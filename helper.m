// Reads the system-wide "Now Playing" (any app, including browsers) through the
// private MediaRemote framework. Since macOS 15.4 MediaRemote only answers
// Apple-signed processes, so this dylib is loaded into /usr/bin/perl
// (see the perl one-liner in main.swift) and talks to the app over stdin/stdout:
//   stdout: one JSON object per line with the current state
//   stdin:  "toggle" | "next" | "prev" | "seek <seconds>"
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetIsPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*ClientStrFn)(id);
typedef Boolean (*SendCommandFn)(int, NSDictionary *);
typedef void (*SetElapsedFn)(double);
typedef void (*RegisterFn)(dispatch_queue_t);

static GetInfoFn getInfo;
static GetIsPlayingFn getIsPlaying;
static GetClientFn getClient;
static ClientStrFn clientBundle, clientParentBundle;
static SendCommandFn sendCommand;
static SetElapsedFn setElapsed;
static dispatch_queue_t queue;
static NSString *lastArtKey;

static void emit(void) {
    getInfo(queue, ^(NSDictionary *info) {
        getIsPlaying(queue, ^(BOOL playing) {
            getClient(queue, ^(id client) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if (title.length) {
                    NSString *bundle = client && clientParentBundle ? clientParentBundle(client) : nil;
                    if (!bundle.length && client && clientBundle) bundle = clientBundle(client);
                    double elapsed = [info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue];
                    double rate = [info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] doubleValue];
                    NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                    if (playing && stamp) elapsed += -[stamp timeIntervalSinceNow] * (rate > 0 ? rate : 1);
                    out[@"title"] = title;
                    out[@"artist"] = info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
                    out[@"duration"] = info[@"kMRMediaRemoteNowPlayingInfoDuration"] ?: @0;
                    out[@"elapsed"] = @(elapsed);
                    out[@"playing"] = @(playing);
                    out[@"bundle"] = bundle ?: @"";
                    // Artwork is large, so it is only sent when it changes.
                    NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    NSString *artKey = [NSString stringWithFormat:@"%@|%@|%lu", title, out[@"artist"], (unsigned long)art.length];
                    if (![artKey isEqualToString:lastArtKey]) {
                        lastArtKey = artKey;
                        out[@"artwork"] = art.length ? [art base64EncodedStringWithOptions:0] : @"";
                    }
                } else {
                    lastArtKey = nil;
                }
                NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                if (json) {
                    fwrite(json.bytes, 1, json.length, stdout);
                    fputc('\n', stdout);
                    fflush(stdout);
                }
            });
        });
    });
}

static void handle(NSString *line) {
    if ([line isEqualToString:@"toggle"]) sendCommand(2, nil);
    else if ([line isEqualToString:@"next"]) sendCommand(4, nil);
    else if ([line isEqualToString:@"prev"]) sendCommand(5, nil);
    else if ([line hasPrefix:@"seek "]) setElapsed([[line substringFromIndex:5] doubleValue]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), queue, ^{ emit(); });
}

// Called from perl as an XSUB; the arguments (interpreter, CV) are unused. Never returns.
void np_run(void *interp, void *cv) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { fprintf(stderr, "MediaRemote not found\n"); exit(1); }
    getInfo = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient = dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    sendCommand = dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = dlsym(mr, "MRMediaRemoteSetElapsedTime");
    RegisterFn registerFn = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !getClient || !sendCommand || !setElapsed) {
        fprintf(stderr, "MediaRemote symbols missing\n");
        exit(1);
    }

    queue = dispatch_queue_create("np.helper", DISPATCH_QUEUE_SERIAL);
    if (registerFn) registerFn(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                      usingBlock:^(NSNotification *n) { dispatch_async(queue, ^{ emit(); }); }];
    }

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    // Changes arrive through the notifications above; the timer is only a safety net.
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, ^{ emit(); });
    dispatch_resume(timer);

    // Commands from the app; EOF means the app quit, so we quit too.
    __block NSMutableString *buffer = [NSMutableString string];
    dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    dispatch_source_set_event_handler(input, ^{
        char buf[512];
        ssize_t n = read(STDIN_FILENO, buf, sizeof buf);
        if (n <= 0) exit(0);
        [buffer appendString:[[NSString alloc] initWithBytes:buf length:n encoding:NSUTF8StringEncoding] ?: @""];
        NSRange r;
        while ((r = [buffer rangeOfString:@"\n"]).location != NSNotFound) {
            NSString *line = [buffer substringToIndex:r.location];
            [buffer deleteCharactersInRange:NSMakeRange(0, r.location + 1)];
            handle([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]);
        }
    });
    dispatch_resume(input);

    CFRunLoopRun();
}
