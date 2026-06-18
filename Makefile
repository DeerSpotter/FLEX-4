ifeq ($(SIMULATOR),1)
	export ARCHS = arm64 x86_64
	export TARGET = simulator:clang::15.0
else
	export THEOS_PACKAGE_SCHEME = rootless
	export ARCHS = arm64 arm64e
	export TARGET = iphone:latest:15.0
endif

ifneq ($(wildcard tools/flex4-app-injection-fix.py),)
$(shell python3 tools/flex4-app-injection-fix.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/flex4-autoflex-option-a.py),)
$(shell python3 tools/flex4-autoflex-option-a.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/add-setter-value-search.py),)
$(shell python3 tools/add-setter-value-search.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/flex4-global-autoshow-default.py),)
$(shell python3 tools/flex4-global-autoshow-default.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/flex4-beta-polish.py),)
$(shell python3 tools/flex4-beta-polish.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/flex4-force-open-apps.py),)
$(shell python3 tools/flex4-force-open-apps.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/fix-force-open-reload.py),)
$(shell python3 tools/fix-force-open-reload.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/fix-force-open-duplicate-block.py),)
$(shell python3 tools/fix-force-open-duplicate-block.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/flex4-force-open-logs.py),)
$(shell python3 tools/flex4-force-open-logs.py >/dev/null 2>&1 || true)
endif

ifneq ($(wildcard tools/fix-override-message-newline.py),)
$(shell python3 tools/fix-override-message-newline.py >/dev/null 2>&1 || true)
endif

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FLEXing
$(TWEAK_NAME)_GENERATOR = internal
$(TWEAK_NAME)_FILES = Tweak.xm SpringBoard.xm Shared/FLEXingConfig.m
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation CoreFoundation
$(TWEAK_NAME)_CFLAGS += -fobjc-arc -w -IShared

include $(THEOS_MAKE_PATH)/tweak.mk

before-stage::
	find . -name ".DS_Store" -delete

# For printing variables from the makefile
print-%  : ; @echo $* = $($*)

SUBPROJECTS += libflex
include $(THEOS_MAKE_PATH)/aggregate.mk
