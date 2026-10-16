TARGET = iphone:clang:latest:15.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = PickerPatcher
PickerPatcher_FILES = Core/PickerPatcher.m
PickerPatcher_FRAMEWORKS = UIKit UniformTypeIdentifiers ImageIO AVFoundation
PickerPatcher_CFLAGS = -fobjc-arc -Wall -Wextra

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
