#import "BackupManager.h"
#import <zlib.h>

static inline uint16_t ReadLE16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static inline uint32_t ReadLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static NSError *BackupError(NSString *description, NSInteger code) {
    return [NSError errorWithDomain:@"org.tolkara.wow-backup"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

#if __has_include(<UIKit/UIKit.h>)

@interface TKWoWImportCoordinator : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSDictionary *product;
@property (nonatomic, strong, nullable) TKAppLibrary *library;
@property (nonatomic, weak) UIViewController *presentingViewController;
@property (nonatomic, copy, nullable) void (^completion)(BOOL success);
@property (nonatomic, strong, nullable) TKWoWImportCoordinator *strongSelf;
@end

@implementation TKWoWImportCoordinator

- (void)start {
    self.strongSelf = self;
    Class utTypeClass = NSClassFromString(@"UTType");
    id zipType = nil;
    if (utTypeClass && [utTypeClass respondsToSelector:@selector(typeWithIdentifier:)]) {
        zipType = [utTypeClass performSelector:@selector(typeWithIdentifier:) withObject:@"public.zip-archive"];
        if (!zipType) zipType = [utTypeClass performSelector:@selector(typeWithIdentifier:) withObject:@"public.archive"];
    }
    NSArray *types = zipType ? @[zipType] : @[];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self.presentingViewController presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    if (self.completion) self.completion(NO);
    self.strongSelf = nil;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *selectedURL = urls.firstObject;
    if (!selectedURL) {
        if (self.completion) self.completion(NO);
        self.strongSelf = nil;
        return;
    }

    NSString *fileName = selectedURL.lastPathComponent;
    NSString *productName = self.product[@"name"] ?: @"this edition";

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Restore Backup"
        message:[NSString stringWithFormat:@"This will restore WTF settings (macros, keybindings) and Add-ons from \"%@\" into %@.\n\nExisting files will be replaced. A safety backup of your current settings will be preserved.\n\nDo you want to continue?", fileName, productName]
        preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        (void)a;
        if (self.completion) self.completion(NO);
        self.strongSelf = nil;
    }]];

    [confirm addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)a;
        [self performRestoreFromURL:selectedURL];
    }]];

    [self.presentingViewController presentViewController:confirm animated:YES completion:nil];
}

- (void)performRestoreFromURL:(NSURL *)archiveURL {
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"Restoring Backup"
                                                                           message:@"Reading archive…"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [self.presentingViewController presentViewController:progressAlert animated:YES completion:^{
        [TKWoWBackupManager restoreBackupFromArchiveURL:archiveURL forProduct:self.product library:self.library progress:^(NSString *status) {
            progressAlert.message = status;
        } completion:^(BOOL success, NSString * _Nullable summary, NSError * _Nullable error) {
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (!success || error) {
                    UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Restore Incomplete"
                                                                                   message:error.localizedDescription ?: @"Failed to unpack or restore archive."
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self.presentingViewController presentViewController:errAlert animated:YES completion:nil];
                } else {
                    UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:@"Backup Restored"
                                                                                    message:summary ?: @"Backup files restored successfully."
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                    [doneAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self.presentingViewController presentViewController:doneAlert animated:YES completion:nil];
                }
                if (self.completion) self.completion(success);
                self.strongSelf = nil;
            }];
        }];
    }];
}

@end
#endif

@implementation TKWoWBackupManager

+ (NSString *)productDirectoryForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library {
    NSString *root = nil;
    if (library) {
        for (TKApp *app in library.apps) {
            NSString *workDir = [library workingDirectoryForApp:app error:NULL];
            if (workDir) {
                root = workDir.stringByDeletingLastPathComponent;
                break;
            }
        }
    }
    if (!root) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        root = [docs stringByAppendingPathComponent:@"World of Warcraft"];
    }
    NSString *folder = product[@"folder"] ?: @"_classic_beta_";
    return [root stringByAppendingPathComponent:folder];
}

