ifeq ($(SIMULATOR),1)
	export ARCHS = arm64 x86_64
	export TARGET = simulator:clang::15.0
else
	export THEOS_PACKAGE_SCHEME = rootless
	export ARCHS = arm64 arm64e
	export TARGET = iphone:latest:15.0
endif

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FLEXing
$(TWEAK_NAME)_GENERATOR = internal
$(TWEAK_NAME)_FILES = Tweak.xm SpringBoard.xm Shared/FLEXingConfig.m
$(TWEAK_NAME)_FRAMEWORKS = Foundation CoreFoundation
$(TWEAK_NAME)_CFLAGS += -fobjc-arc -w -IShared

APPLICATION_NAME = FLEXingManager
$(APPLICATION_NAME)_FILES = \
	FLEXingManager/main.m \
	FLEXingManager/FLEXingAppDelegate.m \
	FLEXingManager/FLEXingRootViewController.m \
	FLEXingManager/FLEXingAppSettingsViewController.m \
	Shared/FLEXingConfig.m
$(APPLICATION_NAME)_FRAMEWORKS = UIKit CoreGraphics Foundation CoreFoundation
$(APPLICATION_NAME)_CFLAGS += -fobjc-arc -w -IShared
$(APPLICATION_NAME)_RESOURCE_DIRS = FLEXingManager/Resources
$(APPLICATION_NAME)_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/application.mk

before-stage::
	find . -name ".DS_Store" -delete

# For printing variables from the makefile
print-%  : ; @echo $* = $($*)

SUBPROJECTS += libflex
include $(THEOS_MAKE_PATH)/aggregate.mk
