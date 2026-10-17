#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <string.h>

// Objective-C classes register before constructors. Distinct product names keep
// two images from fighting over class implementations before the hook guard.
#if defined(PP_EMBEDDED) && PP_EMBEDDED
#define PPStatus PPEmbeddedStatus07
#define PPSession PPEmbeddedSession07
#else
#define PPStatus PPRuntimeStatus07
#define PPSession PPRuntimeSession07
#endif

// This is built independently for the jailbreak loader and the IPA framework.
// Shared selector keys make loading both images safe; no Objective-C categories.
static const void *PPKey(NSString *name) { return NSSelectorFromString([@"PickerPatcher07" stringByAppendingString:name]); }
static IMP PPOriginalPresent, PPOriginalAppear, PPOriginalWebMenu;
static BOOL PPWebInstalled;
static NSString *PPLastController = @"No presentation observed yet";
static NSUInteger PPMatches;
const char *PickerPatcherVersion(void) { return "0.7.0"; }

static BOOL PPEnabled(void) {
    return ![NSUserDefaults.standardUserDefaults boolForKey:@"PickerPatcherDisabled"] &&
        ![NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/Library/PickerPatcher/disabled"];
}
static NSURL *PPLogURL(void);
static NSMutableArray *PPEvents(void) {
    @synchronized(UIViewController.class) {
        NSMutableArray *events = objc_getAssociatedObject(UIViewController.class, PPKey(@"Events"));
        if (!events) {
            NSString *previous=[NSString stringWithContentsOfURL:PPLogURL() encoding:NSUTF8StringEncoding error:nil];
            events=[[previous componentsSeparatedByString:@"\n"] mutableCopy]?:[NSMutableArray array];
            if (events.count>150) [events removeObjectsInRange:NSMakeRange(0,events.count-150)];
            objc_setAssociatedObject(UIViewController.class, PPKey(@"Events"), events, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return events;
    }
}
static NSURL *PPLogURL(void) {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"PickerPatcher-runtime.txt"];
}
static void PPLog(NSString *event) {
    // No filenames, media contents, URLs, account details or request bodies.
    NSMutableArray *events = PPEvents();
    @synchronized(events) {
        [events addObject:[NSString stringWithFormat:@"%.3f %@", NSDate.date.timeIntervalSince1970, event]];
        if (events.count > 200) [events removeObjectsInRange:NSMakeRange(0, events.count-200)];
        [[events componentsJoinedByString:@"\n"] writeToURL:PPLogURL() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
static void PPCallPresent(UIViewController *host, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    ((void (*)(id,SEL,id,BOOL,id))PPOriginalPresent)(host,@selector(presentViewController:animated:completion:),controller,animated,completion);
}
static UIWindow *PPWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) return window;
        }
    }
    id<UIApplicationDelegate> delegate=UIApplication.sharedApplication.delegate;
    return [delegate respondsToSelector:@selector(window)] ? delegate.window : nil;
}
static UIViewController *PPTop(void) {
    UIViewController *top = PPWindow().rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}
static void PPAnchor(UIAlertController *sheet, UIViewController *host) {
    sheet.popoverPresentationController.sourceView = host.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),CGRectGetMidY(host.view.bounds),1,1);
}
static void PPDismiss(UIViewController *controller, void (^finish)(void)) {
    if (!controller || !controller.presentingViewController) { dispatch_async(dispatch_get_main_queue(),finish); return; }
    if (controller.isBeingDismissed) {
        // Files/UIAlert can begin automatic dismissal before invoking a delegate.
        // A second dismiss call may never execute its completion. Join the real
        // transition instead, or wait until UIKit clears the presenter.
        id<UIViewControllerTransitionCoordinator> transition=controller.transitionCoordinator;
        if (transition && [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            if (context.isCancelled) PPDismiss(controller,finish); else finish();
        }]) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ PPDismiss(controller,finish); });
        return;
    }
    [controller dismissViewControllerAnimated:YES completion:finish];
}
static void PPAfterSheet(UIAlertController *sheet, void (^block)(void)) { PPDismiss(sheet,block); }
static BOOL PPMethodMatches(Method method, const char *arguments) {
    if (!method || method_getNumberOfArguments(method)!=strlen(arguments)+2) return NO;
    char *ret=method_copyReturnType(method); BOOL match=ret && ret[0]=='@'; free(ret);
    for (unsigned int index=0; arguments[index]; index++) {
        char *arg=method_copyArgumentType(method,index+2);
        BOOL valid=arg && (arg[0]==arguments[index] || (arguments[index]=='B' && arg[0]=='c'));
        free(arg); if (!valid) match=NO;
    }
    return match;
}
static SEL PPResultConstructor(void) {
    SEL legacy=NSSelectorFromString(@"_initWithItemProvider:assetIdentifier:");
    if (PPMethodMatches(class_getInstanceMethod(PHPickerResult.class,legacy),"@@")) return legacy;
    // The item-based initializer is also present in iOS18 runtime headers.
    // Only select it when its exact object/object/bool/object ABI matches.
    SEL item=NSSelectorFromString(@"_initWithItemProvider:itemIdentifier:isAssetResult:metadata:");
    return PPMethodMatches(class_getInstanceMethod(PHPickerResult.class,item),"@@B@")?item:NULL;
}
static BOOL PPResultInitializerAvailable(void) { return PPResultConstructor()!=NULL; }
static PHPickerResult *PPResult(NSItemProvider *provider) {
    SEL selector=PPResultConstructor(); if (!selector) return nil;
    @try {
        id result;
        if (selector==NSSelectorFromString(@"_initWithItemProvider:assetIdentifier:")) {
            result=((id (*)(id,SEL,id,id))objc_msgSend)([PHPickerResult alloc],selector,provider,nil);
        } else {
            // A file-item identity is not a Photos asset identity. False keeps
            // assetIdentifier nil; metadata is not fabricated from a PHAsset.
            result=((id (*)(id,SEL,id,id,BOOL,id))objc_msgSend)([PHPickerResult alloc],selector,provider,NSUUID.UUID.UUIDString,NO,nil);
        }
        return [result isKindOfClass:PHPickerResult.class] && [result itemProvider]==provider && [result assetIdentifier]==nil ? result : nil;
    } @catch (__unused NSException *exception) { PPLog(@"PhotosUI initializer rejected provider"); return nil; }
}

