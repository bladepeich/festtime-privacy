#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.ruben.FestTime";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "festtime-logo" asset catalog image resource.
static NSString * const ACImageNameFesttimeLogo AC_SWIFT_PRIVATE = @"festtime-logo";

/// The "lcda-logo-dark" asset catalog image resource.
static NSString * const ACImageNameLcdaLogoDark AC_SWIFT_PRIVATE = @"lcda-logo-dark";

/// The "lcda-logo-light" asset catalog image resource.
static NSString * const ACImageNameLcdaLogoLight AC_SWIFT_PRIVATE = @"lcda-logo-light";

#undef AC_SWIFT_PRIVATE
