#import "AddonManager.h"
#import <zlib.h>

static NSError *AddonError(NSString *message, NSInteger code) {
    return [NSError errorWithDomain:@"org.tolkara.addons"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation TKWoWAddonManager

+ (nullable NSString *)apiKey {
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:@"CurseForgeAPIKey"];
    if (key.length > 0) return [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    key = [NSProcessInfo.processInfo.environment objectForKey:@"CURSEFORGE_API_KEY"];
    if (key.length > 0) return [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    key = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CurseForgeAPIKey"];
    if (key.length > 0) return [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *docs = paths.firstObject;
        NSArray *candidates = @[
            [docs stringByAppendingPathComponent:@"curseforge_api_key.txt"],
            [[docs stringByAppendingPathComponent:@"World of Warcraft"] stringByAppendingPathComponent:@"curseforge_api_key.txt"]
        ];
        for (NSString *candidate in candidates) {
            if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
                NSString *content = [NSString stringWithContentsOfFile:candidate encoding:NSUTF8StringEncoding error:NULL];
                content = [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (content.length > 0) return content;
            }
        }
    }
    return nil;
}

+ (void)setApiKey:(nullable NSString *)apiKey {
    NSString *trimmed = [apiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:trimmed forKey:@"CurseForgeAPIKey"];
    } else {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"CurseForgeAPIKey"];
    }
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (BOOL)hasApiKey {
    return [self apiKey].length > 0;
}

+ (NSString *)addonsDirectoryForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library {
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
    NSString *addonsDir = [[[root stringByAppendingPathComponent:folder]
                            stringByAppendingPathComponent:@"Interface"]
                           stringByAppendingPathComponent:@"AddOns"];
    [NSFileManager.defaultManager createDirectoryAtPath:addonsDir withIntermediateDirectories:YES attributes:nil error:NULL];
    return addonsDir;
}

+ (NSString *)manifestPathForAddonsDirectory:(NSString *)addonsDir {
    return [addonsDir stringByAppendingPathComponent:@".installed_addons.json"];
}

+ (NSMutableArray<NSDictionary *> *)readManifestAtAddonsDirectory:(NSString *)addonsDir {
    NSString *path = [self manifestPathForAddonsDirectory:addonsDir];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return [NSMutableArray new];
    NSArray *array = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [array isKindOfClass:NSArray.class] ? [array mutableCopy] : [NSMutableArray new];
}

+ (BOOL)saveManifest:(NSArray<NSDictionary *> *)manifest toAddonsDirectory:(NSString *)addonsDir error:(NSError **)error {
    NSString *path = [self manifestPathForAddonsDirectory:addonsDir];
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

+ (NSDictionary *)parseTOCData:(NSData *)data {
    if (!data) return @{};
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!text) return @{};
    NSMutableDictionary *meta = [NSMutableDictionary new];
    NSArray *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![trimmed hasPrefix:@"##"]) continue;
        NSRange colon = [trimmed rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [[trimmed substringWithRange:NSMakeRange(2, colon.location - 2)]
                         stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = [[trimmed substringFromIndex:colon.location + 1]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (key.length > 0 && value.length > 0) {
            meta[key] = value;
        }
    }
    return meta;
}

+ (NSArray<NSDictionary *> *)installedAddonsForProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library {
    NSString *addonsDir = [self addonsDirectoryForProduct:product library:library];
    NSMutableArray<NSDictionary *> *manifest = [self readManifestAtAddonsDirectory:addonsDir];
    NSMutableSet<NSString *> *trackedFolders = [NSMutableSet new];
    for (NSDictionary *entry in manifest) {
        NSArray *folders = entry[@"folders"];
        if ([folders isKindOfClass:NSArray.class]) {
            [trackedFolders addObjectsFromArray:folders];
        }
    }

    // Discover any unmanaged local add-on directories containing a .toc file.
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:addonsDir error:NULL];
    NSMutableArray<NSDictionary *> *discovered = [NSMutableArray new];
    for (NSString *item in items) {
        if ([item hasPrefix:@"."]) continue;
        if ([trackedFolders containsObject:item]) continue;
        NSString *itemPath = [addonsDir stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:itemPath isDirectory:&isDir] || !isDir) continue;

        NSArray<NSString *> *subfiles = [NSFileManager.defaultManager contentsOfDirectoryAtPath:itemPath error:NULL];
        NSString *tocName = nil;
        for (NSString *sub in subfiles) {
            if ([sub.pathExtension.lowercaseString isEqual:@"toc"]) {
                if ([sub.stringByDeletingPathExtension isEqual:item]) {
                    tocName = sub;
                    break;
                }
                if (!tocName) tocName = sub;
            }
        }
        if (!tocName) continue;

        NSData *tocData = [NSData dataWithContentsOfFile:[itemPath stringByAppendingPathComponent:tocName]];
        NSDictionary *toc = [self parseTOCData:tocData];
        NSString *title = toc[@"Title"] ?: item;
        // Strip WoW UI formatting codes e.g. |cff...|r
        NSRegularExpression *colorRegex = [NSRegularExpression regularExpressionWithPattern:@"\\|[cC][0-9a-fA-F]{8}|\\|[rR]" options:0 error:NULL];
        if (colorRegex) {
            title = [colorRegex stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
        }

        [discovered addObject:@{
            @"id": @(0),
            @"name": item,
            @"displayName": title,
            @"version": toc[@"Version"] ?: @"",
            @"author": toc[@"Author"] ?: @"",
            @"summary": toc[@"Notes"] ?: @"Local add-on",
            @"folders": @[item],
            @"isLocal": @YES
        }];
    }

    NSMutableArray<NSDictionary *> *all = [NSMutableArray arrayWithArray:manifest];
    [all addObjectsFromArray:discovered];
    [all sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *nameA = a[@"name"] ?: a[@"displayName"] ?: @"";
        NSString *nameB = b[@"name"] ?: b[@"displayName"] ?: @"";
        return [nameA localizedCaseInsensitiveCompare:nameB];
    }];
    return all;
}

+ (BOOL)uninstallAddon:(NSDictionary *)addon forProduct:(NSDictionary *)product library:(nullable TKAppLibrary *)library error:(NSError **)error {
    NSString *addonsDir = [self addonsDirectoryForProduct:product library:library];
    NSArray *folders = [addon[@"folders"] isKindOfClass:NSArray.class] ? addon[@"folders"] : nil;
    if (!folders || folders.count == 0) {
        NSString *rawName = TKSafeString(addon[@"name"], nil);
        if (rawName.length > 0) folders = @[rawName];
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    for (id f in folders) {
        if (![f isKindOfClass:NSString.class]) continue;
        NSString *folder = (NSString *)f;
        if (folder.length == 0) continue;
        if ([folder containsString:@"/"] || [folder containsString:@"\\"] || [folder containsString:@".."]) {
            continue;
        }
        NSString *targetPath = [addonsDir stringByAppendingPathComponent:folder];
        if ([fm fileExistsAtPath:targetPath]) {
            if (![fm removeItemAtPath:targetPath error:error]) return NO;
        }
    }

    NSMutableArray<NSDictionary *> *manifest = [self readManifestAtAddonsDirectory:addonsDir];
    NSNumber *addonId = TKSafeNumber(addon[@"id"], nil);
    NSString *addonName = TKSafeString(addon[@"name"], nil);
    NSIndexSet *toRemove = [manifest indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        if (![obj isKindOfClass:NSDictionary.class]) return NO;
        if (addonId && addonId.integerValue != 0 && [obj[@"id"] isEqual:addonId]) return YES;
        if (addonName.length > 0 && [obj[@"name"] isEqual:addonName]) return YES;
        return NO;
    }];
    if (toRemove.count > 0) {
        [manifest removeObjectsAtIndexes:toRemove];
        [self saveManifest:manifest toAddonsDirectory:addonsDir error:error];
    }
    return YES;
}

+ (BOOL)file:(NSDictionary *)file matchesProduct:(NSString *)productId {
    NSArray *versions = file[@"gameVersions"];
    if (![versions isKindOfClass:NSArray.class] || versions.count == 0) return YES;

    BOOL isRetail = [productId isEqual:@"wow"] || [productId isEqual:@"wow_beta"];
    BOOL isClassicEra = [productId isEqual:@"wow_classic_era"];
    BOOL isClassic = [productId isEqual:@"wow_classic"];
    BOOL isForeverBeta = [productId isEqual:@"wow_classic_beta"];

    for (id v in versions) {
        if (![v isKindOfClass:NSString.class]) continue;
        NSString *ver = (NSString *)v;
        if (isRetail) {
            if ([ver rangeOfString:@"Retail" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [ver rangeOfString:@"11."].location != NSNotFound ||
                [ver rangeOfString:@"10."].location != NSNotFound ||
                [ver rangeOfString:@"The War Within" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return YES;
            }
        } else if (isClassicEra) {
            if ([ver rangeOfString:@"Classic Era" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [ver rangeOfString:@"1.15."].location != NSNotFound ||
                [ver rangeOfString:@"1.14."].location != NSNotFound) {
                return YES;
            }
        } else if (isClassic) {
            if (([ver rangeOfString:@"Classic" options:NSCaseInsensitiveSearch].location != NSNotFound &&
                 [ver rangeOfString:@"Era" options:NSCaseInsensitiveSearch].location == NSNotFound) ||
                [ver rangeOfString:@"4.4."].location != NSNotFound ||
                [ver rangeOfString:@"3.4."].location != NSNotFound ||
                [ver rangeOfString:@"Cataclysm" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return YES;
            }
        } else if (isForeverBeta) {
            if ([ver rangeOfString:@"Forever" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [ver rangeOfString:@"1.60."].location != NSNotFound ||
                [ver rangeOfString:@"Classic Era" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [ver rangeOfString:@"1.15."].location != NSNotFound ||
                [ver rangeOfString:@"1.14."].location != NSNotFound ||
                [ver rangeOfString:@"Classic" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return YES;
            }
        }
    }
    return NO;
}

+ (nullable NSDictionary *)bestFileForProduct:(NSString *)productId fromFiles:(NSArray<NSDictionary *> *)files {
    if (![files isKindOfClass:NSArray.class] || files.count == 0) return nil;
    NSDictionary *best = nil;
    NSInteger bestScore = -1;

    for (id obj in files) {
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *file = (NSDictionary *)obj;
        id avail = file[@"isAvailable"];
        if (avail && [avail respondsToSelector:@selector(boolValue)] && ![avail boolValue]) continue;

        NSInteger score = 0;
        if ([self file:file matchesProduct:productId]) {
            score += 100;
        }
        id rel = file[@"releaseType"];
        NSInteger releaseType = [rel respondsToSelector:@selector(integerValue)] ? [rel integerValue] : 0;
        if (releaseType == 1) score += 20; // Release
        else if (releaseType == 2) score += 10; // Beta
        else if (releaseType == 3) score += 5; // Alpha

        if (score > bestScore) {
            bestScore = score;
            best = file;
        }
    }
    return best ?: files.firstObject;
}

static inline uint16_t ReadLE16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static inline uint32_t ReadLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

+ (BOOL)unzipData:(NSData *)zipData toDirectory:(NSString *)destination extractedFolders:(NSArray<NSString *> * _Nullable * _Nullable)outFolders error:(NSError **)error {
    if (!zipData || zipData.length < 22) {
        if (error) *error = AddonError(@"Invalid or empty ZIP data.", 101);
        return NO;
    }
    const uint8_t *bytes = (const uint8_t *)zipData.bytes;
    NSUInteger length = zipData.length;

    // Locate End of Central Directory record (EOCD).
    long eocdOffset = -1;
    long searchLimit = (long)length - 22;
    long maxSearch = (searchLimit > 65557) ? (searchLimit - 65535) : 0;
    for (long i = searchLimit; i >= maxSearch; i--) {
        if (bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
            eocdOffset = i;
            break;
        }
    }
    if (eocdOffset < 0) {
        if (error) *error = AddonError(@"Could not find ZIP End of Central Directory.", 102);
        return NO;
    }

    uint16_t entriesCount = ReadLE16(bytes + eocdOffset + 10);
    uint32_t cdOffset = ReadLE32(bytes + eocdOffset + 16);
    if (cdOffset > length) {
        if (error) *error = AddonError(@"Malformed ZIP central directory offset.", 103);
        return NO;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:NULL];

    NSMutableSet<NSString *> *topFolders = [NSMutableSet new];
    uint32_t offset = cdOffset;
    uint64_t totalExtractedBytes = 0;

    for (int i = 0; i < entriesCount; i++) {
        if (offset + 46 > length) {
            if (error) *error = AddonError(@"ZIP entry header exceeds bounds.", 104);
            return NO;
        }
        if (memcmp(bytes + offset, "PK\x01\x02", 4) != 0) {
            if (error) *error = AddonError(@"Corrupted ZIP central directory header.", 105);
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
            if (error) *error = AddonError(@"Invalid ZIP entry filename length.", 106);
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
            if (error) *error = AddonError(@"Unsafe ZIP entry filename contains directory separators or drives.", 107);
            return NO;
        }
        NSArray *components = [rawName componentsSeparatedByString:@"/"];
        for (NSString *part in components) {
            if ([part isEqual:@".."]) {
                if (error) *error = AddonError(@"Path traversal detected in ZIP archive.", 108);
                return NO;
            }
        }
        NSString *ext = rawName.pathExtension.lowercaseString;
        if ([@[@"exe", @"dylib", @"dll", @"so", @"app"] containsObject:ext]) {
            if (error) *error = AddonError(@"Disallowed binary file extension in add-on archive.", 109);
            return NO;
        }

        if (uncompSize > 64 * 1024 * 1024) {
            if (error) *error = AddonError(@"Individual file in ZIP exceeds 64 MiB limit.", 110);
            return NO;
        }
        totalExtractedBytes += uncompSize;
        if (totalExtractedBytes > 512 * 1024 * 1024) {
            if (error) *error = AddonError(@"Total extracted ZIP size exceeds 512 MiB limit.", 111);
            return NO;
        }

        if (components.count > 0 && [components[0] length] > 0) {
            [topFolders addObject:components[0]];
        }

        BOOL isDir = [rawName hasSuffix:@"/"];
        NSString *targetFilePath = [destination stringByAppendingPathComponent:rawName];

        if (isDir) {
            [fm createDirectoryAtPath:targetFilePath withIntermediateDirectories:YES attributes:nil error:NULL];
            offset += 46 + nameLen + extraLen + commentLen;
            continue;
        }

        if (localOffset + 30 > length) {
            if (error) *error = AddonError(@"Local header offset out of bounds.", 112);
            return NO;
        }
        uint16_t localNameLen = ReadLE16(bytes + localOffset + 26);
        uint16_t localExtraLen = ReadLE16(bytes + localOffset + 28);
        uint32_t dataOffset = localOffset + 30 + localNameLen + localExtraLen;

        if (dataOffset + compSize > length) {
            if (error) *error = AddonError(@"Compressed data out of bounds.", 113);
            return NO;
        }

        NSMutableData *uncompressed = [NSMutableData dataWithLength:uncompSize];
        if (method == 0) { // Stored
            if (compSize != uncompSize) {
                if (error) *error = AddonError(@"Stored entry size mismatch.", 114);
                return NO;
            }
            memcpy(uncompressed.mutableBytes, bytes + dataOffset, uncompSize);
        } else if (method == 8) { // Deflated
            z_stream strm;
            memset(&strm, 0, sizeof(strm));
            int zret = inflateInit2(&strm, -MAX_WBITS);
            if (zret != Z_OK) {
                if (error) *error = AddonError(@"zlib inflateInit2 failed.", 115);
                return NO;
            }
            strm.next_in = (Bytef *)(bytes + dataOffset);
            strm.avail_in = compSize;
            strm.next_out = (Bytef *)uncompressed.mutableBytes;
            strm.avail_out = uncompSize;
            zret = inflate(&strm, Z_FINISH);
            inflateEnd(&strm);
            if (zret != Z_STREAM_END) {
                if (error) *error = AddonError(@"zlib decompression failed.", 116);
                return NO;
            }
        } else {
            if (error) *error = AddonError([NSString stringWithFormat:@"Unsupported compression method: %u", method], 117);
            return NO;
        }

        // Verify CRC-32
        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, (const Bytef *)uncompressed.bytes, (uInt)uncompressed.length);
        if ((uint32_t)crc != expectedCrc) {
            if (error) *error = AddonError(@"CRC32 checksum mismatch in uncompressed file.", 118);
            return NO;
        }

        [fm createDirectoryAtPath:targetFilePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![uncompressed writeToFile:targetFilePath options:NSDataWritingAtomic error:error]) {
            return NO;
        }

        offset += 46 + nameLen + extraLen + commentLen;
    }

    if (outFolders) {
        *outFolders = [topFolders.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
    return YES;
}

- (void)searchAddonsWithQuery:(nullable NSString *)query
                      product:(NSDictionary *)product
                   completion:(void (^)(NSArray<NSDictionary *> * _Nullable results, NSError * _Nullable error))completion {
    NSString *apiKey = [TKWoWAddonManager apiKey];
    if (apiKey.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, AddonError(@"CurseForge API Key is not configured. Please set your key in Settings or local.env.", 401));
        });
        return;
    }

    NSMutableString *urlString = [@"https://api.curseforge.com/v1/mods/search?gameId=1&pageSize=30&sortField=2&sortOrder=desc" mutableCopy];
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length > 0) {
        NSString *encoded = [trimmed stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        [urlString appendFormat:@"&searchFilter=%@", encoded];
    }

    // Optional game flavor parameter
    NSString *productId = product[@"id"];
    if ([productId isEqual:@"wow"]) {
        [urlString appendString:@"&gameVersionTypeId=517"];
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setTimeoutInterval:25.0];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
        if (http.statusCode != 200) {
            NSString *msg = [NSString stringWithFormat:@"CurseForge API error: HTTP %ld", (long)http.statusCode];
            if (http.statusCode == 403 || http.statusCode == 401) {
                msg = @"Invalid or forbidden CurseForge API Key.";
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, AddonError(msg, (NSInteger)http.statusCode)); });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *items = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([items isKindOfClass:NSArray.class] ? items : @[], nil);
        });
    }];
    [task resume];
}

- (void)fetchFilesForModId:(NSNumber *)modId
                completion:(void (^)(NSArray<NSDictionary *> * _Nullable files, NSError * _Nullable error))completion {
    NSString *apiKey = [TKWoWAddonManager apiKey];
    if (apiKey.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, AddonError(@"CurseForge API Key is not configured.", 401));
        });
        return;
    }
    NSString *urlString = [NSString stringWithFormat:@"https://api.curseforge.com/v1/mods/%@/files", modId];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setTimeoutInterval:25.0];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
        if (http.statusCode != 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, AddonError([NSString stringWithFormat:@"Failed to load files: HTTP %ld", (long)http.statusCode], (NSInteger)http.statusCode));
            });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *items = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([items isKindOfClass:NSArray.class] ? items : @[], nil);
        });
    }];
    [task resume];
}

