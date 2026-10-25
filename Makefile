# 本补丁只支持 roothide + arm64e
ifneq ($(THEOS_PACKAGE_SCHEME),roothide)
$(warning Choicy-Whitelist is built for roothide only, forcing THEOS_PACKAGE_SCHEME=roothide)
override THEOS_PACKAGE_SCHEME = roothide
endif

export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64e
export DEBUG = 0
FINALPACKAGE = 1

# roothide devkit（官方 libroothide 0.0.1，见 roothide-devkit/SOURCE.md）
ROOTHIDE_DIR = $(CURDIR)/roothide-devkit
export ADDITIONAL_CFLAGS += -I$(ROOTHIDE_DIR)
export ADDITIONAL_LDFLAGS += -L$(ROOTHIDE_DIR)/roothide -lroothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Choicy

Choicy_FILES = Tweak.c Tweak.s nextstep_plist.c $(wildcard external/litehook/src/*.c)
Choicy_CFLAGS = -DTHEOS_LEAN_AND_MEAN -I./external/litehook/src -I./external/litehook/external/include -I$(ROOTHIDE_DIR)

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += ChoicyPrefs
SUBPROJECTS += ChoicySB
include $(THEOS_MAKE_PATH)/aggregate.mk
