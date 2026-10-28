#import <Foundation/Foundation.h>
#import "../App/AppLibrary.h"

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface TKWoWBackupManager : NSObject

/// Returns the root directory path for a given product (e.g. Documents/World of Warcraft/_classic_beta_).
+ (NSString *)productDirectoryForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library;

/// Returns YES if either WTF or Interface/AddOns folder exists and has content for this product.
+ (BOOL)hasBackupDataForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library;

/// Creates a ZIP archive containing WTF and Interface for the product.
/// Calls completion on the main thread with the temporary file URL or an error.
+ (void)createBackupArchiveForProduct:(NSDictionary *)product
                              library:(nullable TKAppLibrary *)library
                             progress:(nullable void (^)(NSString *status))progress
                           completion:(void (^)(NSURL * _Nullable archiveURL, NSError * _Nullable error))completion;

/// Restores a backup ZIP archive from a local file URL into the product folder.
/// Automatically locates WTF and Interface within the archive, creates a safety backup of existing files, and extracts.
/// Calls completion on the main thread with success status, summary description, or error.
+ (void)restoreBackupFromArchiveURL:(NSURL *)archiveURL
                         forProduct:(NSDictionary *)product
                            library:(nullable TKAppLibrary *)library
                           progress:(nullable void (^)(NSString *status))progress
                         completion:(void (^)(BOOL success, NSString * _Nullable summary, NSError * _Nullable error))completion;

/// Unzips raw ZIP data into destination directory with path traversal and binary protection.
+ (BOOL)unzipData:(NSData *)zipData toDirectory:(NSString *)destination error:(NSError **)error;

#if __has_include(<UIKit/UIKit.h>)
/// Presents UIActivityViewController allowing the user to export the backup via Files, AirDrop, etc.
+ (void)presentExportForProduct:(NSDictionary *)product
                        library:(nullable TKAppLibrary *)library
             fromViewController:(UIViewController *)viewController
                     anchorItem:(nullable UIBarButtonItem *)barButtonItem;

/// Presents UIDocumentPickerViewController to pick a backup ZIP and restore it.
+ (void)presentImportForProduct:(NSDictionary *)product
                        library:(nullable TKAppLibrary *)library
             fromViewController:(UIViewController *)viewController
                     completion:(nullable void (^)(BOOL success))onComplete;
#endif

@end

NS_ASSUME_NONNULL_END
