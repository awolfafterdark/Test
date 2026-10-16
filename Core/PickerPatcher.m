#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>

static char PPBypassKey;
static char PPBridgeKey;
static NSString *const PPDisableFlag = @"/var/jb/Library/PickerPatcher/disabled";

// This file deliberately has no substrate/ElleKit dependency. The same code is
// compiled into the rootless tweak and into a signed IPA's embedded framework.

@interface PPDocumentBridge : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIImagePickerController *originalPicker;
@property(nonatomic, weak) UIViewController *presenter;
@property(nonatomic, strong) UIDocumentPickerViewController *documentPicker;
@property(nonatomic) BOOL processing;
- (instancetype)initWithPicker:(UIImagePickerController *)picker presenter:(UIViewController *)presenter;
@end

@implementation PPDocumentBridge

- (instancetype)initWithPicker:(UIImagePickerController *)picker presenter:(UIViewController *)presenter {
    if ((self = [super init])) {
        _originalPicker = picker;
        _presenter = presenter;
    }
    return self;
}

- (void)endSession {
    UIDocumentPickerViewController *documentPicker = self.documentPicker;
    self.documentPicker = nil;
    objc_setAssociatedObject(documentPicker, &PPBridgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self.originalPicker, &PPBridgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    void (^finish)(void) = ^{
        id<UIImagePickerControllerDelegate> delegate = self.originalPicker.delegate;
        if ([delegate respondsToSelector:@selector(imagePickerControllerDidCancel:)]) {
            [delegate imagePickerControllerDidCancel:self.originalPicker];
        }
        [self endSession];
    };
    if (controller.presentingViewController) [controller dismissViewControllerAnimated:YES completion:finish];
    else finish();
}

- (void)showFailure:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Could not open file"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        id<UIImagePickerControllerDelegate> delegate = self.originalPicker.delegate;
        if ([delegate respondsToSelector:@selector(imagePickerControllerDidCancel:)]) {
            [delegate imagePickerControllerDidCancel:self.originalPicker];
        }
        [self endSession];
    }]];
    UIViewController *presenter = self.originalPicker.presentingViewController ? self.originalPicker : self.presenter;
    if (presenter && !presenter.presentedViewController) {
        [presenter presentViewController:alert animated:YES completion:nil];
    } else {
        id<UIImagePickerControllerDelegate> delegate = self.originalPicker.delegate;
        if ([delegate respondsToSelector:@selector(imagePickerControllerDidCancel:)]) {
            [delegate imagePickerControllerDidCancel:self.originalPicker];
        }
        [self endSession];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:@[url]];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.processing) return;
    self.processing = YES;
    NSURL *source = urls.firstObject;
    if (!source) {
        [self documentPickerWasCancelled:controller];
        return;
    }
    // The original UIKit picker is single-select. Use the same cardinality here.
    __strong PPDocumentBridge *keepAlive = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [source startAccessingSecurityScopedResource];
        __block NSURL *staged = nil;
        __block NSString *failure = nil;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError *coordinationError = nil;
        [coordinator coordinateReadingItemAtURL:source options:0 error:&coordinationError byAccessor:^(NSURL *readURL) {
            NSNumber *bytes = nil;
            [readURL getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
            NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSTemporaryDirectory() error:nil];
            unsigned long long freeBytes = [fs[NSFileSystemFreeSize] unsignedLongLongValue];
            unsigned long long needed = bytes.unsignedLongLongValue;
            NSString *temporaryPrefix = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES].URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
            BOOL ownTemporaryCopy = [readURL.URLByResolvingSymlinksInPath.path hasPrefix:temporaryPrefix];
            unsigned long long additional = ownTemporaryCopy ? 0 : needed;
            if (!bytes || needed == 0 || needed > 2ULL * 1024 * 1024 * 1024 ||
                additional > freeBytes || freeBytes - additional < 256ULL * 1024 * 1024) {
                failure = @"The file size is unknown, too large, or there is too little free space.";
                return;
            }
            NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                URLByAppendingPathComponent:@"PickerPatcher" isDirectory:YES];
            NSError *error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
                failure = error.localizedDescription;
                return;
            }
            // Preserve the name; isolate selections by UUID to avoid collisions.
            NSURL *session = [folder URLByAppendingPathComponent:[NSUUID UUID].UUIDString isDirectory:YES];
            if (![[NSFileManager defaultManager] createDirectoryAtURL:session withIntermediateDirectories:YES attributes:nil error:&error]) {
                failure = error.localizedDescription;
                return;
            }
            NSURL *destination = [session URLByAppendingPathComponent:source.lastPathComponent ?: @"media"];
            BOOL stored = ownTemporaryCopy
                ? [[NSFileManager defaultManager] moveItemAtURL:readURL toURL:destination error:&error]
                : [[NSFileManager defaultManager] copyItemAtURL:readURL toURL:destination error:&error];
            if (!stored) {
                failure = error.localizedDescription;
                [[NSFileManager defaultManager] removeItemAtURL:session error:nil];
                return;
            }
            staged = destination;
        }];
        if (scoped) [source stopAccessingSecurityScopedResource];
        if (!staged && !failure) failure = coordinationError.localizedDescription ?: @"File provider access failed.";
        __block UIImage *decodedImage = nil;
        if (staged) {
            CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)staged, NULL);
            if (imageSource) {
                NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL));
                unsigned long long width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue];
                unsigned long long height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
                if (!width || !height || width > 12000 || height > 12000 || width * height > 32000000) {
                    failure = @"Image dimensions exceed the 32 megapixel memory limit.";
                } else {
                    decodedImage = [UIImage imageWithContentsOfFile:staged.path];
                    if (!decodedImage) failure = @"The image could not be decoded.";
                }
                CFRelease(imageSource);
            } else {
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:staged options:nil];
                if ([asset tracksWithMediaType:AVMediaTypeVideo].count == 0) {
                    failure = @"The file contains no readable image or video track.";
                }
            }
            if (failure) {
                [[NSFileManager defaultManager] removeItemAtURL:staged.URLByDeletingLastPathComponent error:nil];
                staged = nil;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^finish)(void) = ^{
                if (!staged) {
                    [keepAlive showFailure:failure ?: @"The file could not be copied."];
                    return;
                }
                NSURL *file = staged;
                UTType *type = [UTType typeWithFilenameExtension:file.pathExtension];
                BOOL image = [type conformsToType:UTTypeImage];
                BOOL movie = [type conformsToType:UTTypeMovie];
                BOOL imageAllowed = keepAlive.originalPicker.mediaTypes.count == 0;
                BOOL movieAllowed = NO;
                for (NSString *identifier in keepAlive.originalPicker.mediaTypes) {
                    UTType *accepted = [UTType typeWithIdentifier:identifier];
                    imageAllowed |= [accepted conformsToType:UTTypeImage];
                    movieAllowed |= [accepted conformsToType:UTTypeMovie];
                }
                if ((!image && !movie) || (image && !imageAllowed) || (movie && !movieAllowed)) {
                    [[NSFileManager defaultManager] removeItemAtURL:file.URLByDeletingLastPathComponent error:nil];
                    [keepAlive showFailure:@"This file is not a supported image or video."];
                    return;
                }
                NSMutableDictionary *info = [NSMutableDictionary dictionary];
                if (image) {
                    UIImage *uiImage = decodedImage;
                    if (!uiImage) {
                        [[NSFileManager defaultManager] removeItemAtURL:file.URLByDeletingLastPathComponent error:nil];
                        [keepAlive showFailure:@"The image could not be decoded."];
                        return;
                    }
                    info[UIImagePickerControllerMediaType] = @"public.image";
                    info[UIImagePickerControllerOriginalImage] = uiImage;
                    info[UIImagePickerControllerImageURL] = file;
                } else {
                    info[UIImagePickerControllerMediaType] = @"public.movie";
                    info[UIImagePickerControllerMediaURL] = file;
                }
                id<UIImagePickerControllerDelegate> delegate = keepAlive.originalPicker.delegate;
                if ([delegate respondsToSelector:@selector(imagePickerController:didFinishPickingMediaWithInfo:)]) {
                    [delegate imagePickerController:keepAlive.originalPicker didFinishPickingMediaWithInfo:info];
                }
                // The receiving app may use a file URL asynchronously. Keep the staging file
                // through app exit; the OS clears app tmp, and the next app launch prunes old files.
                [keepAlive endSession];
            };
            if (controller.presentingViewController) [controller dismissViewControllerAnimated:YES completion:finish];
            else finish();
        });
    });
}
@end

