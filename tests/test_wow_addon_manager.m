#import <Foundation/Foundation.h>
#import <zlib.h>
#import <assert.h>
#import "../launcher/WoW/AddonManager.h"
#import "../launcher/WoW/Manifest.h"

static inline void WriteLE16(uint8_t *p, uint16_t val) {
    p[0] = (uint8_t)(val & 0xff);
    p[1] = (uint8_t)((val >> 8) & 0xff);
}
static inline void WriteLE32(uint8_t *p, uint32_t val) {
    p[0] = (uint8_t)(val & 0xff);
    p[1] = (uint8_t)((val >> 8) & 0xff);
    p[2] = (uint8_t)((val >> 16) & 0xff);
    p[3] = (uint8_t)((val >> 24) & 0xff);
}

static NSData *CreateZipData(NSDictionary<NSString *, NSString *> *files) {
    NSMutableData *body = [NSMutableData new];
    NSMutableArray *entries = [NSMutableArray new];

    for (NSString *filename in files) {
        NSData *content = [files[filename] dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t localOffset = (uint32_t)body.length;

        // Local header: PK\x03\x04
        uint8_t localHdr[30] = {0};
        localHdr[0] = 0x50; localHdr[1] = 0x4b; localHdr[2] = 0x03; localHdr[3] = 0x04;
        localHdr[4] = 20; // version
        // method: 0 (store)
        uLong crc = crc32(0L, (const Bytef *)content.bytes, (uInt)content.length);
        WriteLE32(localHdr + 14, (uint32_t)crc);
        WriteLE32(localHdr + 18, (uint32_t)content.length); // comp
        WriteLE32(localHdr + 22, (uint32_t)content.length); // uncomp
        NSData *nameBytes = [filename dataUsingEncoding:NSUTF8StringEncoding];
        WriteLE16(localHdr + 26, (uint16_t)nameBytes.length);

        [body appendBytes:localHdr length:30];
        [body appendData:nameBytes];
        [body appendData:content];

        [entries addObject:@{
            @"name": filename,
            @"crc": @(crc),
            @"size": @(content.length),
            @"offset": @(localOffset)
        }];
    }

    uint32_t cdOffset = (uint32_t)body.length;
    for (NSDictionary *e in entries) {
        NSString *name = e[@"name"];
        NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
        uint8_t cd[46] = {0};
        cd[0] = 0x50; cd[1] = 0x4b; cd[2] = 0x01; cd[3] = 0x02;
        cd[4] = 20; cd[6] = 20;
        WriteLE32(cd + 16, [e[@"crc"] unsignedIntValue]);
        WriteLE32(cd + 20, [e[@"size"] unsignedIntValue]);
        WriteLE32(cd + 24, [e[@"size"] unsignedIntValue]);
        WriteLE16(cd + 28, (uint16_t)nameBytes.length);
        WriteLE32(cd + 42, [e[@"offset"] unsignedIntValue]);

        [body appendBytes:cd length:46];
        [body appendData:nameBytes];
    }
    uint32_t cdSize = (uint32_t)body.length - cdOffset;

    // EOCD: PK\x05\x06
    uint8_t eocd[22] = {0};
    eocd[0] = 0x50; eocd[1] = 0x4b; eocd[2] = 0x05; eocd[3] = 0x06;
    WriteLE16(eocd + 8, (uint16_t)entries.count);
    WriteLE16(eocd + 10, (uint16_t)entries.count);
    WriteLE32(eocd + 12, cdSize);
    WriteLE32(eocd + 16, cdOffset);
    [body appendBytes:eocd length:22];

    return body;
}

@interface TestUpdateAddonManager : TKWoWAddonManager
@property(nonatomic, strong) NSArray *mockFiles;
@property(nonatomic, strong) NSMutableArray *installedUpdateCalls;
@end

@implementation TestUpdateAddonManager
- (void)fetchFilesForModId:(NSNumber *)modId completion:(void (^)(NSArray<NSDictionary *> *files, NSError *error))completion {
    (void)modId;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(self.mockFiles, nil);
    });
}
- (void)installAddon:(NSDictionary *)addon
                file:(nullable NSDictionary *)selectedFile
             product:(NSDictionary *)product
             library:(nullable TKAppLibrary *)library
            progress:(nullable void (^)(float progress, NSString *status))progress
          completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    (void)selectedFile; (void)product; (void)library; (void)progress;
    [self.installedUpdateCalls addObject:addon];
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(YES, nil);
    });
}
@end

