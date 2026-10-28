#import <Foundation/Foundation.h>
#import "../App/AppLibrary.h"
NS_ASSUME_NONNULL_BEGIN

static inline NSString * _Nonnull TKSafeString(id _Nullable val, NSString * _Nullable fallback) {
    if ([val isKindOfClass:NSString.class]) return (NSString *)val;
    return fallback ?: @"";
}

static inline NSNumber * _Nullable TKSafeNumber(id _Nullable val, NSNumber * _Nullable fallback) {
    if ([val isKindOfClass:NSNumber.class]) return (NSNumber *)val;
    return fallback;
}

@interface TKWoWAddonManager : NSObject

// CurseForge API Key configuration.
+ (nullable NSString *)apiKey;
+ (void)setApiKey:(nullable NSString *)apiKey;
+ (BOOL)hasApiKey;

// Directory management.
+ (NSString *)addonsDirectoryForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library;

// Local installed add-ons.
+ (NSArray<NSDictionary *> *)installedAddonsForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library;
+ (BOOL)uninstallAddon:(NSDictionary *)addon forProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library error:(NSError **)error;

// Edition compatibility helpers.
+ (BOOL)file:(NSDictionary *)file matchesProduct:(NSString *)productId;
+ (nullable NSDictionary *)bestFileForProduct:(NSString *)productId fromFiles:(NSArray<NSDictionary *> *)files;

// ZIP decompression and TOC parsing helpers.
+ (BOOL)unzipData:(NSData *)zipData toDirectory:(NSString *)destination extractedFolders:(NSArray<NSString *> * _Nullable * _Nullable)outFolders error:(NSError **)error;
+ (NSDictionary *)parseTOCData:(NSData *)data;

// CurseForge API operations.
- (void)searchAddonsWithQuery:(nullable NSString *)query
                      product:(NSDictionary *)product
                   completion:(void (^)(NSArray<NSDictionary *> * _Nullable results, NSError * _Nullable error))completion;

- (void)fetchFilesForModId:(NSNumber *)modId
                completion:(void (^)(NSArray<NSDictionary *> * _Nullable files, NSError * _Nullable error))completion;

- (void)installAddon:(NSDictionary *)addon
                file:(nullable NSDictionary *)selectedFile
             product:(NSDictionary *)product
             library:(nullable TKAppLibrary *)library
            progress:(nullable void (^)(float progress, NSString *status))progress
          completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
