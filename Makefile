TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = WeChat

# macOS CI: ad-hoc codesign via system codesign (ldid is not on runners).
ifeq ($(shell uname -s),Darwin)
TARGET_CODESIGN = /usr/bin/codesign
TARGET_CODESIGN_FLAGS = -f -s -
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WXSubtext
WXSubtext_FILES = Tweak.x $(wildcard Core/*.m) $(wildcard UI/*.m) $(wildcard Hook/*.m)
WXSubtext_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ICore -IUI -IHook

include $(THEOS_MAKE_PATH)/tweak.mk