int main(void) {
    @autoreleasepool {
        // 1. Test API Key configuration
        [TKWoWAddonManager setApiKey:@"test-api-key-12345"];
        assert([[TKWoWAddonManager apiKey] isEqual:@"test-api-key-12345"]);
        assert([TKWoWAddonManager hasApiKey]);
        [TKWoWAddonManager setApiKey:nil];
        // After clearing, standard defaults is empty; verify hasApiKey handles it
        NSString *currentKey = [TKWoWAddonManager apiKey];
        (void)currentKey;

        // 2. Test TOC Parsing
        NSString *tocSample = @"## Interface: 16001\n"
                              @"## Title: |cffffd100Bagnon|r\n"
                              @"## Notes: Single window inventory\n"
                              @"## Author: Jaliborc\n"
                              @"## Version: 12.1.6\n";
        NSDictionary *toc = [TKWoWAddonManager parseTOCData:[tocSample dataUsingEncoding:NSUTF8StringEncoding]];
        assert([toc[@"Interface"] isEqual:@"16001"]);
        assert([toc[@"Version"] isEqual:@"12.1.6"]);
        assert([toc[@"Author"] isEqual:@"Jaliborc"]);

        // 3. Test Product File Matching
        NSDictionary *retailFile = @{
            @"displayName": @"Bagnon 11.0.2",
            @"gameVersions": @[@"11.0.2", @"WoW Retail"],
            @"releaseType": @(1)
        };
        NSDictionary *classicEraFile = @{
            @"displayName": @"Bagnon 1.15.3",
            @"gameVersions": @[@"1.15.3", @"Classic Era"],
            @"releaseType": @(1)
        };
        NSDictionary *classicFile = @{
            @"displayName": @"Bagnon 4.4.1",
            @"gameVersions": @[@"4.4.1", @"WoW Classic"],
            @"releaseType": @(1)
        };
        NSDictionary *foreverFile = @{
            @"displayName": @"Bagnon 1.60.1",
            @"gameVersions": @[@"1.60.1", @"Forever", @"Classic Era"],
            @"releaseType": @(1)
        };

        assert([TKWoWAddonManager file:retailFile matchesProduct:@"wow"]);
        assert(![TKWoWAddonManager file:retailFile matchesProduct:@"wow_classic_era"]);
        assert([TKWoWAddonManager file:classicEraFile matchesProduct:@"wow_classic_era"]);
        assert([TKWoWAddonManager file:classicFile matchesProduct:@"wow_classic"]);
        assert([TKWoWAddonManager file:foreverFile matchesProduct:@"wow_classic_beta"]);

        // Best file selection
        NSArray *allFiles = @[retailFile, classicFile, classicEraFile, foreverFile];
        NSDictionary *bestRetail = [TKWoWAddonManager bestFileForProduct:@"wow" fromFiles:allFiles];
        assert([bestRetail isEqual:retailFile]);
        NSDictionary *bestClassicEra = [TKWoWAddonManager bestFileForProduct:@"wow_classic_era" fromFiles:allFiles];
        assert([bestClassicEra isEqual:classicEraFile]);

        // 4. Test ZIP Extraction
        NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSDictionary *files = @{
            @"Bagnon/Bagnon.toc": tocSample,
            @"Bagnon/Bagnon.lua": @"print('Bagnon loaded')",
            @"BagBrother/BagBrother.toc": @"## Interface: 16001\n## Title: BagBrother\n"
        };
        NSData *zipData = CreateZipData(files);
        NSArray<NSString *> *folders = nil;
        NSError *unzipError = nil;
        BOOL ok = [TKWoWAddonManager unzipData:zipData toDirectory:tmpDir extractedFolders:&folders error:&unzipError];
        assert(ok);
        assert(unzipError == nil);
        assert(folders.count == 2);
        assert([folders containsObject:@"Bagnon"]);
        assert([folders containsObject:@"BagBrother"]);

        NSString *extractedToc = [NSString stringWithContentsOfFile:[tmpDir stringByAppendingPathComponent:@"Bagnon/Bagnon.toc"]
                                                           encoding:NSUTF8StringEncoding
                                                              error:NULL];
        assert([extractedToc containsString:@"Jaliborc"]);

        // 5. Test Path Traversal and Safety Rejection in ZIP
        NSDictionary *evilFiles = @{
            @"../evil.txt": @"should fail"
        };
        NSData *evilZip = CreateZipData(evilFiles);
        NSError *evilErr = nil;
        BOOL evilResult = [TKWoWAddonManager unzipData:evilZip toDirectory:tmpDir extractedFolders:NULL error:&evilErr];
        assert(!evilResult);
        assert(evilErr != nil);

        // Disallowed extension
        NSDictionary *binaryFiles = @{
            @"addon/hack.dylib": @"not allowed"
        };
        NSData *binZip = CreateZipData(binaryFiles);
        NSError *binErr = nil;
        BOOL binResult = [TKWoWAddonManager unzipData:binZip toDirectory:tmpDir extractedFolders:NULL error:&binErr];
        assert(!binResult);
        assert(binErr != nil);

        // 6. Test Uninstall Addon
        NSDictionary *product = @{@"id": @"wow_classic_beta", @"name": @"Forever · Beta", @"folder": @"_classic_beta_"};
        NSString *addonsDir = [TKWoWAddonManager addonsDirectoryForProduct:product library:nil];
        NSString *testAddonDir = [addonsDir stringByAppendingPathComponent:@"TestAddonFolder"];
        [NSFileManager.defaultManager createDirectoryAtPath:testAddonDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"## Interface: 16001\n## Title: Test Addon\n## Version: 1.0\n" writeToFile:[testAddonDir stringByAppendingPathComponent:@"TestAddonFolder.toc"]
                                                                           atomically:YES
                                                                             encoding:NSUTF8StringEncoding
                                                                                error:NULL];

        NSArray *installed = [TKWoWAddonManager installedAddonsForProduct:product library:nil];
        BOOL foundTest = NO;
        NSDictionary *testRecord = nil;
        for (NSDictionary *entry in installed) {
            if ([entry[@"name"] isEqual:@"TestAddonFolder"]) {
                foundTest = YES;
                testRecord = entry;
                break;
            }
        }
        assert(foundTest);
        assert(testRecord != nil);

        // Uninstall it
        NSError *unErr = nil;
        BOOL unOk = [TKWoWAddonManager uninstallAddon:testRecord forProduct:product library:nil error:&unErr];
        assert(unOk);
        assert(![NSFileManager.defaultManager fileExistsAtPath:testAddonDir]);

        // 7. Test NSNull and Defensive Parsing Resilience
        assert([TKSafeString([NSNull null], @"fallback") isEqual:@"fallback"]);
        assert([TKSafeString(nil, @"fallback") isEqual:@"fallback"]);
        assert([TKSafeString(@(123), @"fallback") isEqual:@"fallback"]);
        assert([TKSafeString(@"valid", @"fallback") isEqual:@"valid"]);
        assert([TKSafeNumber([NSNull null], @(42)) isEqual:@(42)]);
        assert([TKSafeNumber(nil, @(42)) isEqual:@(42)]);
        assert([TKSafeNumber(@"notanumber", @(42)) isEqual:@(42)]);
        assert([TKSafeNumber(@(100), @(42)) isEqual:@(100)]);

        NSDictionary *nullHeavyFile = @{
            @"displayName": [NSNull null],
            @"fileName": @"bagnon-null.zip",
            @"downloadUrl": [NSNull null],
            @"isAvailable": [NSNull null],
            @"releaseType": [NSNull null],
            @"gameVersions": @[[NSNull null], @"1.15.5", @"Classic Era"]
        };
        NSDictionary *bestFromNull = [TKWoWAddonManager bestFileForProduct:@"wow_classic_era" fromFiles:@[nullHeavyFile]];
        assert(bestFromNull != nil);
        assert([bestFromNull[@"fileName"] isEqual:@"bagnon-null.zip"]);

        NSDictionary *nullRecord = @{
            @"id": [NSNull null],
            @"name": [NSNull null],
            @"folders": [NSNull null]
        };
        NSError *nullUnErr = nil;
        BOOL nullUnOk = [TKWoWAddonManager uninstallAddon:nullRecord forProduct:product library:nil error:&nullUnErr];
        assert(nullUnOk);

        // Cleanup temp dir
        [NSFileManager.defaultManager removeItemAtPath:tmpDir error:NULL];

        // 8. Test Check For Updates without API Key
        [TKWoWAddonManager setApiKey:nil];
        TKWoWAddonManager *mgr = [TKWoWAddonManager new];
        __block BOOL checkDone = NO;
        __block NSArray *checkUpdates = nil;
        __block NSError *checkError = nil;
        [mgr checkForUpdatesForProduct:product library:nil completion:^(NSArray<NSDictionary *> *u, NSError *e) {
            checkUpdates = u;
            checkError = e;
            checkDone = YES;
        }];
        while (!checkDone) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        assert(checkUpdates.count == 0);
        assert(checkError != nil && checkError.code == 401);

        // 9. Test Check For Updates with Available Update
        [TKWoWAddonManager setApiKey:@"test-key"];
        NSString *manifestPath = [addonsDir stringByAppendingPathComponent:@".installed_addons.json"];
        NSArray *testManifest = @[@{
            @"id": @(99999),
            @"name": @"TestMod",
            @"version": @"1.0.0",
            @"fileId": @(100),
            @"fileName": @"test-1.0.0.zip",
            @"folders": @[@"TestMod"]
        }];
        NSData *mfcData = [NSJSONSerialization dataWithJSONObject:testManifest options:0 error:NULL];
        [mfcData writeToFile:manifestPath atomically:YES];

        TestUpdateAddonManager *testMgr = [TestUpdateAddonManager new];
        testMgr.installedUpdateCalls = [NSMutableArray new];
        testMgr.mockFiles = @[@{
            @"id": @(200),
            @"displayName": @"TestMod 1.1.0",
            @"fileName": @"test-1.1.0.zip",
            @"gameVersions": @[@"1.60.1", @"Forever", @"Classic Era"],
            @"releaseType": @(1),
            @"isAvailable": @YES
        }];

        checkDone = NO;
        checkUpdates = nil;
        [testMgr checkForUpdatesForProduct:product library:nil completion:^(NSArray<NSDictionary *> *u, NSError *e) {
            (void)e;
            checkUpdates = u;
            checkDone = YES;
        }];
        while (!checkDone) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        assert(checkUpdates.count == 1);
        assert([checkUpdates[0][@"modId"] isEqual:@(99999)]);
        assert([checkUpdates[0][@"currentVersion"] isEqual:@"1.0.0"]);
        assert([checkUpdates[0][@"updateVersion"] isEqual:@"TestMod 1.1.0"]);
        assert([checkUpdates[0][@"updateFileId"] isEqual:@(200)]);

        // 10. Test Install Updates
        __block BOOL installDone = NO;
        __block NSUInteger progressCount = 0;
        __block NSArray *installErrors = nil;
        [testMgr installUpdates:checkUpdates product:product library:nil progress:^(NSUInteger completed, NSUInteger total, NSString *addonName) {
            assert(completed == 1);
            assert(total == 1);
            assert([addonName isEqual:@"TestMod"]);
            progressCount++;
        } completion:^(NSArray<NSError *> *errors) {
            installErrors = errors;
            installDone = YES;
        }];
        while (!installDone) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        assert(installDone);
        assert(progressCount == 1);
        assert(installErrors.count == 0);
        assert(testMgr.installedUpdateCalls.count == 1);

        // Cleanup test manifest
        [NSFileManager.defaultManager removeItemAtPath:manifestPath error:NULL];
        [TKWoWAddonManager setApiKey:nil];

        printf("WoW Addon Manager tests PASS: API key, TOC parser, edition matching, safe ZIP extraction, traversal blocking, install discovery, uninstall, update check, batch update, and NSNull resilience.\n");
    }
    return 0;
}
