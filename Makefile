TARGET = iphone:clang:latest:16.0
ARCHS = arm64

LIBRARY_NAME = ClaudeUnlock
ClaudeUnlock_FILES = ClaudeUnlock.mm CUURLProtocol.mm CUPatch.mm
ClaudeUnlock_FRAMEWORKS = Foundation
ClaudeUnlock_CFLAGS = -fobjc-arc -fvisibility=hidden -DCU_DEBUG=1
ClaudeUnlock_LDFLAGS = -install_name @executable_path/Frameworks/ClaudeUnlock.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/library.mk
