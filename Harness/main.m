#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <WebKit/WebKit.h>

static BOOL HarnessPresented(UIViewController *controller) {
    while (controller.parentViewController) controller=controller.parentViewController;
    return controller.presentingViewController!=nil;
}

@interface HarnessWebController : UIViewController <WKScriptMessageHandler>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UILabel *result;
@end
@implementation HarnessWebController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Web upload contract"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    [config.userContentController addScriptMessageHandler:self name:@"upload"];
    self.web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.web.translatesAutoresizingMaskIntoConstraints=NO;
    self.result=[UILabel new]; self.result.translatesAutoresizingMaskIntoConstraints=NO; self.result.numberOfLines=0;
    self.result.accessibilityIdentifier=@"webResult"; self.result.text=@"Waiting for a real HTML file input change event.";
    [self.view addSubview:self.web]; [self.view addSubview:self.result];
    [NSLayoutConstraint activateConstraints:@[
        [self.web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.web.heightAnchor constraintEqualToConstant:300],
        [self.result.topAnchor constraintEqualToAnchor:self.web.bottomAnchor constant:20],
        [self.result.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.result.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20]]];
    NSString *html=@"<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{padding:30px;font:18px -apple-system}input{margin-top:30px;height:60px;width:100%}</style><label for='upload'>Upload an image from Files</label><input id='upload' aria-label='Choose upload image' type='file' accept='image/*'><script>document.getElementById('upload').addEventListener('change',function(){const file=this.files[0];if(!file)return;const r=new FileReader();r.onload=function(){const img=new Image();img.onload=function(){window.webkit.messageHandlers.upload.postMessage({bytes:file.size,width:img.width});};img.onerror=function(){window.webkit.messageHandlers.upload.postMessage({bytes:0,width:0});};img.src=r.result;};r.readAsDataURL(file);});</script>";
    [self.web loadHTMLString:html baseURL:nil];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *value=[message.body isKindOfClass:NSDictionary.class]?message.body:@{};
    self.result.text=[value[@"bytes"] unsignedLongLongValue]>0 && [value[@"width"] integerValue]>0 ? @"PASS web; input change=yes; bytes=yes; image decode=yes" : @"FAIL web upload data";
}
@end

#if __has_include("PickerBridgeHost-Swift.h")
#import "PickerBridgeHost-Swift.h"
#elif __has_include("PickerHarness-Swift.h")
#import "PickerHarness-Swift.h"
#else
#error The harness requires its generated Swift interface
#endif

@interface HarnessController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate>
@property(nonatomic, strong) UILabel *result;
@property(nonatomic, strong) id providerDelegate;
@end
@implementation HarnessController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"Picker contract test";
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24]
    ]];
    NSArray *titles = @[@"Select image", @"Select video", @"Editing picker (original)", @"PHPicker image", @"PHPicker multiple", @"Wrapped image picker", @"Web upload test"];
    NSArray *ids = @[@"harnessImage", @"harnessVideo", @"harnessEditing", @"harnessPHPicker", @"harnessPHMultiple", @"harnessWrapped", @"harnessWeb"];
    for (NSInteger i=0; i<titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.accessibilityIdentifier = ids[i];
        button.tag = i;
        [button addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    self.result = [[UILabel alloc] init];
    self.result.numberOfLines = 0;
    self.result.accessibilityIdentifier = @"harnessResult";
    const char *(*version)(void)=dlsym(RTLD_DEFAULT,"PickerPatcherVersion");
    self.result.text=version ? [NSString stringWithFormat:@"Injected framework %s loaded. Ready for native upload tests.",version()] : @"No injected framework loaded (unpatched harness).";
    UILabel *loaded=[UILabel new]; loaded.accessibilityIdentifier=@"injectionResult";
    loaded.text=version?@"Injected framework 0.7.0":@"Unpatched harness";
    [stack addArrangedSubview:loaded];
    [stack addArrangedSubview:self.result];
    NSURL *folder = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Fixtures" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64,64)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0,0,64,64));
    }];
    [UIImagePNGRepresentation(image) writeToURL:[folder URLByAppendingPathComponent:@"PickerBridge.png"] atomically:YES];
    [UIImagePNGRepresentation(image) writeToURL:[folder URLByAppendingPathComponent:@"PickerBridge2.png"] atomically:YES];
    [[NSUserDefaults standardUserDefaults] setObject:folder.path forKey:@"PickerPatcherTestDirectory"];
}
- (void)choose:(UIButton *)button {
    if (button.tag == 6) { [self.navigationController pushViewController:[HarnessWebController new] animated:YES]; return; }
    if (button.tag == 3 || button.tag == 4) {
        PPProviderDelegate *probe=[[PPProviderDelegate alloc] initWithResultLabel:self.result];
        self.providerDelegate=probe;
        PHPickerViewController *picker=[probe makePickerWithSelectionLimit:button.tag==4?2:1];
        if (![picker.delegate respondsToSelector:@selector(picker:didFinishPicking:)]) {
            self.result.text=@"FAIL Swift overlay delegate adapter unavailable";
            return;
        }
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = button.tag == 1 ? @[UTTypeMovie.identifier] : @[UTTypeImage.identifier];
    picker.allowsEditing = button.tag == 2;
    picker.delegate = self;
    UIViewController *container=picker;
    if (button.tag==5) {
        container=[UIViewController new]; [container addChildViewController:picker];
        picker.view.frame=container.view.bounds;
        picker.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [container.view addSubview:picker.view]; [picker didMoveToParentViewController:container];
    }
    [self presentViewController:container animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    BOOL presented = HarnessPresented(picker);
    NSURL *url = info[UIImagePickerControllerImageURL] ?: info[UIImagePickerControllerMediaURL];
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    BOOL isImage = [info[UIImagePickerControllerMediaType] isEqualToString:UTTypeImage.identifier];
    [picker dismissViewControllerAnimated:YES completion:^{
        BOOL dismissed = !HarnessPresented(picker);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            unsigned long long bytes = 0;
            if (url) {
                NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
                [stream open];
                uint8_t buffer[64 * 1024];
                NSInteger length;
                while ((length = [stream read:buffer maxLength:sizeof(buffer)]) > 0) bytes += length;
                [stream close];
            }
            BOOL valid = presented && dismissed && bytes > 0 && (!isImage || image != nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.result.text = [NSString stringWithFormat:@"%@ %@; presenter=%@; dismiss=%@; bytes=%llu", valid ? @"PASS" : @"FAIL", isImage ? @"image" : @"video", presented ? @"yes" : @"no", dismissed ? @"yes" : @"no", bytes];
            });
        });
    }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    BOOL presented = HarnessPresented(picker);
    [picker dismissViewControllerAnimated:YES completion:^{
        self.result.text = presented && !HarnessPresented(picker) ? @"PASS cancel; presenter=yes; dismiss=yes" : @"FAIL cancel lifecycle";
    }];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:^{ self.result.text=@"FAIL expected the Swift PHPicker delegate"; }];
}
@end
@interface HarnessAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation HarnessAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--double-hook"]) {
        NSURL *second = [NSBundle.mainBundle URLForResource:@"PickerPatcherSecond" withExtension:@"dylib"];
        void *handle = second ? dlopen(second.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL) : NULL;
        NSAssert(handle != NULL, @"The independent second hook image must load");
    }
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[HarnessController new]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(HarnessAppDelegate.class)); }
}
