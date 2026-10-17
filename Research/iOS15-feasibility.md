# PickerPatcher feasibility research · 16 October 2026

## Findings that determine the implementation

| Area | Verified source and consequence |
| --- | --- |
| Rootless package | [Theos rootless](https://theos.dev/docs/rootless) sets `/var/jb` paths, `iphoneos-arm64` package architecture, and iOS 15 minimum. [Theos packaging](https://theos.dev/docs/packaging) documents the `Filter/Bundles` plist. The `.deb` uses an exact list of bundle IDs. |
| Host compiler | [Theos macOS installation](https://theos.dev/docs/installation-macos) requires full Xcode, not just Command Line Tools. GitHub's [macOS runner inventory](https://github.com/actions/runner-images) supplies Xcode/iPhoneOS SDK on `macos-15`. The workflow discovers the selected SDK instead of assuming iOS 15 SDK is installed. |
| Files picker | Apple documents [`UIDocumentPickerViewController initForOpeningContentTypes:`](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init%28foropeningcontenttypes%3A%29?language=objc) and security-scoped URL access in [document selection](https://developer.apple.com/documentation/uikit/providing-access-to-directories). The bridge coordinates a read, checks space, and copies one file into the target app's sandbox. |
| UIKit callback | [`UIImagePickerControllerDelegate`](https://developer.apple.com/documentation/uikit/uiimagepickercontrollerdelegate?language=objc) provides `imagePickerController:didFinishPickingMediaWithInfo:` and cancellation. The implementation supplies image or movie info, but it does not reproduce every possible app assumption. |
| Modern picker | [`PHPickerResult`](https://developer.apple.com/documentation/photosui/phpickerresult-c.class?language=objc) exposes an item provider and an optional Photos asset identifier. There is no documented public initializer for constructing a result from a Files URL. The PHPicker path is left intact pending explicit, app-tested integration. |
| Embedded code | Apple [bundle placement](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle) and [developer guidance](https://developer.apple.com/forums/thread/670761) support placing iOS library code in an app-level framework. The same source is compiled into an embedded framework with no ElleKit/substrate linkage. |
| Load command | [LIEF's Mach-O modification guide](https://lief.re/doc/latest/tutorials/11_macho_modification.html) explains the load-command padding constraint. Our shared C injector accepts only thin arm64 and verifies free zero padding before writing `LC_LOAD_DYLIB`; a binary lacking space is rejected. Its old signature is invalid after patching. |
| Signing | Apple [code-signature format guidance](https://developer.apple.com/documentation/xcode/using-the-latest-code-signature-format) requires iOS 15 compatible DER entitlements for applicable apps and signing nested code before the app. [GitHub's certificate guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications) uses secrets and a temporary keychain. An unsigned IPA is identified as such. |
| TrollStore | Its [README](https://github.com/opa334/TrollStore) documents iOS 15 support and re-signing on installation. [Its document declaration](https://github.com/opa334/TrollStore/blob/main/TrollStoreLite/Resources/Info.plist) associates `.ipa` with the app. [Its installer source](https://github.com/opa334/TrollStore/blob/main/RootHelper/main.m) calls `signApp` when installing; this supports a local share-sheet handoff, with on-device testing still required. |
| ZIP packaging | [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) provides iOS ZIP extraction/creation; pin version 0.9.20. Validate archive paths, symlinks, expanded size, and free space before extraction. [XcodeGen](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) declares an exact Swift package version in the generated app project. |

## Compatibility matrix

| Input/app workflow | Installed `.deb` | Embedded IPA | Media handoff |
| --- | --- | --- | --- |
| Standard UIKit photo library, single image/movie, no editing | Build path exists | CI and on-device patch paths exist for simple unencrypted IPA | UIKit delegate dictionary, requires device test |
| `PHPickerViewController` | Original picker unchanged | Original picker unchanged | No synthetic `PHPickerResult` |
| Custom gallery, Photos asset ID, edited image contract | Original flow where detectable; otherwise target-specific test | Same | Requires dedicated adapter |
| Encrypted App Store executable | Runtime mode can operate on installed app | IPA tool rejects | No decryption feature |
| IPA with extensions/nested apps | Runtime injection can target the main bundle | IPA tool rejects pending per-extension signing | No universal claim |
| Original binary has no room for the load command | Runtime mode unaffected | Injector fails closed | No IPA output |
| Fat, arm64e-only or encrypted IPA executable | Runtime mode may still apply | On-device patcher rejects | No exported IPA |

## Security and operational decisions

- The repository never includes a third-party app binary, provisioning profile, or signing certificate. IPA mode operates on a user-provided, authorized, unencrypted input.
- The IPA tool rejects ZIP traversal and links, unusually large expansion, and insufficient disk space before extraction. It preserves the original input and writes output atomically.
- A signed IPA is created only with an explicit identity, matching profile, and authorized entitlements; the tool verifies the signature after signing. Install/launch remains a separate on-device gate.
- On a 32 GB device, the `.deb` avoids duplicating the installed app. The on-device patcher refuses IPAs when free space cannot cover its extracted contents and export with a margin; macOS CI remains useful for large IPAs.
- UIKit hook coverage and upload completion are runtime behavior and have not been tested on a device in this environment.

## Unresolved implementation work

1. Build the action in an actual GitHub repository and inspect the produced `.deb`, patcher `.ipa`, and framework load commands.
2. Test app launch, Photos, Files image, Files movie, cancel, and cloud provider on iOS 15 with Dopamine; inspect app logs for contract mismatches.
3. Add an explicit per-app adapter for PHPicker or custom picker only after identifying the target app and its callback/data requirements.
4. Expand IPA signing to nested extensions with matching profiles and entitlement sets if a target app requires them.
