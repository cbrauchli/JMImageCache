//
//  JMImageCache.m
//  JMCache
//
//  Created by Jake Marsh on 2/7/11.
//  Copyright 2011 Jake Marsh. All rights reserved.
//

#import "JMImageCache.h"
#import "CBOperationStack.h"

static NSString *_JMImageCacheDirectory;
static dispatch_once_t onceToken;

static inline NSString *JMImageCacheDirectory() {
    dispatch_once(&onceToken, ^{
        _JMImageCacheDirectory = [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"JMCache"] copy];
    });
    
    return _JMImageCacheDirectory;
}
static inline NSString *keyForURL(NSURL *url) {
    return [url absoluteString];
}
static inline NSString *cachePathForKey(NSString *key) {
    NSString *fileName = [NSString stringWithFormat:@"JMImageCache-%u", [key hash]];
    return [JMImageCacheDirectory() stringByAppendingPathComponent:fileName];
}

@interface JMImageCache ()

@property (strong, nonatomic) CBOperationStack *diskOperationQueue;
@property (strong, nonatomic) CBOperationStack *downloadOperationQueue;

- (void) _asyncGetImageFromDiskOrRemoteSourceForURL:(NSURL *)url key:(NSString *)key completionBlock:(void (^)(UIImage *image))completion;
- (void) _downloadAndWriteImageForURL:(NSURL *)url key:(NSString *)key completionBlock:(void (^)(UIImage *image))completion;

@end

@implementation JMImageCache

@synthesize diskOperationQueue = _diskOperationQueue;
@synthesize downloadOperationQueue = _downloadOperationQueue;

+ (JMImageCache *) sharedCache {
    static JMImageCache *shared;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        shared = [[JMImageCache alloc] init];
    });
    
    return shared;
}

- (id) init {
    self = [super init];
    if(!self) return nil;
    
    self.diskOperationQueue = [[CBOperationStack alloc] init];
    self.diskOperationQueue.maxConcurrentOperationCount = 3;
    self.downloadOperationQueue = [[CBOperationStack alloc] init];
    self.downloadOperationQueue.maxConcurrentOperationCount = 3;
    
    [[NSFileManager defaultManager] createDirectoryAtPath:JMImageCacheDirectory()
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return self;
}

- (void) _asyncGetImageFromDiskOrRemoteSourceForURL:(NSURL *)url key:(NSString *)key completionBlock:(void (^)(UIImage *image))completion {
    if (!key && !url) return;
    
    if (!key) {
        key = keyForURL(url);
    }
    
    NSBlockOperation *diskReadOperation = [NSBlockOperation blockOperationWithBlock:^{
          UIImage *i = [self imageFromDiskForKey:key];
          
          if (i) {
              [self setImage:i forKey:key];
              
              dispatch_async(dispatch_get_main_queue(), ^{
                  if(completion) completion(i);
              });
          } else {
              // Have to download the image!
              [self _downloadAndWriteImageForURL:url key:key completionBlock:completion];
          }
    }];
    
    [self.diskOperationQueue addOperation:diskReadOperation];
}

- (void) _downloadAndWriteImageForURL:(NSURL *)url key:(NSString *)key completionBlock:(void (^)(UIImage *image))completion {
    if (!key && !url) return;
    
    if (!key) {
        key = keyForURL(url);
    }
    
    NSBlockOperation *downloadOperation = [NSBlockOperation blockOperationWithBlock:^{
          NSError *error = nil;
          NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&error];
          UIImage *i = [[UIImage alloc] initWithData:data];
        
          if (error) {
              NSLog(@"Error downloading image from %@: %@", [url absoluteString], [error localizedDescription]);
          }
          else {
              [self setImage:i forKey:key];
              
              dispatch_async(dispatch_get_main_queue(), ^{
                  if(completion) completion(i);
              });
              
              NSBlockOperation *diskWriteOperation = [NSBlockOperation blockOperationWithBlock:^{
                  NSString *cachePath = cachePathForKey(key);
                  [self writeData:data toPath:cachePath];
              }];
              [self.diskOperationQueue addOperationAtBottomOfStack:diskWriteOperation];
//                [self.diskOperationQueue addOperation:diskWriteOperation];
          }
    }];
    
    [self.downloadOperationQueue addOperation:downloadOperation];
}