- (void)resolveDownloadUrlForModId:(NSNumber *)modId
                            fileId:(NSNumber *)fileId
                        completion:(void (^)(NSString * _Nullable url, NSError * _Nullable error))completion {
    NSNumber *validModId = TKSafeNumber(modId, nil);
    NSNumber *validFileId = TKSafeNumber(fileId, nil);
    if (!validModId || validModId.integerValue == 0 || !validFileId || validFileId.integerValue == 0) {
        completion(nil, AddonError(@"Invalid mod or file ID.", 125));
        return;
    }
    NSString *apiKey = [TKWoWAddonManager apiKey];
    NSString *urlString = [NSString stringWithFormat:@"https://api.curseforge.com/v1/mods/%@/files/%@/download-url", validModId, validFileId];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    if (apiKey.length > 0) {
        [request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    }
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setTimeoutInterval:25.0];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && ((NSHTTPURLResponse *)resp).statusCode == 200 && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([json isKindOfClass:NSDictionary.class]) {
                NSString *direct = json[@"data"];
                if ([direct isKindOfClass:NSString.class] && direct.length > 0) {
                    completion(direct, nil);
                    return;
                }
            }
        }
        // Fallback: public download endpoint
        NSString *fallback = [NSString stringWithFormat:@"https://www.curseforge.com/api/v1/mods/%@/files/%@/download", validModId, validFileId];
        completion(fallback, nil);
    }];
    [task resume];
}