+ (BOOL)hasBackupDataForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library {
    NSString *productDir = [self productDirectoryForProduct:product library:library];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *wtfPath = [productDir stringByAppendingPathComponent:@"WTF"];
    NSString *ifacePath = [productDir stringByAppendingPathComponent:@"Interface"];

    BOOL isDir = NO;
    if ([fm fileExistsAtPath:wtfPath isDirectory:&isDir] && isDir) {
        NSArray *items = [fm contentsOfDirectoryAtPath:wtfPath error:NULL];
        if (items.count > 0) return YES;
    }
    if ([fm fileExistsAtPath:ifacePath isDirectory:&isDir] && isDir) {
        NSArray *items = [fm contentsOfDirectoryAtPath:ifacePath error:NULL];
        if (items.count > 0) return YES;
    }
    return NO;
}

+ (void)createBackupArchiveForProduct:(NSDictionary *)product
                              library:(nullable TKAppLibrary *)library
                             progress:(nullable void (^)(NSString *status))progress
                           completion:(void (^)(NSURL * _Nullable archiveURL, NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(@"Locating game settings and add-ons…"); });
        }

        NSString *productDir = [self productDirectoryForProduct:product library:library];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *wtfPath = [productDir stringByAppendingPathComponent:@"WTF"];
        NSString *ifacePath = [productDir stringByAppendingPathComponent:@"Interface"];

        BOOL isDir = NO;
        BOOL hasWTF = [fm fileExistsAtPath:wtfPath isDirectory:&isDir] && isDir;
        BOOL hasIface = [fm fileExistsAtPath:ifacePath isDirectory:&isDir] && isDir;

        if (!hasWTF && !hasIface) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, BackupError(@"No WTF settings or Add-ons found to back up.", 201));
            });
            return;
        }

        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(@"Preparing backup files…"); });
        }

        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd-HHmmss";
        NSString *timestamp = [df stringFromDate:NSDate.date];
        NSString *folderName = product[@"folder"] ?: @"_classic_beta_";
        NSString *slug = [folderName stringByReplacingOccurrencesOfString:@"_" withString:@""];
        if (!slug.length) slug = @"wow";
        NSString *stagingName = [NSString stringWithFormat:@"Wolkara-Backup-%@-%@", slug, timestamp];
        NSString *stagingDir = [NSTemporaryDirectory() stringByAppendingPathComponent:stagingName];
        [fm removeItemAtPath:stagingDir error:NULL];
        [fm createDirectoryAtPath:stagingDir withIntermediateDirectories:YES attributes:nil error:NULL];

        NSError *copyErr = nil;
        if (hasWTF) {
            if (![fm copyItemAtPath:wtfPath toPath:[stagingDir stringByAppendingPathComponent:@"WTF"] error:&copyErr]) {
                [fm removeItemAtPath:stagingDir error:NULL];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, copyErr ?: BackupError(@"Failed to copy WTF directory.", 202));
                });
                return;
            }
        }
        if (hasIface) {
            if (![fm copyItemAtPath:ifacePath toPath:[stagingDir stringByAppendingPathComponent:@"Interface"] error:&copyErr]) {
                [fm removeItemAtPath:stagingDir error:NULL];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, copyErr ?: BackupError(@"Failed to copy Interface directory.", 203));
                });
                return;
            }
        }

        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(@"Compressing ZIP archive…"); });
        }

        NSURL *stagingURL = [NSURL fileURLWithPath:stagingDir];
        NSFileCoordinator *coord = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError *coordErr = nil;
        NSString *zipFilename = [stagingName stringByAppendingPathExtension:@"zip"];
        NSString *finalZipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:zipFilename];
        [fm removeItemAtPath:finalZipPath error:NULL];

        __block NSError *writeErr = nil;
        [coord coordinateReadingItemAtURL:stagingURL options:NSFileCoordinatorReadingForUploading error:&coordErr byAccessor:^(NSURL *tempZipURL) {
            if (tempZipURL) {
                [fm copyItemAtURL:tempZipURL toURL:[NSURL fileURLWithPath:finalZipPath] error:&writeErr];
            } else {
                writeErr = BackupError(@"Archive creation failed.", 204);
            }
        }];
        [fm removeItemAtPath:stagingDir error:NULL];

        if (coordErr || writeErr || ![fm fileExistsAtPath:finalZipPath]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, coordErr ?: (writeErr ?: BackupError(@"Failed to generate ZIP archive.", 205)));
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion([NSURL fileURLWithPath:finalZipPath], nil);
        });
    });
}

