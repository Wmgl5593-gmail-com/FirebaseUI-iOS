//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <objc/runtime.h>

#import "UIImageView+FirebaseStorage.h"

@interface UIImageView (FirebaseStorage_Private)
@property (nonatomic, readwrite, nullable, setter=sd_setCurrentDownloadTask:) id<FUIDownloadTask> sd_currentDownloadTask;
@end

@implementation UIImageView (FirebaseStorage)

- (id<FUIDownloadTask>)sd_setImageWithStorageReference:(id<FUIStorageReference>)storageRef {
  return [self sd_setImageWithStorageReference:storageRef placeholderImage:nil completion:nil];
}

- (id<FUIDownloadTask>)sd_setImageWithStorageReference:(id<FUIStorageReference>)storageRef
                                      placeholderImage:(UIImage *)placeholder {
  return [self sd_setImageWithStorageReference:storageRef placeholderImage:placeholder completion:nil];
}

- (id<FUIDownloadTask>)sd_setImageWithStorageReference:(id<FUIStorageReference>)storageRef
                                      placeholderImage:(UIImage *)placeholder
                                            completion:(void (^)(UIImage *_Nullable,
                                                                 NSError *_Nullable,
                                                                 SDImageCacheType,
                                                                 FIRStorageReference *))completion {
  return [self sd_setImageWithStorageReference:storageRef
                                  maxImageSize:5e6 // 5 megabytes
                              placeholderImage:placeholder
                                    completion:completion];
}

- (id<FUIDownloadTask>)sd_setImageWithStorageReference:(id<FUIStorageReference>)storageRef
                                          maxImageSize:(UInt64)size
                                      placeholderImage:(nullable UIImage *)placeholder
                                            completion:(void (^)(UIImage *,
                                                                 NSError *,
                                                                 SDImageCacheType,
                                                                 FIRStorageReference *))completion{
  return [self sd_setImageWithStorageReference:storageRef
                                  maxImageSize:size
                              placeholderImage:placeholder
                                         cache:[SDImageCache sharedImageCache]
                                    completion:completion];
}

- (id<FUIDownloadTask>)sd_setImageWithStorageReference:(id<FUIStorageReference>)storageRef
                                          maxImageSize:(UInt64)size
                                      placeholderImage:(nullable UIImage *)placeholder
                                                 cache:(nullable id<FUIImageCache>)cache
                                            completion:(void (^)(UIImage *,
                                                                 NSError *,
                                                                 SDImageCacheType,
                                                                 FIRStorageReference *))completion {
  NSParameterAssert(storageRef != nil);

  // If there's already a download on this UIImageView, cancel it
  if (self.sd_currentDownloadTask != nil) {
    [self.sd_currentDownloadTask cancel];
    self.sd_currentDownloadTask = nil;
  }

  // Set placeholder image
  self.image = placeholder;

  // Query cache for image before trying to download
  NSString *key = storageRef.fullPath;
  UIImage *cached = nil;

  cached = [cache imageFromMemoryCacheForKey:key];
  if (cached != nil) {
    self.image = cached;
    if (completion != nil) {
      completion(cached, nil, SDImageCacheTypeMemory, storageRef);
    }
    return nil;
  }

  cached = [cache imageFromDiskCacheForKey:key];
  if (cached != nil) {
    self.image = cached;
    if (completion != nil) {
      completion(cached, nil, SDImageCacheTypeDisk, storageRef);
    }
    return nil;
  }

  // If nothing was found in cache, download the image from Firebase Storage
  id<FUIDownloadTask> download = [storageRef dataWithMaxSize:size
                                                  completion:^(NSData * _Nullable data,
                                                               NSError * _Nullable error) {
    if (data != nil) {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.sd_currentDownloadTask = nil;
        UIImage *image = [UIImage sd_imageWithData:data];
        self.image = image;

        // Cache downloaded image
        [cache storeImage:image forKey:storageRef.fullPath];

        if (completion != nil) {
          completion(image, nil, SDImageCacheTypeNone, storageRef);
        }
      });
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.sd_currentDownloadTask = nil;
      });
      if (completion != nil) {
        completion(nil, error, SDImageCacheTypeNone, storageRef);
      }
    }
  }];
  self.sd_currentDownloadTask = download;
  return download;
}

#pragma mark - Accessors

- (void)sd_setCurrentDownloadTask:(id<FUIDownloadTask>)currentDownload {
  objc_setAssociatedObject(self,
                           @selector(sd_currentDownloadTask),
                           currentDownload,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id<FUIDownloadTask>)sd_currentDownloadTask {
  return objc_getAssociatedObject(self, @selector(sd_currentDownloadTask));
}

@end
