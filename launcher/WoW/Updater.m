#import "Updater.h"
#import "CASC.h"
#include <sys/clonefile.h>
#include <sys/file.h>
#include <sys/stdio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static BOOL Fail(NSError **error,NSString *message) { if(error)*error=TKWoWError(message);return NO; }
static NSArray *Words(NSString *s) { return [[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]; }
static NSString *Join(NSString *root,NSString *path) { return [root stringByAppendingPathComponent:path]; }
static BOOL Directory(NSString *path,NSError **error) { return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]; }
static BOOL SafeRelative(NSString *path) {
    if(!path.length || path.isAbsolutePath || [path containsString:@":"])return NO;
    for(NSString *part in path.pathComponents)if([part isEqual:@".."] || [part isEqual:@"."])return NO;
    return [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound;
}
// Refuse symlink escapes, including existing symlinks in parent directories.
static BOOL SafeWrite(NSString *root,NSString *relative,NSData *data,NSError **error) {
    if(!SafeRelative(relative))return Fail(error,@"Unsafe installation path.");
    NSString *path=Join(root,relative), *parent=path.stringByDeletingLastPathComponent;
    NSString *resolved=parent.stringByResolvingSymlinksInPath;
    if(![resolved isEqual:root] && ![resolved hasPrefix:[root stringByAppendingString:@"/"]])return Fail(error,@"Installation path escapes its staging directory.");
    return Directory(parent,error) && [data writeToFile:path options:NSDataWritingAtomic error:error];
}
static NSData *BuildInfo(NSString *root,NSError **error) {
    NSString *path=Join(root,@".build.info");NSError *failure=nil;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:&failure];
    if(!attributes) {
        if([failure.domain isEqual:NSCocoaErrorDomain] &&
           (failure.code==NSFileNoSuchFileError || failure.code==NSFileReadNoSuchFileError))return [NSData data];
        if(error)*error=failure;return nil;
    }
    if(![attributes[NSFileType] isEqual:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue]>2*1024*1024) {
        Fail(error,@"Unsupported or oversized installation metadata.");return nil;
    }
    return [NSData dataWithContentsOfFile:path options:0 error:error];
}
static BOOL SameBuild(NSDictionary *a,NSDictionary *b) {
    return [a[@"BuildConfig"] isEqual:b[@"BuildConfig"]] && [a[@"CDNConfig"] isEqual:b[@"CDNConfig"]] && [a[@"VersionsName"] isEqual:b[@"VersionsName"]];
}
@implementation TKWoWUpdater { TKWoWClient *_client; }
- (instancetype)initWithClient:(TKWoWClient *)client { if((self=[super init]))_client=client;return self; }
- (BOOL)cancelled:(NSError **)error { return _client.cancelled? !Fail(error,@"Update paused. Reopen the app to resume."):NO; }
- (BOOL)cloneRoot:(NSString *)root into:(NSString *)stage progress:(void (^)(NSString *,uint64_t,uint64_t))progress error:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager;
    if(!Directory(stage,error))return NO;
    if(![fm fileExistsAtPath:root])return YES;
    __block NSError *failure=nil;NSUInteger count=0;
    NSDirectoryEnumerator *enumerator=[fm enumeratorAtURL:[NSURL fileURLWithPath:root isDirectory:YES]
        includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url,NSError *problem) {
            (void)url;failure=problem;return NO;
        }];
    @try {
    for(NSURL *entry in enumerator) { @autoreleasepool {
        // Foundation can canonicalize /var to /private/var on returned URLs.
        // Use enumeration depth rather than slicing an absolute path prefix.
        NSArray *parts=entry.path.pathComponents;NSUInteger depth=enumerator.level;
        if(!depth || depth>parts.count)return Fail(&failure,@"Invalid directory enumeration depth.");
        NSString *relative=[[parts subarrayWithRange:NSMakeRange(parts.count-depth,depth)] componentsJoinedByString:@"/"];
        if([self cancelled:&failure])return NO;
        NSString *source=Join(root,relative), *destination=Join(stage,relative);
        NSDictionary *attributes=[fm attributesOfItemAtPath:source error:&failure];if(!attributes)return NO;
        NSString *type=attributes[NSFileType];
        if([type isEqual:NSFileTypeDirectory]) { if(!Directory(destination,&failure))return NO; }
        else if([type isEqual:NSFileTypeSymbolicLink]) {
            NSString *target=[fm destinationOfSymbolicLinkAtPath:source error:&failure];if(!target)return NO;
            NSString *resolved=(target.isAbsolutePath?target:Join(source.stringByDeletingLastPathComponent,target)).stringByResolvingSymlinksInPath;
            if(![resolved hasPrefix:[root stringByAppendingString:@"/"]])return Fail(&failure,@"An existing game symlink points outside its installation.");
            if(target.isAbsolutePath) {
                NSMutableString *adjusted=[NSMutableString new]; for(NSUInteger i=1;i<relative.pathComponents.count;i++)[adjusted appendString:@"../"];
                [adjusted appendString:[resolved substringFromIndex:root.length+1]];target=adjusted;
            }
            if(![fm createSymbolicLinkAtPath:destination withDestinationPath:target error:&failure])return NO;
        } else if([type isEqual:NSFileTypeRegular]) {
            // APFS clones share unchanged blocks, but writes cannot affect the
            // original. Hard links are deliberately not used for game files.
            if(clonefile(source.fileSystemRepresentation,destination.fileSystemRepresentation,CLONE_NOFOLLOW))
                return Fail(&failure,[NSString stringWithFormat:@"Cannot prepare a private copy (%s). An APFS volume is required.",strerror(errno)]);
        } else return Fail(&failure,@"Unsupported special file in the installation.");
        count++;if(count%100==0)progress(@"snapshot",count,0);
    }}
    } @finally { if(failure && error)*error=failure; }
    return !failure;
}
- (BOOL)writeBuildInfo:(NSDictionary *)plan root:(NSString *)root error:(NSError **)error {
    NSData *old=BuildInfo(root,error);if(!old)return NO;
    NSArray *rows=old.length?TKWoWTable(old,error):@[];if(!rows)return NO;
    NSString *header=old.length?[[[NSString alloc] initWithData:old encoding:NSUTF8StringEncoding] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject:
        @"Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|CDN Key!HEX:16|Install Key!HEX:16|IM Size!DEC:4|CDN Path!STRING:0|CDN Hosts!STRING:0|Tags!STRING:0|Armadillo!STRING:0|Last Activated!STRING:0|Version!STRING:0|Keyring!HEX:16|KeyService!STRING:0|Product!STRING:0|Product Config!HEX:16";
    if(![header containsString:@"Product Config"]) header=[header stringByAppendingString:@"|Product Config!HEX:16"];
    NSMutableArray *keys=[NSMutableArray new];for(NSString *column in [header componentsSeparatedByString:@"|"])[keys addObject:[column componentsSeparatedByString:@"!"][0]];
    for(NSString *required in @[@"Product",@"Active",@"Build Key",@"CDN Key",@"Version"])if(![keys containsObject:required])return Fail(error,@"Unsupported installation metadata columns.");
    NSMutableArray *updated=[NSMutableArray new];NSMutableDictionary *entry=nil;
    for(NSDictionary *row in rows) {
        if([row[@"Product"] isEqual:plan[@"product"]]) { if(entry)return Fail(error,@"Ambiguous installed product rows.");entry=[row mutableCopy]; }
        else [updated addObject:row];
    }
    if(!entry)entry=[NSMutableDictionary new];
    NSDictionary *v=plan[@"version"]; NSArray *install=Words(plan[@"config"][@"install"]), *sizes=Words(plan[@"config"][@"install-size"]);
    if(install.count!=2 || sizes.count!=2)return Fail(error,@"Invalid install metadata.");
    NSString *cdnHosts=[NSURL URLWithString:plan[@"cdn"]].host;
    if([cdnHosts hasPrefix:@"level3.ssl."]) cdnHosts=@"level3.blizzard.com us.cdn.blizzard.com";
    [entry addEntriesFromDictionary:@{@"Product":plan[@"product"],@"Branch":plan[@"region"],@"Active":@"1",
        @"Build Key":v[@"BuildConfig"],@"CDN Key":v[@"CDNConfig"],@"Version":v[@"VersionsName"],
        @"Install Key":install[1],@"IM Size":sizes[1],@"CDN Path":@"tpr/wow",@"CDN Hosts":cdnHosts,
        @"Tags":[NSString stringWithFormat:@"OSX arm64 %@ %@ speech?:OSX arm64 %@ %@ text?",[plan[@"region"] uppercaseString],plan[@"locale"],[plan[@"region"] uppercaseString],plan[@"locale"]]}];
    if(v[@"ProductConfig"]) entry[@"Product Config"]=v[@"ProductConfig"];
    [updated addObject:entry];NSMutableString *text=[[header stringByAppendingString:@"\n"] mutableCopy];
    for(NSDictionary *row in updated) {
        NSMutableArray *values=[NSMutableArray new];
        for(NSString *key in keys) { NSString *value=row[key]?:@"";if([value containsString:@"|"] || [value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound)return Fail(error,@"Invalid installation metadata value.");[values addObject:value]; }
        [text appendFormat:@"%@\n",[values componentsJoinedByString:@"|"]];
    }
    return SafeWrite(root,@".build.info",[text dataUsingEncoding:NSUTF8StringEncoding],error);
}
- (BOOL)updatePlan:(NSDictionary *)plan root:(NSString *)root progress:(void (^)(NSString *,uint64_t,uint64_t))progress error:(NSError **)error {
    _verificationBytesRead=0;_verificationBytesReused=0;
    NSString *folder=nil;for(NSDictionary *p in TKWoWProducts())if([p[@"id"] isEqual:plan[@"product"]])folder=p[@"folder"];
    if(!folder || ![@[@"eu",@"us",@"kr",@"tw"] containsObject:plan[@"region"]] || ![@[@"enUS",@"esES",@"deDE",@"frFR",@"itIT",@"esMX",@"ptBR",@"ruRU",@"koKR",@"zhTW"] containsObject:plan[@"locale"]] || !root.isAbsolutePath || !TKWoWHashValid(plan[@"version"][@"BuildConfig"]) || !TKWoWHashValid(plan[@"version"][@"CDNConfig"]))return Fail(error,@"Invalid update target.");
    root=root.stringByResolvingSymlinksInPath;NSString *parent=root.stringByDeletingLastPathComponent;
    NSString *work=Join(parent,@".tolkara-updates");if(!Directory(work,error))return NO;
    if(![work.stringByResolvingSymlinksInPath isEqual:work])return Fail(error,@"Update directory must not be a symlink.");
    int lock=open(Join(work,@"update.lock").fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(lock<0 || flock(lock,LOCK_EX|LOCK_NB)) { if(lock>=0)close(lock);return Fail(error,@"Another update is finishing. Try again shortly."); }
    BOOL success=NO;TKWoWCASCStore *store=nil;
    NSError *failure=nil;
    @try {
        NSString *name=[NSString stringWithFormat:@"%@-%@-%@",plan[@"product"],plan[@"version"][@"BuildConfig"],plan[@"locale"]];
        NSString *job=Join(work,name), *stage=Join(job,@"installation"), *marker=Join(job,@"snapshot-complete");
        if(!Directory(job,&failure))return NO;
        if(![job.stringByResolvingSymlinksInPath isEqual:job])return Fail(&failure,@"Update job must not be a symlink.");
        NSDictionary *current=[_client versionForProduct:plan[@"product"] region:plan[@"region"] error:&failure];
        if(!current)return NO;if(!SameBuild(current,plan[@"version"]))return Fail(&failure,@"A newer build was published. Check for updates again.");
        NSFileManager *fm=NSFileManager.defaultManager;
        NSData *sourceInfo=BuildInfo(root,&failure);if(!sourceInfo)return NO;
        NSString *sourceHash=TKWoWMD5(sourceInfo);
        NSString *snapshotHash=[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL];
        if(![snapshotHash isEqual:sourceHash]) {
            // This path is our own incomplete snapshot, never the installation.
            if([fm fileExistsAtPath:stage] && ![fm removeItemAtPath:stage error:&failure])return NO;
            NSString *sourceData=Join(root,@"Data/data"),*stagedData=Join(stage,@"Data/data");
            NSDictionary *verification=_fullVerification?nil:TKWoWCASCVerificationSnapshot(sourceData);
            progress(@"snapshot",0,0);if(![self cloneRoot:root into:stage progress:progress error:&failure])return NO;
            if(!TKWoWCASCCloneVerification(verification,sourceData,stagedData,&failure))return NO;
            if(![sourceHash writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:&failure])return NO;
        }
        if(![stage.stringByResolvingSymlinksInPath isEqual:stage])return Fail(&failure,@"Staging directory must not be a symlink.");
        NSString *dataRoot=Join(stage,@"Data"), *cache=Join(job,@"cache"), *indices=Join(dataRoot,@"indices");
        if(!Directory(cache,&failure) || !Directory(dataRoot,&failure))return NO;
        NSMutableArray *configs=[@[plan[@"version"][@"BuildConfig"],plan[@"version"][@"CDNConfig"]] mutableCopy];
        if(plan[@"version"][@"ProductConfig"]) [configs addObject:plan[@"version"][@"ProductConfig"]];
        for(NSString *key in configs) {
            NSData *data=[_client configuration:key cdn:plan[@"cdn"] error:&failure];if(!data)return NO;
            NSString *relative=[NSString stringWithFormat:@"Data/config/%@/%@/%@",[key substringToIndex:2],[key substringWithRange:NSMakeRange(2,2)],key];
            if(!SafeWrite(stage,relative,data,&failure))return NO;
        }
        progress(@"manifests",0,0);
        NSData *encoding=[_client encodingForPlan:plan directory:cache error:&failure];if(!encoding)return NO;
        NSData *download=[_client manifest:@"download" config:plan[@"config"] cdn:plan[@"cdn"] error:&failure];if(!download)return NO;
        NSData *records=TKWoWDownloads(download,plan[@"locale"],plan[@"region"],&failure);download=nil;if(!records)return NO;
        store=[[TKWoWCASCStore alloc] initWithDirectory:Join(dataRoot,@"data") error:&failure];if(!store)return NO;
        if(_fullVerification)[store discardVerification];
        // Plan missing objects after content verification, using compact records.
        const TKWoWDownloadEntry *entries=records.bytes; NSUInteger count=records.length/sizeof(*entries);
        NSMutableData *missing=[NSMutableData new];uint64_t required=0,processed=0,total=0;
        for(NSUInteger i=0;i<count;i++)total+=entries[i].size;
        for(NSUInteger i=0;i<count;i++) { @autoreleasepool {
            if([self cancelled:&failure])return NO;
            NSString *key=TKWoWHex(entries[i].key,16);
            if(![store verifyKey:key size:entries[i].size]) { [missing appendBytes:entries+i length:sizeof(*entries)];required+=entries[i].size+30; }
            processed+=entries[i].size;
            if(i%500==0 || i+1==count) {
                if(store.verificationBytesReused)progress(@"reuse",i+1,count);
                else progress(@"verify",processed,total);
            }
        }}
        records=nil;
        if(![store saveVerification:&failure])return NO;
        uint64_t loose=[plan[@"installFileBytes"] unsignedLongLongValue];
        uint64_t free=[[[fm attributesOfFileSystemForPath:stage error:&failure] objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
        if(required>UINT64_MAX-loose-1024*1024*1024 || free<required+loose+1024*1024*1024)return Fail(&failure,[NSString stringWithFormat:@"Not enough storage. Need at least %.1f GB free for this update.",(required+loose+1024*1024*1024)/1e9]);
        _client.progress=progress;
        uint64_t transferBytes=required-30*(missing.length/sizeof(TKWoWDownloadEntry));
        __block uint64_t downloaded=0,checkpoint=0;__block double lastProgress=0;
        if(![_client downloadEntries:missing plan:plan indices:indices consume:^BOOL(NSData *raw,NSString *key,NSError **problem) {
            if(![store addData:raw key:key error:problem])return NO;
            downloaded+=raw.length;checkpoint+=raw.length;
            double now=NSDate.timeIntervalSinceReferenceDate;
            if(now-lastProgress>0.15) { progress(@"download",downloaded,transferBytes);lastProgress=now; }
            if(checkpoint>=64*1024*1024) { if(![store checkpoint:problem])return NO;checkpoint=0; }
            return YES;
        } error:&failure])return NO;
        progress(@"download",downloaded,downloaded);
        // These bootstrap manifests are not necessarily in the download list.
        NSMutableArray *bootstrap=[@[@"encoding",@"install",@"download"] mutableCopy];
        if(plan[@"config"][@"size"]) [bootstrap addObject:@"size"];
        if(plan[@"config"][@"patch-index"]) [bootstrap addObject:@"patch-index"];
        for(NSString *key in plan[@"config"]) {
            if([key hasPrefix:@"vfs-"] && ![key hasSuffix:@"-size"]) {
                [bootstrap addObject:key];
            }
        }
        for(NSString *name in bootstrap) { @autoreleasepool {
            NSArray *keys=Words(plan[@"config"][name]), *sizes=Words(plan[@"config"][[name stringByAppendingString:@"-size"]]);
            if(keys.count!=2 || sizes.count!=2)return Fail(&failure,@"Missing bootstrap manifest.");
            uint64_t size=[sizes[1] longLongValue];
            if(![store verifyKey:keys[1] size:size]) {
                NSData *raw=[_client encodedKey:keys[1] size:size plan:plan indices:indices error:&failure];
                if(!raw || ![store addData:raw key:keys[1] error:&failure])return NO;
            }
        }}
        // The root manifest is addressed by content hash in the build config
        // and may be absent from the download list, especially on fresh installs.
        NSArray *roots=Words(plan[@"config"][@"root"]);
        if(roots.count!=1)return Fail(&failure,@"Unsupported root manifest configuration.");
        NSString *rootKey=TKWoWEncodingKey(encoding,roots[0],&failure);if(!rootKey)return NO;
        if(![store verifyKey:rootKey size:0]) {
            NSData *raw=[_client encodedKey:rootKey size:0 plan:plan indices:indices error:&failure];
            if(!raw || ![store addData:raw key:rootKey error:&failure])return NO;
        }
        NSUInteger done=0;
        for(NSDictionary *file in plan[@"files"]) { @autoreleasepool {
            if([self cancelled:&failure])return NO;
            NSString *relative=file[@"path"], *top=[relative.pathComponents.firstObject lowercaseString];
            if(!SafeRelative(relative) || [@[@"wtf",@"interface",@"data",@".build.info"] containsObject:top])return Fail(&failure,@"An installation file conflicts with protected user data.");
            NSString *target=Join(folder,relative);uint64_t size=[file[@"size"] unsignedLongLongValue];
            if(size>256*1024*1024)return Fail(&failure,@"A loose file exceeds the supported size limit.");
            NSDictionary *attrs=[fm attributesOfItemAtPath:Join(stage,target) error:NULL];NSData *existing=nil;
            if([attrs[NSFileSize] unsignedLongLongValue]==size)existing=[NSData dataWithContentsOfFile:Join(stage,target) options:NSDataReadingMappedIfSafe error:NULL];
            if(!existing || ![TKWoWMD5(existing) isEqual:file[@"contentKey"]]) {
                NSString *key=TKWoWEncodingKey(encoding,file[@"contentKey"],&failure);if(!key)return NO;
                NSData *raw=[store readKey:key size:0];if(!raw)raw=[_client encodedKey:key size:0 plan:plan indices:indices error:&failure];if(!raw)return NO;
                NSData *original=TKWoWDecode(raw,key,file[@"contentKey"],(NSUInteger)size,256*1024*1024,&failure);if(!original)return NO;
                if(!SafeWrite(stage,target,original,&failure))return NO;
            }
            progress(@"files",++done,[plan[@"files"] count]);
        }}
        if(![store checkpoint:&failure])return NO;
        if(![store saveVerification:&failure])return NO;
        NSData *flavor=[[NSString stringWithFormat:@"Product Flavor!STRING:0\n%@\n",plan[@"product"]] dataUsingEncoding:NSUTF8StringEncoding];
        if(!SafeWrite(stage,Join(folder,@".flavor.info"),flavor,&failure) || ![self writeBuildInfo:plan root:stage error:&failure])return NO;
        if([self cancelled:&failure])return NO;
        current=[_client versionForProduct:plan[@"product"] region:plan[@"region"] error:&failure];if(!current)return NO;
        if(!SameBuild(current,plan[@"version"]))return Fail(&failure,@"A newer build arrived during the download. Reopen to update to it.");
        if([self cancelled:&failure])return NO;
        NSData *latestInfo=BuildInfo(root,&failure);if(!latestInfo)return NO;
        if(![TKWoWMD5(latestInfo) isEqual:sourceHash])return Fail(&failure,@"The installed copy changed during the update. Reopen to retry.");
        // Pick up user settings/addon edits made while the download was paused.
        for(NSString *userFolder in @[@"WTF",@"Interface"]) {
            NSString *relative=Join(folder,userFolder), *source=Join(root,relative), *destination=Join(stage,relative);
            if([fm fileExistsAtPath:destination] && ![fm removeItemAtPath:destination error:&failure])return NO;
            if([fm fileExistsAtPath:source] && ![self cloneRoot:source into:destination progress:progress error:&failure])return NO;
        }
        NSString *settings=Join(folder,@"WTF/Config.wtf");
        NSString *settingsPath=Join(stage,settings);
        if(![fm fileExistsAtPath:settingsPath]) {
            // New installs skip the unsupported region picker. Existing account,
            // input and graphics settings are never replaced.
            NSString *portal=[plan[@"product"] containsString:@"beta"]?@"test":[plan[@"region"] uppercaseString];
            NSString *initial=[NSString stringWithFormat:@"SET portal \"%@\"\nSET textLocale \"%@\"\nSET audioLocale \"%@\"\n",portal,plan[@"locale"],plan[@"locale"]];
            if(!SafeWrite(stage,settings,[initial dataUsingEncoding:NSUTF8StringEncoding],&failure))return NO;
        } else {
            NSError *readError=nil;
            NSString *content=[NSString stringWithContentsOfFile:settingsPath encoding:NSUTF8StringEncoding error:&readError];
            if([content containsString:@"SET textLocale "] || [content containsString:@"SET audioLocale "]) {
                NSMutableString *updated=[NSMutableString new];
                for(NSString *line in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                    if([line hasPrefix:@"SET textLocale "]) {
                        [updated appendFormat:@"SET textLocale \"%@\"\n",plan[@"locale"]];
                    } else if([line hasPrefix:@"SET audioLocale "]) {
                        [updated appendFormat:@"SET audioLocale \"%@\"\n",plan[@"locale"]];
                    } else if(line.length) {
                        [updated appendFormat:@"%@\n",line];
                    }
                }
                SafeWrite(stage,settings,[updated dataUsingEncoding:NSUTF8StringEncoding],&failure);
            }
        }
        if([self cancelled:&failure])return NO;
        progress(@"activate",0,0);
        // One filesystem operation activates metadata, executable and data together.
        int result=[fm fileExistsAtPath:root]?renamex_np(stage.fileSystemRepresentation,root.fileSystemRepresentation,RENAME_SWAP):rename(stage.fileSystemRepresentation,root.fileSystemRepresentation);
        if(result)return Fail(&failure,[NSString stringWithFormat:@"Cannot activate the verified installation (%s).",strerror(errno)]);
        success=YES;
        _verificationBytesRead=store.verificationBytesRead;_verificationBytesReused=store.verificationBytesReused;store=nil;
        // stage now holds only the replaced private snapshot. The new root owns
        // settings and addons unchanged; clean up this transaction's old clone.
        [fm removeItemAtPath:job error:NULL];progress(@"complete",1,1);return YES;
    } @finally {
        if(!success && store) {
            if([store checkpoint:NULL])[store saveVerification:NULL];
            _verificationBytesRead=store.verificationBytesRead;_verificationBytesReused=store.verificationBytesReused;
        }
        if(!success && failure && error)*error=failure;
        _client.progress=nil;flock(lock,LOCK_UN);close(lock);
    }
}
@end