+ (void)findWTF:(NSString **)outWTF andInterface:(NSString **)outInterface inDirectory:(NSString *)dir {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *wtf = nil;
    NSString *iface = nil;

    // 1. Direct match at root of extract directory
    NSString *candidateWTF = [dir stringByAppendingPathComponent:@"WTF"];
    NSString *candidateIface = [dir stringByAppendingPathComponent:@"Interface"];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:candidateWTF isDirectory:&isDir] && isDir) wtf = candidateWTF;
    if ([fm fileExistsAtPath:candidateIface isDirectory:&isDir] && isDir) iface = candidateIface;

    if (wtf && iface) {
        if (outWTF) *outWTF = wtf;
        if (outInterface) *outInterface = iface;
        return;
    }

    // 2. Check 1 level down (e.g. Wolkara-Backup-.../WTF or _classic_beta_/WTF)
    NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        NSString *sub = [dir stringByAppendingPathComponent:item];
        if (![fm fileExistsAtPath:sub isDirectory:&isDir] || !isDir) continue;

        if (!wtf) {
            NSString *subWTF = [sub stringByAppendingPathComponent:@"WTF"];
            if ([fm fileExistsAtPath:subWTF isDirectory:&isDir] && isDir) wtf = subWTF;
        }
        if (!iface) {
            NSString *subIface = [sub stringByAppendingPathComponent:@"Interface"];
            if ([fm fileExistsAtPath:subIface isDirectory:&isDir] && isDir) iface = subIface;
        }
        if (wtf && iface) break;
    }

    // 3. Check 2 levels down (e.g. World of Warcraft/_classic_beta_/WTF)
    if (!wtf || !iface) {
        for (NSString *item in contents) {
            if ([item hasPrefix:@"."]) continue;
            NSString *sub = [dir stringByAppendingPathComponent:item];
            if (![fm fileExistsAtPath:sub isDirectory:&isDir] || !isDir) continue;
            NSArray *subContents = [fm contentsOfDirectoryAtPath:sub error:NULL];
            for (NSString *subItem in subContents) {
                if ([subItem hasPrefix:@"."]) continue;
                NSString *subSub = [sub stringByAppendingPathComponent:subItem];
                if (![fm fileExistsAtPath:subSub isDirectory:&isDir] || !isDir) continue;
                if (!wtf) {
                    NSString *deepWTF = [subSub stringByAppendingPathComponent:@"WTF"];
                    if ([fm fileExistsAtPath:deepWTF isDirectory:&isDir] && isDir) wtf = deepWTF;
                }
                if (!iface) {
                    NSString *deepIface = [subSub stringByAppendingPathComponent:@"Interface"];
                    if ([fm fileExistsAtPath:deepIface isDirectory:&isDir] && isDir) iface = deepIface;
                }
                if (wtf && iface) break;
            }
            if (wtf && iface) break;
        }
    }

    // 4. Fallback: if someone zipped an AddOns folder directly without Interface/
    if (!iface) {
        NSString *candidateAddons = [dir stringByAppendingPathComponent:@"AddOns"];
        if ([fm fileExistsAtPath:candidateAddons isDirectory:&isDir] && isDir) {
            NSString *wrapper = [dir stringByAppendingPathComponent:@"_Synthesized_Interface"];
            [fm createDirectoryAtPath:wrapper withIntermediateDirectories:YES attributes:nil error:NULL];
            [fm moveItemAtPath:candidateAddons toPath:[wrapper stringByAppendingPathComponent:@"AddOns"] error:NULL];
            iface = wrapper;
        }
    }

    if (outWTF) *outWTF = wtf;
    if (outInterface) *outInterface = iface;
}

