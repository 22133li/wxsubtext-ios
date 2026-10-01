#import "WXSubtextLog.h"

static NSString *WXSubtextLogPath(void) {
    static NSString *path = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        @try {
            NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *doc = [dirs firstObject];
            if (doc.length) path = [doc stringByAppendingPathComponent:@"wxsubtext.log"];
        } @catch (NSException *e) { path = nil; }
    });
    return path;
}

static NSObject *WXSubtextLogLock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ lock = [[NSObject alloc] init]; });
    return lock;
}

void WXSubtextLogMessage(NSString *format, ...) {
    @try {
        va_list ap;
        va_start(ap, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
        va_end(ap);
        if (!msg.length) return;
        NSLog(@"%@", msg);
        NSString *path = WXSubtextLogPath();
        if (!path.length) return;
        @synchronized (WXSubtextLogLock()) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
            unsigned long long size = [attr[NSFileSize] unsignedLongLongValue];
            if (size > 256 * 1024) [fm removeItemAtPath:path error:nil];
            static NSDateFormatter *df = nil;
            static dispatch_once_t t2;
            dispatch_once(&t2, ^{
                df = [[NSDateFormatter alloc] init];
                df.dateFormat = @"MM-dd HH:mm:ss";
            });
            NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], msg];
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!fh) {
                [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            } else {
                @try {
                    [fh seekToEndOfFile];
                    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                } @catch (NSException *e) {}
                [fh closeFile];
            }
        }
    } @catch (NSException *e) {}
}
