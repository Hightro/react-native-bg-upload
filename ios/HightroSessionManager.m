//
//  HightroBackgroundResponder.m
//  HightroUploadService
//
//  Created by Joshua Nicholl on 21/3/21.
//

#import <Foundation/Foundation.h>
#import "HightroSessionManager.h"

@implementation HightroSessionManager
static void (^backgroundCompletionHandler)(void) = nil;
static NSURLSession* _session = nil;

+ (void)setCompletionHandler:(void (^)(void))handler {
    backgroundCompletionHandler = handler;
}

+ (void (^)(void))getCompletionHandler {
    return backgroundCompletionHandler;
}

+ (NSURLSession*)getURLSession {
    if(_session == nil){
        return nil;
    }
    return _session;
}

+ (void)registerURLSession:(NSURLSession *)newSession {
    _session = newSession;
}

@end