+ (void)restoreBackupFromArchiveURL:(NSURL *)archiveURL
                         forProduct:(NSDictionary *)product
                            library:(nullable TKAppLibrary *)library
                           progress:(nullable void (^)(NSString *status))progress
                         completion:(void (^)(BOOL success, NSString * _Nullable summary, NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(@"Reading backup archive…"); });
        }

        BOOL access = [archiveURL startAccessingSecurityScopedResource];
        NSFileCoordinator *coord = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block NSData *zipData = nil;
        NSError *readErr = nil;
        [coord coordinateReadingItemAtURL:archiveURL options:0 error:&readErr byAccessor:^(NSURL *newURL) {
            zipData = [NSData dataWithContentsOfURL:newURL];
        }];
        if (access) [archiveURL stopAccessingSecurityScopedResource];

        if (!zipData || zipData.length < 22) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, readErr ?: BackupError(@"Invalid or empty backup archive.", 301));
            });
            return;
        }

        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(@"Extracting archive contents…"); });
        }

        NSString *extractDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"wolkara-restore-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtPath:extractDir error:NULL];
        [fm createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:NULL];

        NSError *unzipErr = nil;
        if (![self unzipData:zipData toDirectory:extractDir error:&unzipErr]) {
            [fm removeItemAtPath:extractDir error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, unzipErr ?: BackupError(@"Failed to unpack backup archive.", 302));
            });
            return;
        }

        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(@"Validating backup structure…"); });
        }

        NSString *foundWTF = nil;
        NSString *foundInterface = nil;
        [self findWTF:&foundWTF andInterface:&foundInterface inDirectory:extractDir];

        if (!foundWTF && !foundInterface) {
            [fm removeItemAtPath:extractDir error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, BackupError(@"The selected archive does not contain a valid WTF or Interface folder.", 303));
            });
            return;
        }

        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{ progress(@"Applying restored settings…"); });
        }

        NSString *productDir = [self productDirectoryForProduct:product library:library];
        [fm createDirectoryAtPath:productDir withIntermediateDirectories:YES attributes:nil error:NULL];

        // Create safety backup of existing files before replacing
        NSString *safetyDir = [productDir stringByAppendingPathComponent:@".backup_pre_restore"];
        [fm removeItemAtPath:safetyDir error:NULL];
        [fm createDirectoryAtPath:safetyDir withIntermediateDirectories:YES attributes:nil error:NULL];

        NSString *existingWTF = [productDir stringByAppendingPathComponent:@"WTF"];
        NSString *existingInterface = [productDir stringByAppendingPathComponent:@"Interface"];
        if ([fm fileExistsAtPath:existingWTF]) {
            [fm copyItemAtPath:existingWTF toPath:[safetyDir stringByAppendingPathComponent:@"WTF"] error:NULL];
        }
        if ([fm fileExistsAtPath:existingInterface]) {
            [fm copyItemAtPath:existingInterface toPath:[safetyDir stringByAppendingPathComponent:@"Interface"] error:NULL];
        }

        BOOL restoredWTF = NO;
        NSUInteger restoredAddonsCount = 0;

        if (foundWTF) {
            [fm removeItemAtPath:existingWTF error:NULL];
            if ([fm moveItemAtPath:foundWTF toPath:existingWTF error:NULL]) {
                restoredWTF = YES;
            }
        }

        if (foundInterface) {
            [fm removeItemAtPath:existingInterface error:NULL];
            if ([fm moveItemAtPath:foundInterface toPath:existingInterface error:NULL]) {
                NSString *addonsDir = [existingInterface stringByAppendingPathComponent:@"AddOns"];
                NSArray *addonItems = [fm contentsOfDirectoryAtPath:addonsDir error:NULL];
                for (NSString *name in addonItems) {
                    if (![name hasPrefix:@"."]) restoredAddonsCount++;
                }
            }
        }

        [fm removeItemAtPath:extractDir error:NULL];

        NSMutableString *summary = [NSMutableString new];
        if (restoredWTF && restoredAddonsCount > 0) {
            [summary appendFormat:@"Successfully restored WTF (macros, keybindings, settings) and %lu add-on(s).", (unsigned long)restoredAddonsCount];
        } else if (restoredWTF) {
            [summary appendString:@"Successfully restored WTF (macros, keybindings, settings)."];
        } else {
            [summary appendFormat:@"Successfully restored %lu add-on(s).", (unsigned long)restoredAddonsCount];
        }
        [summary appendString:@"\n\nA safety backup of your previous settings was saved to .backup_pre_restore."];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, summary, nil);
        });
    });
}