- (void)installAddon:(NSDictionary *)addon
                file:(nullable NSDictionary *)selectedFile
             product:(NSDictionary *)product
             library:(nullable TKAppLibrary *)library
            progress:(nullable void (^)(float progress, NSString *status))progress
          completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (![addon isKindOfClass:NSDictionary.class]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, AddonError(@"Invalid add-on information.", 119));
        });
        return;
    }
    NSNumber *modId = TKSafeNumber(addon[@"id"], nil);
    if (!modId || modId.integerValue == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, AddonError(@"Missing mod identifier.", 120));
        });
        return;
    }

    void (^reportProgress)(float, NSString *) = ^(float p, NSString *s) {
        if (!progress) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(p, s);
        });
    };

    void (^continueWithFile)(NSDictionary *) = ^(NSDictionary *fileToInstall) {
        if (![fileToInstall isKindOfClass:NSDictionary.class]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, AddonError(@"No compatible file found for this game edition.", 121));
            });
            return;
        }

        NSNumber *fileId = TKSafeNumber(fileToInstall[@"id"], @(0));
        NSString *initialUrl = nil;
        if ([fileToInstall[@"downloadUrl"] isKindOfClass:NSString.class]) {
            initialUrl = fileToInstall[@"downloadUrl"];
        }

        void (^startDownload)(NSString *) = ^(NSString *downloadUrl) {
            reportProgress(0.05f, @"Downloading add-on package…");
            NSURL *dlUrl = [NSURL URLWithString:downloadUrl];
            if (!dlUrl) {
                NSString *escaped = [downloadUrl stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                dlUrl = [NSURL URLWithString:escaped];
            }
            if (!dlUrl) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, AddonError(@"Invalid download URL.", 124));
                });
                return;
            }

            NSMutableURLRequest *dlReq = [NSMutableURLRequest requestWithURL:dlUrl];
            [dlReq setValue:@"Wolkara-AddonManager/1.0" forHTTPHeaderField:@"User-Agent"];
            [dlReq setTimeoutInterval:60.0];

            NSURLSessionDownloadTask *dlTask = [NSURLSession.sharedSession downloadTaskWithRequest:dlReq completionHandler:^(NSURL *location, NSURLResponse *resp, NSError *dlErr) {
                if (dlErr) {
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, dlErr); });
                    return;
                }
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
                if (http.statusCode < 200 || http.statusCode >= 400) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(NO, AddonError([NSString stringWithFormat:@"Download failed with HTTP %ld", (long)http.statusCode], (NSInteger)http.statusCode));
                    });
                    return;
                }
                NSData *pkgData = [NSData dataWithContentsOfURL:location];
                if (!pkgData || pkgData.length == 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(NO, AddonError(@"Downloaded file was empty.", 122));
                    });
                    return;
                }

                reportProgress(0.75f, @"Extracting add-on files…");
                NSString *addonsDir = [TKWoWAddonManager addonsDirectoryForProduct:product library:library];
                NSArray<NSString *> *extractedFolders = nil;
                NSError *extractErr = nil;
                if (![TKWoWAddonManager unzipData:pkgData toDirectory:addonsDir extractedFolders:&extractedFolders error:&extractErr]) {
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, extractErr); });
                    return;
                }

                // Update manifest record
                NSMutableArray<NSDictionary *> *manifest = [TKWoWAddonManager readManifestAtAddonsDirectory:addonsDir];
                // Remove older entry for same mod if present
                NSIndexSet *existing = [manifest indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
                    (void)idx; (void)stop;
                    return [obj[@"id"] isEqual:modId];
                }];
                if (existing.count > 0) [manifest removeObjectsAtIndexes:existing];

                NSString *author = nil;
                NSArray *authors = addon[@"authors"];
                if ([authors isKindOfClass:NSArray.class] && authors.count > 0) {
                    NSDictionary *firstAuth = authors[0];
                    if ([firstAuth isKindOfClass:NSDictionary.class]) {
                        author = TKSafeString(firstAuth[@"name"], nil);
                    }
                }
                NSString *iconUrl = nil;
                NSDictionary *logo = addon[@"logo"];
                if ([logo isKindOfClass:NSDictionary.class]) {
                    id thumb = logo[@"thumbnailUrl"];
                    id full = logo[@"url"];
                    if ([thumb isKindOfClass:NSString.class]) iconUrl = thumb;
                    else if ([full isKindOfClass:NSString.class]) iconUrl = full;
                }

                NSString *modName = TKSafeString(addon[@"name"], TKSafeString(addon[@"displayName"], @""));
                NSString *version = TKSafeString(fileToInstall[@"displayName"], TKSafeString(fileToInstall[@"fileName"], @""));
                NSString *fileName = TKSafeString(fileToInstall[@"fileName"], @"");
                NSString *summary = TKSafeString(addon[@"summary"], @"");

                NSDictionary *record = @{
                    @"id": modId ?: @(0),
                    @"name": modName,
                    @"version": version,
                    @"fileId": fileId ?: @(0),
                    @"fileName": fileName,
                    @"summary": summary,
                    @"author": author ?: @"",
                    @"iconUrl": iconUrl ?: @"",
                    @"folders": extractedFolders ?: @[],
                    @"installedAt": [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]
                };
                [manifest addObject:record];
                [TKWoWAddonManager saveManifest:manifest toAddonsDirectory:addonsDir error:NULL];

                reportProgress(1.0f, @"Installation complete!");
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES, nil);
                });
            }];
            [dlTask resume];
        };

        if (initialUrl && initialUrl.length > 0) {
            startDownload(initialUrl);
        } else {
            reportProgress(0.02f, @"Resolving download address…");
            [self resolveDownloadUrlForModId:modId fileId:fileId completion:^(NSString *url, NSError *resErr) {
                (void)resErr;
                if ([url isKindOfClass:NSString.class] && url.length > 0) {
                    startDownload(url);
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(NO, AddonError(@"Could not resolve download URL for this add-on.", 123));
                    });
                }
            }];
        }
    };

    if (selectedFile) {
        continueWithFile(selectedFile);
    } else {
        reportProgress(0.01f, @"Checking compatible versions…");
        [self fetchFilesForModId:modId completion:^(NSArray<NSDictionary *> *files, NSError *fetchErr) {
            if (fetchErr) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, fetchErr); });
                return;
            }
            NSDictionary *best = [TKWoWAddonManager bestFileForProduct:product[@"id"] fromFiles:files ?: @[]];
            continueWithFile(best);
        }];
    }
}

@end
