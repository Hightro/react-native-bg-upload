//
//  HightroBackgroundResponder.m
//  HightroUploadService
//
//  Created by Joshua Nicholl on 21/3/21.
//

#import <Foundation/Foundation.h>
#import <Foundation/NSURLSession.h>
#import "HightroSessionManager.h"
#import <React/RCTLog.h>

@implementation HightroSessionManager
static void (^backgroundCompletionHandler)(void) = nil;
static NSURLSession* _session = nil;
NSString* __nonnull backgroundSessionID = @"com.hightro.background";

+ (void)setCompletionHandler:(void (^)(void))handler {
    backgroundCompletionHandler = handler;
}

+ (void (^)(void))getCompletionHandler {
    return backgroundCompletionHandler;
}

+ (bool)sessionExists {
    if(_session != nil) {
        RCTLogInfo(@"Session exists");
    } else {
        RCTLogInfo(@"Session does not exist yet.");
    }
    return _session != nil;
}

+ (void)createSession:(id<NSURLSessionDataDelegate> __nonnull)delegate {
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:backgroundSessionID];
    _session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];
    RCTLogInfo(@"Creating new URL session.");
}

+ (bool)createTaskWithRequest:(NSURLRequest*)req withFilePath:(NSURL* __nonnull)path withID:(NSString* __nonnull)taskID {
    if(_session == nil){
        RCTLogInfo(@"URLSession not found when creating task.");
        return false;
    }
    NSURLSessionUploadTask* task = [_session uploadTaskWithRequest:req fromFile:path];
    task.taskDescription = taskID;
    [task resume];
    return true;
}

+ (id<NSURLSessionDataDelegate> __nullable)getDelegate {
    return (id<NSURLSessionDataDelegate>)_session.delegate;
}
@end