+ (BOOL)unzipData:(NSData *)zipData toDirectory:(NSString *)destination error:(NSError **)error {
    if (!zipData || zipData.length < 22) {
        if (error) *error = BackupError(@"Invalid or empty ZIP data.", 101);
        return NO;
    }

    const uint8_t *bytes = (const uint8_t *)zipData.bytes;
    NSUInteger length = zipData.length;

    // Locate End of Central Directory record (EOCD: "PK\x05\x06")
    int64_t maxComment = 65535;
    int64_t searchStart = (int64_t)length - 22;
    int64_t searchEnd = (int64_t)MAX(0, (int64_t)length - 22 - maxComment);
    int64_t eocdOffset = -1;

    for (int64_t p = searchStart; p >= searchEnd; p--) {
        if (bytes[p] == 0x50 && bytes[p+1] == 0x4b && bytes[p+2] == 0x05 && bytes[p+3] == 0x06) {
            eocdOffset = p;
            break;
        }
    }

    if (eocdOffset < 0) {
        if (error) *error = BackupError(@"Could not find ZIP End of Central Directory.", 102);
        return NO;
    }

    uint16_t entriesCount = ReadLE16(bytes + eocdOffset + 10);
    uint32_t cdOffset = ReadLE32(bytes + eocdOffset + 16);

    if (cdOffset > length) {
        if (error) *error = BackupError(@"Malformed ZIP central directory offset.", 103);
        return NO;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:NULL];

    uint32_t offset = cdOffset;
    uint64_t totalExtractedBytes = 0;

    for (int i = 0; i < entriesCount; i++) {
        if (offset + 46 > length) {
            if (error) *error = BackupError(@"ZIP entry header exceeds bounds.", 104);
            return NO;
        }
        if (memcmp(bytes + offset, "PK\x01\x02", 4) != 0) {
            if (error) *error = BackupError(@"Corrupted ZIP central directory header.", 105);
            return NO;
        }

        uint16_t method = ReadLE16(bytes + offset + 10);
        uint32_t expectedCrc = ReadLE32(bytes + offset + 16);
        uint32_t compSize = ReadLE32(bytes + offset + 20);
        uint32_t uncompSize = ReadLE32(bytes + offset + 24);
        uint16_t nameLen = ReadLE16(bytes + offset + 28);
        uint16_t extraLen = ReadLE16(bytes + offset + 30);
        uint16_t commentLen = ReadLE16(bytes + offset + 32);
        uint32_t localOffset = ReadLE32(bytes + offset + 42);

        if (nameLen == 0 || offset + 46 + nameLen > length) {
            if (error) *error = BackupError(@"Invalid ZIP entry filename length.", 106);
            return NO;
        }

        NSString *rawName = [[NSString alloc] initWithBytes:bytes + offset + 46 length:nameLen encoding:NSUTF8StringEncoding];
        if (!rawName) rawName = [[NSString alloc] initWithBytes:bytes + offset + 46 length:nameLen encoding:NSISOLatin1StringEncoding];
        if (!rawName) {
            offset += 46 + nameLen + extraLen + commentLen;
            continue;
        }

        // Security checks: prevent path traversal and unsafe characters.
        if ([rawName containsString:@"\\"] || [rawName hasPrefix:@"/"] || [rawName containsString:@":"]) {
            if (error) *error = BackupError(@"Unsafe ZIP entry filename contains directory separators or drives.", 107);
            return NO;
        }
        NSArray *components = [rawName componentsSeparatedByString:@"/"];
        for (NSString *part in components) {
            if ([part isEqual:@".."]) {
                if (error) *error = BackupError(@"Path traversal detected in ZIP archive.", 108);
                return NO;
            }
        }
        NSString *ext = rawName.pathExtension.lowercaseString;
        if ([@[@"exe", @"dylib", @"dll", @"so", @"app"] containsObject:ext]) {
            if (error) *error = BackupError(@"Disallowed binary file extension in archive.", 109);
            return NO;
        }

        if (uncompSize > 256 * 1024 * 1024) {
            if (error) *error = BackupError(@"Individual file in ZIP exceeds 256 MiB limit.", 110);
            return NO;
        }
        totalExtractedBytes += uncompSize;
        if (totalExtractedBytes > 4096ULL * 1024 * 1024) {
            if (error) *error = BackupError(@"Total extracted ZIP size exceeds 4 GiB limit.", 111);
            return NO;
        }

        BOOL isDir = [rawName hasSuffix:@"/"];
        NSString *targetFilePath = [destination stringByAppendingPathComponent:rawName];

        if (isDir) {
            [fm createDirectoryAtPath:targetFilePath withIntermediateDirectories:YES attributes:nil error:NULL];
            offset += 46 + nameLen + extraLen + commentLen;
            continue;
        }

        if (localOffset + 30 > length) {
            if (error) *error = BackupError(@"Local header offset out of bounds.", 112);
            return NO;
        }
        uint16_t localNameLen = ReadLE16(bytes + localOffset + 26);
        uint16_t localExtraLen = ReadLE16(bytes + localOffset + 28);
        uint32_t dataOffset = localOffset + 30 + localNameLen + localExtraLen;

        if (dataOffset + compSize > length) {
            if (error) *error = BackupError(@"Compressed data out of bounds.", 113);
            return NO;
        }

        NSMutableData *uncompressed = [NSMutableData dataWithLength:uncompSize];
        if (method == 0) { // Stored
            if (compSize != uncompSize) {
                if (error) *error = BackupError(@"Stored entry size mismatch.", 114);
                return NO;
            }
            memcpy(uncompressed.mutableBytes, bytes + dataOffset, uncompSize);
        } else if (method == 8) { // Deflated
            z_stream strm;
            memset(&strm, 0, sizeof(strm));
            int zret = inflateInit2(&strm, -MAX_WBITS);
            if (zret != Z_OK) {
                if (error) *error = BackupError(@"zlib inflateInit2 failed.", 115);
                return NO;
            }
            strm.next_in = (Bytef *)(bytes + dataOffset);
            strm.avail_in = compSize;
            strm.next_out = (Bytef *)uncompressed.mutableBytes;
            strm.avail_out = uncompSize;
            zret = inflate(&strm, Z_FINISH);
            inflateEnd(&strm);
            if (zret != Z_STREAM_END) {
                if (error) *error = BackupError(@"zlib decompression failed.", 116);
                return NO;
            }
        } else {
            if (error) *error = BackupError([NSString stringWithFormat:@"Unsupported compression method: %u", method], 117);
            return NO;
        }

        // Verify CRC-32
        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, (const Bytef *)uncompressed.bytes, (uInt)uncompressed.length);
        if ((uint32_t)crc != expectedCrc) {
            if (error) *error = BackupError(@"CRC32 checksum mismatch in uncompressed file.", 118);
            return NO;
        }

        [fm createDirectoryAtPath:targetFilePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![uncompressed writeToFile:targetFilePath options:NSDataWritingAtomic error:error]) {
            return NO;
        }

        offset += 46 + nameLen + extraLen + commentLen;
    }

    return YES;
}

