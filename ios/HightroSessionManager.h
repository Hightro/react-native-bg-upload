//
//  HightroBackgroundResponder.h
//  Pods
//
//  Created by Joshua Nicholl on 21/3/21.
//

#ifndef HightroBackgroundResponder_h
#define HightroBackgroundResponder_h
@interface HightroSessionManager: NSObject
+ (void)setCompletionHandler:(void (^)(void)) handler;
+ (void (^)(void))getCompletionHandler;
+ (NSURLSession*)getURLSession;
+ (void)registerURLSession:(NSURLSession*) newSession;
@end
#endif /* HightroBackgroundResponder_h */
