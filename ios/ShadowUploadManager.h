//
//  ShadowUploadResponder.h
//  Pods
//
//  Created by Joshua Nicholl on 21/3/21.
//

#ifndef ShadowUploadResponder_h
#define ShadowUploadResponder_h

@interface ShadowUploadManager: NSObject
+ (void)setCompletionHandler:(void (^ __nonnull)(void)) handler;
+ (void (^ __nullable)(void))getCompletionHandler;
+ (bool)sessionExists;
+ (void)createSession:(id<NSURLSessionDataDelegate> __nonnull)delegate;
+ (bool)createTaskWithRequest:(NSURLRequest* __nonnull)request withFilePath:(NSURL* __nonnull)path withID:(NSString* __nonnull)taskID;
+ (id<NSURLSessionDataDelegate> __nullable)getDelegate;
@end
#endif /* ShadowUploadResponder_h */