@interface PPStatus : NSObject
+ (void)attach;
+ (void)show:(id)sender;
+ (void)move:(UIPanGestureRecognizer *)gesture;
@end
@implementation PPStatus
+ (void)attach {
    UIWindow *window = PPWindow();
    if (!window) return;
    UIButton *existing=objc_getAssociatedObject(window,PPKey(@"Button"));
    if (existing) { [window bringSubviewToFront:existing]; return; }
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"PP" forState:UIControlStateNormal];
    button.accessibilityIdentifier = @"pickerPatcherStatus";
    button.accessibilityLabel = @"PickerPatcher injection status";
    button.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.9];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.layer.cornerRadius = 18;
    button.frame = CGRectMake(MAX(4,window.bounds.size.width-52),MAX(window.safeAreaInsets.top+8,window.bounds.size.height-window.safeAreaInsets.bottom-76),40,36);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(move:)]];
    [button addTarget:self action:@selector(show:) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];
    objc_setAssociatedObject(window,PPKey(@"Button"),button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
+ (void)move:(UIPanGestureRecognizer *)gesture {
    UIView *button=gesture.view; UIView *window=button.superview;
    CGPoint translation=[gesture translationInView:window];
    CGPoint center=CGPointMake(button.center.x+translation.x,button.center.y+translation.y);
    center.x=MIN(MAX(center.x,24),window.bounds.size.width-24);
    center.y=MIN(MAX(center.y,window.safeAreaInsets.top+24),window.bounds.size.height-window.safeAreaInsets.bottom-24);
    button.center=center; [gesture setTranslation:CGPointZero inView:window];
}
+ (void)show:(id)sender {
    UIViewController *host = PPTop();
    if (!host || [host isKindOfClass:UIAlertController.class]) return;
    NSString *message = [NSString stringWithFormat:@"Framework loaded: 0.7.0\niOS %@\nInterception: %@\nUIImagePicker: installed\nPHPicker result bridge: %@\nWebKit upload menu: %@\nMatched presentations: %lu\nLast controller: %@\n\nCustom galleries need their own callback adapter. Share diagnostics after reproducing a missed upload.",UIDevice.currentDevice.systemVersion,PPEnabled()?@"enabled":@"disabled",PPResultInitializerAvailable()?@"available":@"unavailable (original retained)",PPWebInstalled?@"installed":@"unavailable",(unsigned long)PPMatches,PPLastController];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PickerPatcher runtime" message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Share runtime diagnostics" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        PPAfterSheet(weakAlert,^{
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[PPLogURL()] applicationActivities:nil];
            share.popoverPresentationController.sourceView = host.view;
            share.popoverPresentationController.sourceRect = CGRectMake(10,10,1,1);
            PPCallPresent(host,share,YES,nil);
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:PPEnabled()?@"Disable interception":@"Enable interception" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [NSUserDefaults.standardUserDefaults setBool:PPEnabled() forKey:@"PickerPatcherDisabled"];
        PPLog(@"Interception preference changed");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hide PP button until restart" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [(UIView *)sender setHidden:YES]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    PPCallPresent(host,alert,YES,nil);
}
@end

// A file is staged once. The original name is preserved in an isolated session.
// The file outlives picker dismissal and any lazily requested item representation.
static NSDictionary *PPStage(NSURL *source, BOOL allowImage, BOOL allowVideo, NSString **failure) {
    BOOL scoped = [source startAccessingSecurityScopedResource];
    __block NSURL *staged;
    __block NSString *problem;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSError *coordinationError;
    [coordinator coordinateReadingItemAtURL:source options:0 error:&coordinationError byAccessor:^(NSURL *readURL) {
        NSNumber *size, *regular;
        [readURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        [readURL getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        unsigned long long bytes = size.unsignedLongLongValue;
        unsigned long long freeBytes = [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSTemporaryDirectory() error:nil][NSFileSystemFreeSize] unsignedLongLongValue];
        NSString *tmpPrefix = [[[NSURL fileURLWithPath:NSTemporaryDirectory()].URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"] copy];
        BOOL movable = [readURL.URLByResolvingSymlinksInPath.path hasPrefix:tmpPrefix];
        unsigned long long extra = movable?0:bytes;
        if (!regular.boolValue || !bytes || bytes > 2ULL*1024*1024*1024 || extra > freeBytes || freeBytes-extra < 256ULL*1024*1024) {
            problem = @"The file is unreadable, too large, or there is insufficient working space."; return;
        }
        NSURL *folder = [[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:@"PickerPatcher" isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSError *error;
        if (![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error]) { problem=error.localizedDescription; return; }
        NSURL *destination = [folder URLByAppendingPathComponent:source.lastPathComponent?:@"media"];
        BOOL stored = movable ? [NSFileManager.defaultManager moveItemAtURL:readURL toURL:destination error:&error] : [NSFileManager.defaultManager copyItemAtURL:readURL toURL:destination error:&error];
        if (!stored) { problem=error.localizedDescription; [NSFileManager.defaultManager removeItemAtURL:folder error:nil]; return; }
        staged=destination;
    }];
    if (scoped) [source stopAccessingSecurityScopedResource];
    if (!staged) { *failure=problem?:coordinationError.localizedDescription?:@"File provider access failed."; return nil; }
    NSString *identifier;
    CGImageSourceRef image = CGImageSourceCreateWithURL((__bridge CFURLRef)staged,NULL);
    if (image) {
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(image,0,NULL));
        unsigned long long w=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue],h=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
        identifier = [(__bridge NSString *)CGImageSourceGetType(image) copy];
        CFRelease(image);
        if (!allowImage || !w || !h || w>12000 || h>12000 || w*h>32000000) problem=@"This picker does not accept this image, or its dimensions exceed the 32 megapixel limit.";
    } else {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:staged options:nil];
        UTType *type = [UTType typeWithFilenameExtension:staged.pathExtension];
        if (!allowVideo || ![type conformsToType:UTTypeMovie] || [asset tracksWithMediaType:AVMediaTypeVideo].count==0) problem=@"This picker does not accept this file as an image or video.";
        identifier=type.identifier;
    }
    if (problem || !identifier) { [NSFileManager.defaultManager removeItemAtURL:staged.URLByDeletingLastPathComponent error:nil]; *failure=problem?:@"Unknown media type."; return nil; }
    return @{@"url":staged,@"type":identifier,@"image":@([[UTType typeWithIdentifier:identifier] conformsToType:UTTypeImage])};
}
static NSItemProvider *PPProvider(NSDictionary *media) {
    NSURL *url=media[@"url"]; NSString *type=media[@"type"];
    NSItemProvider *provider=[NSItemProvider new];
    provider.suggestedName=url.lastPathComponent;
    [provider registerFileRepresentationForTypeIdentifier:type fileOptions:0 visibility:NSItemProviderRepresentationVisibilityAll loadHandler:^NSProgress *(void (^done)(NSURL *,BOOL,NSError *)) {
        done(url,NO,nil); return nil;
    }];
    [provider registerDataRepresentationForTypeIdentifier:type visibility:NSItemProviderRepresentationVisibilityAll loadHandler:^NSProgress *(void (^done)(NSData *,NSError *)) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            unsigned long long size=[[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil][NSFileSize] unsignedLongLongValue];
            NSError *error; NSData *data;
            if (size<=128ULL*1024*1024) data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
            else error=[NSError errorWithDomain:@"PickerPatcher" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Use the file representation for media above 128 MiB."}];
            done(data,error);
        }); return nil;
    }];
    if ([media[@"image"] boolValue]) {
        [provider registerObjectOfClass:UIImage.class visibility:NSItemProviderRepresentationVisibilityAll loadHandler:^NSProgress *(void (^done)(id<NSItemProviderWriting>,NSError *)) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                UIImage *image=[UIImage imageWithContentsOfFile:url.path];
                done(image,image?nil:[NSError errorWithDomain:@"PickerPatcher" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Image decoding failed."}]);
            }); return nil;
        }];
    }
    return provider;
}

@interface PPSession : NSObject <UIDocumentPickerDelegate>
@property(nonatomic,strong) UIViewController *picker;
@property(nonatomic,strong) UIViewController *container;
@property(nonatomic,strong) UIDocumentPickerViewController *document;
@property(nonatomic) BOOL modern, images, videos, processing;
@property(nonatomic) NSUInteger limit;
- (void)cancel;
- (void)openFiles:(BOOL)animated completion:(void (^)(void))completion;
@end
@implementation PPSession
- (void)end {
    objc_setAssociatedObject(self.document,PPKey(@"Session"),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self.picker,PPKey(@"Session"),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.document=nil;
}
- (void)cancel {
    PPLog(self.modern?@"PHPicker cancel callback":@"UIImagePicker cancel callback");
    if (self.modern) {
        PHPickerViewController *picker=(id)self.picker;
        [picker.delegate picker:picker didFinishPicking:@[]];
    } else {
        UIImagePickerController *picker=(id)self.picker;
        if ([picker.delegate respondsToSelector:@selector(imagePickerControllerDidCancel:)]) [picker.delegate imagePickerControllerDidCancel:picker];
        else [self.container dismissViewControllerAnimated:YES completion:nil];
    }
    [self end];
}
- (void)closeDocument:(void (^)(void))finish {
    PPDismiss(self.document,finish);
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (self.processing) return;
    self.processing=YES;
    [self closeDocument:^{ [self cancel]; }];
}
- (void)fail:(NSString *)message {
    PPLog(@"Media delivery failed (validation or adapter)");
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Could not deliver media" message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { PPAfterSheet(weakAlert,^{ [self cancel]; }); }]];
    PPCallPresent(self.container,alert,YES,nil);
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url { [self documentPicker:controller didPickDocumentsAtURLs:@[url]]; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.processing) return;
    self.processing=YES;
    PPLog([NSString stringWithFormat:@"Files callback; count=%lu",(unsigned long)urls.count]);
    if (!urls.count || urls.count>self.limit) { [self closeDocument:^{ [self fail:@"Selection exceeds the allowed count (maximum 32 files). Choose fewer files."]; }]; return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSMutableArray *items=[NSMutableArray array]; NSString *failure;
        for (NSURL *url in urls) { NSDictionary *item=PPStage(url,self.images,self.videos,&failure); if (!item) break; [items addObject:item]; }
        NSMutableArray *results=[NSMutableArray array]; UIImage *decoded;
        if (!failure && self.modern) {
            for (NSDictionary *item in items) { PHPickerResult *result=PPResult(PPProvider(item)); if (!result) { failure=@"This iOS build cannot construct a compatible Photos item-provider result. Use Photo Library."; break; } [results addObject:result]; }
        } else if (!failure && [items.firstObject[@"image"] boolValue]) {
            decoded=[UIImage imageWithContentsOfFile:[items.firstObject[@"url"] path]];
            if (!decoded) failure=@"Image decoding failed.";
        }
        if (failure) for (NSDictionary *item in items) [NSFileManager.defaultManager removeItemAtURL:[item[@"url"] URLByDeletingLastPathComponent] error:nil];
        dispatch_async(dispatch_get_main_queue(),^{
            [self closeDocument:^{
                if (failure) { [self fail:failure]; return; }
                if (self.modern) {
                    PHPickerViewController *picker=(id)self.picker;
                    PPLog([NSString stringWithFormat:@"PHPicker callback; result count=%lu; asset IDs=nil",(unsigned long)results.count]);
                    [picker.delegate picker:picker didFinishPicking:results];
                } else {
                    NSDictionary *item=items.firstObject;
                    NSMutableDictionary *info=[NSMutableDictionary dictionary];
                    if ([item[@"image"] boolValue]) { info[UIImagePickerControllerMediaType]=UTTypeImage.identifier; info[UIImagePickerControllerOriginalImage]=decoded; info[UIImagePickerControllerImageURL]=item[@"url"]; }
                    else { info[UIImagePickerControllerMediaType]=UTTypeMovie.identifier; info[UIImagePickerControllerMediaURL]=item[@"url"]; }
                    UIImagePickerController *picker=(id)self.picker;
                    PPLog(@"UIImagePicker media callback delivered");
                    [picker.delegate imagePickerController:picker didFinishPickingMediaWithInfo:info];
                }
                [self end];
            }];
        });
    });
}
- (void)openFiles:(BOOL)animated completion:(void (^)(void))completion {
    NSMutableArray *types=[NSMutableArray array];
    if (self.images) [types addObject:UTTypeImage]; if (self.videos) [types addObject:UTTypeMovie];
    self.document=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    self.document.allowsMultipleSelection=self.limit>1;
    self.document.modalPresentationStyle=UIModalPresentationFullScreen;
    self.document.shouldShowFileExtensions=YES; self.document.delegate=self;
    NSString *testDirectory=[NSUserDefaults.standardUserDefaults stringForKey:@"PickerPatcherTestDirectory"];
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"dev.pickerpatcher.bridgehost"] && testDirectory) self.document.directoryURL=[NSURL fileURLWithPath:testDirectory isDirectory:YES];
    objc_setAssociatedObject(self.document,PPKey(@"Session"),self,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self.picker,PPKey(@"Session"),self,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PPCallPresent(self.container,self.document,animated,completion);
}
@end