#if __has_include(<UIKit/UIKit.h>)
+ (void)presentExportForProduct:(NSDictionary *)product
                        library:(nullable TKAppLibrary *)library
             fromViewController:(UIViewController *)viewController
                     anchorItem:(nullable UIBarButtonItem *)barButtonItem {
    if (![self hasBackupDataForProduct:product library:library]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Backup Data"
            message:[NSString stringWithFormat:@"No WTF settings or Add-ons were found for %@ to back up.", product[@"name"] ?: @"this edition"]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [viewController presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"Creating Backup"
                                                                           message:@"Compressing WTF and Add-on files…"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [viewController presentViewController:progressAlert animated:YES completion:^{
        [self createBackupArchiveForProduct:product library:library progress:^(NSString *status) {
            progressAlert.message = status;
        } completion:^(NSURL * _Nullable archiveURL, NSError * _Nullable error) {
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (error || !archiveURL) {
                    UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Backup Failed"
                                                                                   message:error.localizedDescription ?: @"An unknown error occurred."
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [viewController presentViewController:errAlert animated:YES completion:nil];
                    return;
                }

                UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[archiveURL] applicationActivities:nil];
                if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                    if (barButtonItem) {
                        activity.popoverPresentationController.barButtonItem = barButtonItem;
                    } else {
                        activity.popoverPresentationController.sourceView = viewController.view;
                        activity.popoverPresentationController.sourceRect = CGRectMake(viewController.view.bounds.size.width / 2, viewController.view.bounds.size.height / 2, 0, 0);
                    }
                }
                [viewController presentViewController:activity animated:YES completion:nil];
            }];
        }];
    }];
}

+ (void)presentImportForProduct:(NSDictionary *)product
                        library:(nullable TKAppLibrary *)library
             fromViewController:(UIViewController *)viewController
                     completion:(nullable void (^)(BOOL success))onComplete {
    TKWoWImportCoordinator *coord = [TKWoWImportCoordinator new];
    coord.product = product;
    coord.library = library;
    coord.presentingViewController = viewController;
    coord.completion = onComplete;
    [coord start];
}
#endif

@end
