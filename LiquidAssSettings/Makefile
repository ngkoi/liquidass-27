include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidAssSettings

LiquidAssSettings_FILES = Tweak.x \
                		  ../LiquidAssPrefs/LGPrefsLiquidSlider.m \
                       	  ../LiquidAssPrefs/LGPrefsLiquidSwitch.m \
                          ../Shared/LGFramework.m \
                          ../Shared/LGLiveBackdropView.m \
                          $(abspath ../Shared/LGGlassKit.x) \
                          ../Shared/LGSharedSupport.m
LiquidAssSettings_CFLAGS = -fobjc-arc
LiquidAssSettings_USE_MODULES = 0
LiquidAssSettings_FRAMEWORKS = UIKit QuartzCore CoreText CoreGraphics CoreMotion

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
LiquidAssSettings_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk
