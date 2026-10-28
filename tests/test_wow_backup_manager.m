#import <Foundation/Foundation.h>
#import <zlib.h>
#import <assert.h>
#import "../launcher/WoW/BackupManager.h"

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

@interface MockApp : NSObject
@end
@implementation MockApp
@end

@interface MockLibrary : NSObject
@property(nonatomic, copy) NSString *testRoot;
@property(nonatomic, strong) NSArray *apps;
@end
@implementation MockLibrary
- (instancetype)initWithRoot:(NSString *)root {
    if (!(self = [super init])) return nil;
    _testRoot = [root copy];
    _apps = @[[MockApp new]];
    return self;
}
- (NSString *)workingDirectoryForApp:(id)app error:(NSError **)error {
    (void)app; (void)error;
    return [_testRoot stringByAppendingPathComponent:@"_classic_beta_"];
}
@end

static NSData *CreateCustomZip(NSDictionary<NSString *, NSString *> *files) {
    NSMutableData *body = [NSMutableData new];
    NSMutableArray *entries = [NSMutableArray new];

    for (NSString *filename in files) {
        NSData *content = [files[filename] dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t localOffset = (uint32_t)body.length;

        uint8_t localHdr[30] = {0};
        localHdr[0] = 0x50; localHdr[1] = 0x4b; localHdr[2] = 0x03; localHdr[3] = 0x04;
        localHdr[4] = 20;
        uLong crc = crc32(0L, (const Bytef *)content.bytes, (uInt)content.length);
        WriteLE32(localHdr + 14, (uint32_t)crc);
        WriteLE32(localHdr + 18, (uint32_t)content.length);
        WriteLE32(localHdr + 22, (uint32_t)content.length);
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
    uint8_t eocd[22] = {0};
    eocd[0] = 0x50; eocd[1] = 0x4b; eocd[2] = 0x05; eocd[3] = 0x06;
    WriteLE16(eocd + 8, (uint16_t)entries.count);
    WriteLE16(eocd + 10, (uint16_t)entries.count);
    WriteLE32(eocd + 12, cdSize);
    WriteLE32(eocd + 16, cdOffset);
    [body appendBytes:eocd length:22];

    return body;
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *baseTmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"wolkara-backup-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [fm createDirectoryAtPath:baseTmp withIntermediateDirectories:YES attributes:nil error:NULL];

        MockLibrary *mockLib = [[MockLibrary alloc] initWithRoot:baseTmp];
        TKAppLibrary *library = (id)mockLib;

        NSDictionary *product = @{
            @"id": @"wow_classic_beta",
            @"folder": @"_classic_beta_",
            @"name": @"World of Warcraft Forever"
        };

        // 1. Test hasBackupData when empty
        assert(![TKWoWBackupManager hasBackupDataForProduct:product library:library]);

        // 2. Setup mock game folder in baseTmp/_classic_beta_
        NSString *realProductDir = [baseTmp stringByAppendingPathComponent:@"_classic_beta_"];
        NSString *wtfDir = [realProductDir stringByAppendingPathComponent:@"WTF"];
        NSString *addonsDir = [[realProductDir stringByAppendingPathComponent:@"Interface"] stringByAppendingPathComponent:@"AddOns/MyTestAddon"];

        [fm createDirectoryAtPath:wtfDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:addonsDir withIntermediateDirectories:YES attributes:nil error:NULL];

        NSString *configSample = @"SET portal \"EU\"\nSET textLocale \"enUS\"\n";
        [configSample writeToFile:[wtfDir stringByAppendingPathComponent:@"Config.wtf"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *tocSample = @"## Title: MyTestAddon\n## Version: 1.0\n";
        [tocSample writeToFile:[addonsDir stringByAppendingPathComponent:@"MyTestAddon.toc"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        // 3. hasBackupData should now be YES
        assert([TKWoWBackupManager hasBackupDataForProduct:product library:library]);

        // 4. Test Backup Archive Creation
        __block BOOL exportFinished = NO;
        __block NSURL *createdArchiveURL = nil;
        __block NSError *exportError = nil;

        [TKWoWBackupManager createBackupArchiveForProduct:product library:library progress:^(NSString *status) {
            (void)status;
        } completion:^(NSURL * _Nullable archiveURL, NSError * _Nullable error) {
            createdArchiveURL = archiveURL;
            exportError = error;
            exportFinished = YES;
        }];

        while (!exportFinished) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }

        assert(exportError == nil);
        assert(createdArchiveURL != nil);
        assert([fm fileExistsAtPath:createdArchiveURL.path]);

        // 5. Test Unzip raw data
        NSString *unpackDir = [baseTmp stringByAppendingPathComponent:@"unpacked"];
        NSData *zipData = [NSData dataWithContentsOfURL:createdArchiveURL];
        assert(zipData.length > 0);
        NSError *unzipError = nil;
        BOOL unzipOk = [TKWoWBackupManager unzipData:zipData toDirectory:unpackDir error:&unzipError];
        assert(unzipOk);
        assert(unzipError == nil);

        // 6. Test Restoration from archive
        // Modify existing Config.wtf to ensure restore actually overwrites it
        NSString *alteredConfig = @"SET portal \"US\"\nSET textLocale \"esES\"\n";
        [alteredConfig writeToFile:[wtfDir stringByAppendingPathComponent:@"Config.wtf"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        __block BOOL restoreFinished = NO;
        __block BOOL restoreSuccess = NO;
        __block NSString *restoreSummary = nil;
        __block NSError *restoreError = nil;

        [TKWoWBackupManager restoreBackupFromArchiveURL:createdArchiveURL forProduct:product library:library progress:^(NSString *status) {
            (void)status;
        } completion:^(BOOL success, NSString * _Nullable summary, NSError * _Nullable error) {
            restoreSuccess = success;
            restoreSummary = summary;
            restoreError = error;
            restoreFinished = YES;
        }];

        while (!restoreFinished) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }

        assert(restoreSuccess);
        assert(restoreError == nil);
        assert(restoreSummary.length > 0);

        // Verify Config.wtf was restored back to original "EU"
        NSString *restoredConfig = [NSString stringWithContentsOfFile:[wtfDir stringByAppendingPathComponent:@"Config.wtf"] encoding:NSUTF8StringEncoding error:NULL];
        assert([restoredConfig containsString:@"SET portal \"EU\""]);

        // Verify safety backup was created
        NSString *safetyDir = [realProductDir stringByAppendingPathComponent:@".backup_pre_restore"];
        assert([fm fileExistsAtPath:safetyDir]);
        NSString *safetyConfig = [NSString stringWithContentsOfFile:[[safetyDir stringByAppendingPathComponent:@"WTF"] stringByAppendingPathComponent:@"Config.wtf"] encoding:NSUTF8StringEncoding error:NULL];
        assert([safetyConfig containsString:@"SET portal \"US\""]);

        // 7. Test Nested Restoration (e.g. zip created with top-level folder)
        NSDictionary *nestedFiles = @{
            @"MyPack-v1/WTF/Config.wtf": @"SET portal \"KR\"\n",
            @"MyPack-v1/Interface/AddOns/NestedAddon/NestedAddon.toc": @"## Title: NestedAddon\n"
        };
        NSData *nestedZipData = CreateCustomZip(nestedFiles);
        NSString *nestedZipPath = [baseTmp stringByAppendingPathComponent:@"nested.zip"];
        [nestedZipData writeToFile:nestedZipPath atomically:YES];

        restoreFinished = NO;
        [TKWoWBackupManager restoreBackupFromArchiveURL:[NSURL fileURLWithPath:nestedZipPath] forProduct:product library:library progress:nil completion:^(BOOL success, NSString * _Nullable summary, NSError * _Nullable error) {
            (void)summary; (void)error;
            assert(success);
            restoreFinished = YES;
        }];
        while (!restoreFinished) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }

        NSString *krConfig = [NSString stringWithContentsOfFile:[wtfDir stringByAppendingPathComponent:@"Config.wtf"] encoding:NSUTF8StringEncoding error:NULL];
        assert([krConfig containsString:@"SET portal \"KR\""]);
        assert([fm fileExistsAtPath:[[realProductDir stringByAppendingPathComponent:@"Interface"] stringByAppendingPathComponent:@"AddOns/NestedAddon/NestedAddon.toc"]]);

        // 8. Test Security Checks
        // Path traversal
        NSDictionary *evilFiles = @{@"../../evil.txt": @"hack"};
        NSData *evilZip = CreateCustomZip(evilFiles);
        NSError *evilErr = nil;
        BOOL evilResult = [TKWoWBackupManager unzipData:evilZip toDirectory:unpackDir error:&evilErr];
        assert(!evilResult);
        assert(evilErr != nil);

        // Disallowed binary file
        NSDictionary *binFiles = @{@"Interface/AddOns/Test/bad.dylib": @"binary content"};
        NSData *binZip = CreateCustomZip(binFiles);
        NSError *binErr = nil;
        BOOL binResult = [TKWoWBackupManager unzipData:binZip toDirectory:unpackDir error:&binErr];
        assert(!binResult);
        assert(binErr != nil);

        // Clean up test directories
        [fm removeItemAtPath:baseTmp error:NULL];
        [fm removeItemAtPath:createdArchiveURL.path error:NULL];

        printf("WoW Backup Manager tests PASS: data detection, zip creation, safe extraction, nested folder resolution, traversal blocking, binary rejection, full WTF/Addons restoration, and safety backup.\n");
    }
    return 0;
}
