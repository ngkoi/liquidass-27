export TARGET ?= iphone:clang:16.5:14.0
export ARCHS ?= arm64 arm64e
export THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidAssBackboardd

LiquidAssBackboardd_FILES     = $(wildcard *.mm)
LiquidAssBackboardd_CFLAGS    = -fobjc-arc -std=c++17 -fno-objc-arc-exceptions
LiquidAssBackboardd_FRAMEWORKS = Metal QuartzCore CoreFoundation
LiquidAssBackboardd_LDFLAGS   = -lc++
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
LiquidAssBackboardd_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk
