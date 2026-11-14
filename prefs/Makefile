TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CamFixPrefs
CamFixPrefs_FILES = CMXRootListController.m
CamFixPrefs_FRAMEWORKS = UIKit
CamFixPrefs_LDFLAGS = -undefined dynamic_lookup
CamFixPrefs_INSTALL_PATH = /Library/PreferenceBundles
CamFixPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