static void PPPruneOldFiles(void) {
    NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:@"PickerPatcher" isDirectory:YES];
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-24 * 60 * 60];
    for (NSURL *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:folder
        includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]) {
        NSDate *modified = nil;
        [entry getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        if (modified && [modified compare:cutoff] == NSOrderedAscending) {
            [[NSFileManager defaultManager] removeItemAtURL:entry error:nil];
        }
    }
}

@interface UIViewController (PickerPatcher)
- (void)pp_presentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;
@end

@implementation UIViewController (PickerPatcher)
- (void)pp_presentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion {
    if (objc_getAssociatedObject(viewController, &PPBypassKey)) {
        objc_setAssociatedObject(viewController, &PPBypassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self pp_presentViewController:viewController animated:animated completion:completion];
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"PickerPatcherDisabled"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:PPDisableFlag] ||
        ![viewController isKindOfClass:[UIImagePickerController class]]) {
        [self pp_presentViewController:viewController animated:animated completion:completion];
        return;
    }
    UIImagePickerController *picker = (UIImagePickerController *)viewController;
    if (picker.sourceType != UIImagePickerControllerSourceTypePhotoLibrary &&
        picker.sourceType != UIImagePickerControllerSourceTypeSavedPhotosAlbum) {
        [self pp_presentViewController:viewController animated:animated completion:completion];
        return;
    }
    // Preserve workflows whose delegate or editing contract we cannot satisfy.
    if (picker.allowsEditing || ![picker.delegate respondsToSelector:@selector(imagePickerController:didFinishPickingMediaWithInfo:)]) {
        [self pp_presentViewController:viewController animated:animated completion:completion];
        return;
    }
    BOOL hasSupportedType = picker.mediaTypes.count == 0;
    for (NSString *identifier in picker.mediaTypes) {
        UTType *type = [UTType typeWithIdentifier:identifier];
        hasSupportedType |= [type conformsToType:UTTypeImage] || [type conformsToType:UTTypeMovie];
    }
    if (!hasSupportedType) {
        [self pp_presentViewController:viewController animated:animated completion:completion];
        return;
    }
    UIAlertController *choice = [UIAlertController alertControllerWithTitle:@"Select media"
        message:@"Choose Photos or Files. Files supports a single image or video." preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIViewController *weakPresenter = self;
    __weak UIAlertController *weakChoice = choice;
    void (^afterChoice)(void (^)(UIViewController *)) = ^(void (^next)(UIViewController *)) {
        UIViewController *presenter = weakPresenter;
        UIAlertController *sheet = weakChoice;
        if (!presenter) return;
        void (^run)(void) = ^{ next(presenter); };
        if (sheet.presentingViewController) [sheet dismissViewControllerAnimated:YES completion:run];
        else dispatch_async(dispatch_get_main_queue(), run);
    };
    [choice addAction:[UIAlertAction actionWithTitle:@"Photo Library" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        afterChoice(^(UIViewController *presenter) {
            objc_setAssociatedObject(picker, &PPBypassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [presenter presentViewController:picker animated:animated completion:completion];
        });
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Browse Files" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        afterChoice(^(UIViewController *presenter) {
            PPDocumentBridge *bridge = [[PPDocumentBridge alloc] initWithPicker:picker presenter:presenter];
            NSMutableArray<UTType *> *types = [NSMutableArray array];
            BOOL imageAllowed = picker.mediaTypes.count == 0;
            BOOL movieAllowed = NO;
            for (NSString *identifier in picker.mediaTypes) {
                UTType *accepted = [UTType typeWithIdentifier:identifier];
                imageAllowed |= [accepted conformsToType:UTTypeImage];
                movieAllowed |= [accepted conformsToType:UTTypeMovie];
            }
            if (imageAllowed) [types addObject:UTTypeImage];
            if (movieAllowed) [types addObject:UTTypeMovie];
            UIDocumentPickerViewController *document = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
            document.allowsMultipleSelection = NO;
            document.shouldShowFileExtensions = YES;
            document.delegate = bridge;
            bridge.documentPicker = document;
            // The original UIImagePickerController remains a real presented
            // controller. Its delegate may dismiss that exact object, inspect its
            // presenter, or start uploading in its dismissal completion block.
            objc_setAssociatedObject(document, &PPBridgeKey, bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(picker, &PPBridgeKey, bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(picker, &PPBypassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [presenter presentViewController:picker animated:NO completion:^{
                NSString *testFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"PickerPatcherTestDirectory"];
                if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"dev.pickerpatcher.bridgehost"] && testFolder) {
                    document.directoryURL = [NSURL fileURLWithPath:testFolder isDirectory:YES];
                }
                [picker presentViewController:document animated:animated completion:completion];
            }];
        });
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        afterChoice(^(UIViewController *presenter) {
            objc_setAssociatedObject(picker, &PPBypassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [presenter presentViewController:picker animated:NO completion:^{
                if (completion) completion();
                id<UIImagePickerControllerDelegate> delegate = picker.delegate;
                if ([delegate respondsToSelector:@selector(imagePickerControllerDidCancel:)]) [delegate imagePickerControllerDidCancel:picker];
                else [picker dismissViewControllerAnimated:YES completion:nil];
            }];
        });
    }]];
    UIPopoverPresentationController *popover = choice.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:choice animated:animated completion:nil];
}
@end

__attribute__((constructor)) static void PickerPatcherStart(void) {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.apple."]) return;
        // The same process may accidentally load both a runtime tweak and an
        // embedded copy. A selector key is shared across dynamic images.
        const void *hookKey = NSSelectorFromString(@"PickerPatcherInstalledV06");
        if (objc_getAssociatedObject(UIViewController.class, hookKey)) return;
        objc_setAssociatedObject(UIViewController.class, hookKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ PPPruneOldFiles(); });
        Method original = class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:));
        Method replacement = class_getInstanceMethod(UIViewController.class, @selector(pp_presentViewController:animated:completion:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
