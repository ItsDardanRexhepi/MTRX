#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.opnmatrx.mtrx";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "AccentPrimary" asset catalog color resource.
static NSString * const ACColorNameAccentPrimary AC_SWIFT_PRIVATE = @"AccentPrimary";

/// The "AccentSecondary" asset catalog color resource.
static NSString * const ACColorNameAccentSecondary AC_SWIFT_PRIVATE = @"AccentSecondary";

/// The "AccentTertiary" asset catalog color resource.
static NSString * const ACColorNameAccentTertiary AC_SWIFT_PRIVATE = @"AccentTertiary";

/// The "PriceDown" asset catalog color resource.
static NSString * const ACColorNamePriceDown AC_SWIFT_PRIVATE = @"PriceDown";

/// The "PriceUp" asset catalog color resource.
static NSString * const ACColorNamePriceUp AC_SWIFT_PRIVATE = @"PriceUp";

/// The "SurfaceCard" asset catalog color resource.
static NSString * const ACColorNameSurfaceCard AC_SWIFT_PRIVATE = @"SurfaceCard";

/// The "SurfaceElevated" asset catalog color resource.
static NSString * const ACColorNameSurfaceElevated AC_SWIFT_PRIVATE = @"SurfaceElevated";

/// The "TrinityPrimary" asset catalog color resource.
static NSString * const ACColorNameTrinityPrimary AC_SWIFT_PRIVATE = @"TrinityPrimary";

/// The "TrinityProcessing" asset catalog color resource.
static NSString * const ACColorNameTrinityProcessing AC_SWIFT_PRIVATE = @"TrinityProcessing";

/// The "TrinitySecondary" asset catalog color resource.
static NSString * const ACColorNameTrinitySecondary AC_SWIFT_PRIVATE = @"TrinitySecondary";

#undef AC_SWIFT_PRIVATE