static UIViewController *PPFind(UIViewController *controller) {
    if ([controller isKindOfClass:UIImagePickerController.class] || [controller isKindOfClass:PHPickerViewController.class]) return controller;
    for (UIViewController *child in controller.childViewControllers) { UIViewController *found=PPFind(child); if (found) return found; }
    return nil;
}
static PPSession *PPSessionFor(UIViewController *picker, UIViewController *container) {
    PPSession *session=[PPSession new]; session.picker=picker; session.container=container;
    if ([picker isKindOfClass:UIImagePickerController.class]) {
        UIImagePickerController *legacy=(id)picker;
        if (legacy.sourceType==UIImagePickerControllerSourceTypeCamera) { PPLog(@"Camera retained"); return nil; }
        if (legacy.allowsEditing || ![legacy.delegate respondsToSelector:@selector(imagePickerController:didFinishPickingMediaWithInfo:)]) { PPLog(@"UIImagePicker retained: editing or unsupported delegate"); return nil; }
        session.images=legacy.mediaTypes.count==0;
        for (NSString *identifier in legacy.mediaTypes) { UTType *type=[UTType typeWithIdentifier:identifier]; session.images|=[type conformsToType:UTTypeImage]; session.videos|=[type conformsToType:UTTypeMovie]; }
        session.limit=1;
    } else {
        session.modern=YES;
        PHPickerViewController *modern=(id)picker; PHPickerConfiguration *config=modern.configuration;
        if (!PPResultInitializerAvailable()) { PPLog(@"PHPicker retained: result initializer unavailable"); return nil; }
        if (![modern.delegate respondsToSelector:@selector(picker:didFinishPicking:)]) { PPLog(@"PHPicker retained: delegate unavailable or incompatible"); return nil; }
        SEL onlyIDs=NSSelectorFromString(@"_onlyReturnsIdentifiers");
        if (config.preselectedAssetIdentifiers.count || ([config respondsToSelector:onlyIDs] && ((BOOL (*)(id,SEL))objc_msgSend)(config,onlyIDs))) { PPLog(@"PHPicker retained: Photos identity/preselection contract"); return nil; }
        PHPickerFilter *filter=config.filter;
        if (!filter) { session.images=YES; session.videos=YES; }
        else if ([filter isEqual:PHPickerFilter.imagesFilter]) session.images=YES;
        else if ([filter isEqual:PHPickerFilter.videosFilter]) session.videos=YES;
        else if ([filter isEqual:[PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter,PHPickerFilter.videosFilter]]]) { session.images=YES; session.videos=YES; }
        else { PPLog(@"PHPicker retained: specialized filter needs adapter"); return nil; }
        session.limit=config.selectionLimit==0?32:MIN((NSUInteger)config.selectionLimit,32);
    }
    return session.images||session.videos?session:nil;
}
static BOOL PPOffer(UIViewController *host, UIViewController *container, UIViewController *picker, BOOL alreadyPresented, BOOL animated, void (^completion)(void)) {
    PPSession *session=PPSessionFor(picker,container); if (!session) return NO;
    PPMatches++; objc_setAssociatedObject(picker,PPKey(@"Offered"),@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PPLog(session.modern?@"Matched PHPicker item-provider adapter":@"Matched UIImagePicker adapter");
    UIAlertController *choice=[UIAlertController alertControllerWithTitle:@"Select media" message:session.modern?@"Photos or Files. Files returns item providers without Photos asset identifiers.":@"Choose Photos or Files." preferredStyle:UIAlertControllerStyleActionSheet];
    PPAnchor(choice,host);
    __weak UIAlertController *weakChoice=choice;
    void (^presentOriginal)(void (^)(void))=^(void (^after)(void)) {
        if (alreadyPresented) { if (after) after(); }
        else PPCallPresent(host,container,animated,after);
    };
    [choice addAction:[UIAlertAction actionWithTitle:@"Photo Library" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { PPAfterSheet(weakChoice,^{ presentOriginal(completion); }); }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Browse Files" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { PPAfterSheet(weakChoice,^{ presentOriginal(^{ [session openFiles:animated completion:completion]; }); }); }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) { PPAfterSheet(weakChoice,^{ presentOriginal(^{ if(completion)completion(); [session cancel]; }); }); }]];
    PPCallPresent(host,choice,animated,nil); return YES;
}
static void PPPresent(UIViewController *host, __unused SEL sel, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    PPLastController=NSStringFromClass(controller.class);
    PPLog([@"Present " stringByAppendingString:PPLastController]);
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"dev.pickerpatcher.bridgehost"] && [controller isKindOfClass:UIDocumentPickerViewController.class]) {
        NSString *folder=[NSUserDefaults.standardUserDefaults stringForKey:@"PickerPatcherTestDirectory"];
        if (folder) ((UIDocumentPickerViewController *)controller).directoryURL=[NSURL fileURLWithPath:folder isDirectory:YES];
    }
    UIViewController *picker=PPEnabled()?PPFind(controller):nil;
    if (picker && PPOffer(host,controller,picker,NO,animated,completion)) return;
    PPCallPresent(host,controller,animated,completion);
}
static void PPAppear(UIViewController *controller, SEL sel, BOOL animated) {
    ((void (*)(id,SEL,BOOL))PPOriginalAppear)(controller,sel,animated);
    [PPStatus attach];
    PPLog([@"Appeared " stringByAppendingString:NSStringFromClass(controller.class)]);
    // Catches navigation pushes, containment and presentation overrides calling
    // super's appearance lifecycle. Never guesses a custom gallery's delegate.
    if (!PPEnabled() || objc_getAssociatedObject(controller,PPKey(@"Offered"))) return;
    if (![controller isKindOfClass:UIImagePickerController.class] && ![controller isKindOfClass:PHPickerViewController.class]) return;
    objc_setAssociatedObject(controller,PPKey(@"Offered"),@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *container=controller;
        while (container.parentViewController) container=container.parentViewController;
        if (controller.view.window && !container.presentedViewController) PPOffer(container,container,controller,YES,YES,nil);
    });
}
static void PPWebMenu(id panel, SEL sel) {
    if (!PPEnabled()) { ((void (*)(id,SEL))PPOriginalWebMenu)(panel,sel); return; }
    PPMatches++; PPLog(@"Matched WebKit upload panel; native document delegate retained");
    // Let WebKit create the document picker and coordinate files/send sandbox
    // extensions to its WebContent process. No JavaScript FileList spoofing.
    ((void (*)(id,SEL))objc_msgSend)(panel,NSSelectorFromString(@"showFilePickerMenu"));
}
static void PPPrune(void) {
    NSURL *folder=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"PickerPatcher" isDirectory:YES];
    NSDate *cutoff=[NSDate dateWithTimeIntervalSinceNow:-86400];
    for (NSURL *entry in [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]) {
        NSDate *date; [entry getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        if (date && [date compare:cutoff]==NSOrderedAscending) [NSFileManager.defaultManager removeItemAtURL:entry error:nil];
    }
}
__attribute__((constructor)) static void PPStart(void) {
    @autoreleasepool {
        const void *key=PPKey(@"Installed");
        if (objc_getAssociatedObject(UIViewController.class,key)) return;
        Method present=class_getInstanceMethod(UIViewController.class,@selector(presentViewController:animated:completion:));
        Method appear=class_getInstanceMethod(UIViewController.class,@selector(viewDidAppear:));
        if (!present || !appear) return;
        PPOriginalPresent=method_getImplementation(present); PPOriginalAppear=method_getImplementation(appear);
        objc_setAssociatedObject(UIViewController.class,key,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        method_setImplementation(present,(IMP)PPPresent); method_setImplementation(appear,(IMP)PPAppear);
        Class web=NSClassFromString(@"WKFileUploadPanel");
        Method menu=class_getInstanceMethod(web,NSSelectorFromString(@"showDocumentPickerMenu"));
        Method files=class_getInstanceMethod(web,NSSelectorFromString(@"showFilePickerMenu"));
        char *menuReturn=menu?method_copyReturnType(menu):NULL, *filesReturn=files?method_copyReturnType(files):NULL;
        if (menu && files && method_getNumberOfArguments(menu)==2 && method_getNumberOfArguments(files)==2 && menuReturn && filesReturn && menuReturn[0]=='v' && filesReturn[0]=='v') {
            PPOriginalWebMenu=method_getImplementation(menu); method_setImplementation(menu,(IMP)PPWebMenu); PPWebInstalled=YES;
        }
        free(menuReturn); free(filesReturn);
        PPLog([NSString stringWithFormat:@"Loaded 0.7.0; iOS %@; PHPicker constructor=%@; WebKit=%@",UIDevice.currentDevice.systemVersion,PPResultConstructor()?NSStringFromSelector(PPResultConstructor()):@"unavailable",PPWebInstalled?@"yes":@"no"]);
        if (!PPResultInitializerAvailable()) {
            unsigned int count=0; Method *methods=class_copyMethodList(PHPickerResult.class,&count);
            for (unsigned int i=0;i<count;i++) {
                NSString *name=NSStringFromSelector(method_getName(methods[i]));
                if ([name containsString:@"init"]) PPLog([NSString stringWithFormat:@"PhotosUI runtime method %@ %s",name,method_getTypeEncoding(methods[i])]);
            }
            free(methods);
        }
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { [PPStatus attach]; }];
        dispatch_async(dispatch_get_main_queue(),^{ [PPStatus attach]; });
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ PPPrune(); });
    }
}
