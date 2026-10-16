#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>

@interface HarnessController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate>
@property(nonatomic, strong) UILabel *result;
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
    NSArray *titles = @[@"Select image", @"Select video", @"Editing picker (original)", @"PHPicker (original)"];
    NSArray *ids = @[@"harnessImage", @"harnessVideo", @"harnessEditing", @"harnessPHPicker"];
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
    self.result.text = @"Ready. Select media, check callback identity, dismiss, then read the file in chunks.";
    [stack addArrangedSubview:self.result];
    NSURL *folder = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Fixtures" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64,64)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0,0,64,64));
    }];
    [UIImagePNGRepresentation(image) writeToURL:[folder URLByAppendingPathComponent:@"PickerBridge.png"] atomically:YES];
    [[NSUserDefaults standardUserDefaults] setObject:folder.path forKey:@"PickerPatcherTestDirectory"];
}
- (void)choose:(UIButton *)button {
    if (button.tag == 3) {
        PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
        configuration.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = button.tag == 1 ? @[UTTypeMovie.identifier] : @[UTTypeImage.identifier];
    picker.allowsEditing = button.tag == 2;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    BOOL presented = picker.presentingViewController != nil;
    NSURL *url = info[UIImagePickerControllerImageURL] ?: info[UIImagePickerControllerMediaURL];
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    BOOL isImage = [info[UIImagePickerControllerMediaType] isEqualToString:UTTypeImage.identifier];
    [picker dismissViewControllerAnimated:YES completion:^{
        BOOL dismissed = picker.presentingViewController == nil;
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
    BOOL presented = picker.presentingViewController != nil;
    [picker dismissViewControllerAnimated:YES completion:^{
        self.result.text = presented && picker.presentingViewController == nil ? @"PASS cancel; presenter=yes; dismiss=yes" : @"FAIL cancel lifecycle";
    }];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:^{ self.result.text = @"Original PHPicker callback received; no synthetic Photos asset created."; }];
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
