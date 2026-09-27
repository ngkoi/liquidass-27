export TARGET 		?= iphone:clang:16.5:14.0
export ARCHS 		?= arm64 arm64e
export THEOS_PACKAGE_SCHEME ?= rootless
export USE_DEPS 	?= 1

CCACHE := $(shell command -v ccache 2>/dev/null)
ifeq ($(shell uname -s),Darwin)
export TARGET_CC 	:= $(CCACHE) $(shell xcrun -f clang)
export TARGET_CXX 	:= $(CCACHE) $(shell xcrun -f clang++)
endif

INSTALL_TARGET_PROCESSES = backboardd SpringBoard assistivetouchd
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = liquidass27

liquidass27_FILES     = Tweak.x \
                        $(filter-out Hooks/Clock.x, $(wildcard Hooks/*.x)) \
                        $(wildcard Hooks/Clock/*.[xm]) \
                        $(wildcard LiquidAssPrefs/LGPrefsLiquid*.m) \
                        $(wildcard Shared/*.[xm])
liquidass27_CFLAGS    = -fobjc-arc
liquidass27_USE_MODULES = 0
liquidass27_FRAMEWORKS = UIKit QuartzCore CoreText CoreGraphics CoreMotion
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
liquidass27_LIBRARIES += roothide
endif

include $(THEOS)/makefiles/tweak.mk
SUBPROJECTS += LiquidAssBackboardd LiquidAssRWB LiquidAssPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