- (void) removeAllObjects {
    [super removeAllObjects];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        NSError *error = nil;
        NSArray *directoryContents = [fileMgr contentsOfDirectoryAtPath:JMImageCacheDirectory() error:&error];
        
        if (error == nil) {
            for (NSString *path in directoryContents) {
                NSString *fullPath = [JMImageCacheDirectory() stringByAppendingPathComponent:path];
                
                BOOL removeSuccess = [fileMgr removeItemAtPath:fullPath error:&error];
                if (!removeSuccess) {
                    //Error Occured
                }
            }
        } else {
            //Error Occured
        }
    });
}
- (void) removeObjectForKey:(id)key {
    [super removeObjectForKey:key];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        NSString *cachePath = cachePathForKey(key);
        
        NSError *error = nil;
        
        BOOL removeSuccess = [fileMgr removeItemAtPath:cachePath error:&error];
        if (!removeSuccess) {
            //Error Occured
        }
    });
}

#pragma mark -
#pragma mark Getter Methods

- (void) imageForURL:(NSURL *)url key:(NSString *)key completionBlock:(void (^)(UIImage *image))completion {
    
    UIImage *i = [super objectForKey:key];
    
    if(i) {
        if(completion) completion(i);
    } else {
        [self _asyncGetImageFromDiskOrRemoteSourceForURL:url key:key completionBlock:completion];
    }
}

- (void) imageForURL:(NSURL *)url completionBlock:(void (^)(UIImage *image))completion {
    [self imageForURL:url key:keyForURL(url) completionBlock:completion];
}

- (id)objectForURL:(NSURL *)url {
    NSString *key = keyForURL(url);
    return [super objectForKey:key];
}

- (UIImage *) cachedImageForKey:(NSString *)key {
    if(!key) return nil;
    
    id returner = [super objectForKey:key];
    
    if(returner) {
        return returner;
    } else {
        UIImage *i = [self imageFromDiskForKey:key];
        if(i) [self setImage:i forKey:key];
        
        return i;
    }
    
    return nil;
}

- (UIImage *) cachedImageForURL:(NSURL *)url {
    NSString *key = keyForURL(url);
    return [self cachedImageForKey:key];
}

- (UIImage *) imageForURL:(NSURL *)url key:(NSString*)key delegate:(id<JMImageCacheDelegate>)d {
    if(!url) return nil;
    
    UIImage *i = [self cachedImageForURL:url];
    
    if(i) {
        return i;
    } else {
        [self _downloadAndWriteImageForURL:url key:key completionBlock:^(UIImage *image) {
            if(d) {
                if([d respondsToSelector:@selector(cache:didDownloadImage:forURL:)]) {
                    [d cache:self didDownloadImage:image forURL:url];
                }
                if([d respondsToSelector:@selector(cache:didDownloadImage:forURL:key:)]) {
                    [d cache:self didDownloadImage:image forURL:url key:key];
                }
            }
        }];
    }
    
    return nil;
}

- (UIImage *) imageForURL:(NSURL *)url delegate:(id<JMImageCacheDelegate>)d {
    return [self imageForURL:url key:keyForURL(url) delegate:d];
}

- (UIImage *) imageFromDiskForKey:(NSString *)key {
    UIImage *i = [[UIImage alloc] initWithData:[NSData dataWithContentsOfFile:cachePathForKey(key) options:0 error:NULL]];
    return i;
}

- (UIImage *) imageFromDiskForURL:(NSURL *)url {
    return [self imageFromDiskForKey:keyForURL(url)];
}

#pragma mark -
#pragma mark Setter Methods

- (void) setImage:(UIImage *)i forKey:(NSString *)key {
    if (i) {
        [super setObject:i forKey:key];
    }
}
- (void) setImage:(UIImage *)i forURL:(NSURL *)url {
    [self setImage:i forKey:keyForURL(url)];
}
- (void) removeImageForKey:(NSString *)key {
    [super removeObjectForKey:key];
}
- (void) removeImageForURL:(NSURL *)url {
    [self removeImageForKey:keyForURL(url)];
}

#pragma mark -
#pragma mark Disk Writing Operations

- (void) writeData:(NSData*)data toPath:(NSString *)path {
    [data writeToFile:path atomically:YES];
}

@end