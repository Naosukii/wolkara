#import <Foundation/Foundation.h>
#import "../launcher/WoW/Updater.h"
#import "../launcher/WoW/CASC.h"
#include <assert.h>
#include <unistd.h>
static NSData *Text(NSString *s){return [s dataUsingEncoding:NSUTF8StringEncoding];}
static void BE(NSMutableData *d,uint64_t n,NSUInteger bytes){while(bytes){uint8_t b=(uint8_t)(n>>(--bytes*8));[d appendBytes:&b length:1];}}
static NSData *Hash(NSData *d){uint8_t bytes[16];assert(TKWoWUnhex(TKWoWMD5(d),bytes));return [NSData dataWithBytes:bytes length:16];}
static NSData *Wrap(NSData *d){NSMutableData *r=[Text(@"BLTE") mutableCopy];BE(r,0,4);BE(r,'N',1);[r appendData:d];return r;}
@interface TKUpdateClient : TKWoWClient
@property(nonatomic) NSMutableDictionary *responses;
@property(nonatomic) NSMutableDictionary *counts;
@property(nonatomic) NSData *archive;
@property(nonatomic) BOOL changed;
@end
@implementation TKUpdateClient
- (instancetype)init { if((self=[super init])){_responses=[NSMutableDictionary new];_counts=[NSMutableDictionary new];}return self; }
- (NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit error:(NSError **)error {
    NSString *key=url.lastPathComponent;_counts[key]=@([_counts[key] unsignedIntegerValue]+1);
    NSData *data=_responses[key];if(self.changed && [key isEqual:@"versions"])data=Text(@"Region|BuildConfig|CDNConfig|VersionsName\neu|11111111111111111111111111111111|22222222222222222222222222222222|changed\n");
    if(self.cancelled || !data || data.length>limit){if(error)*error=TKWoWError(@"Synthetic missing/cancelled response");return nil;}return data;
}
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size error:(NSError **)error {
    (void)url; if(offset>_archive.length || size>_archive.length-offset){if(error)*error=TKWoWError(@"Bad synthetic range");return nil;}
    _counts[@"range"]=@([_counts[@"range"] unsignedIntegerValue]+1);return [_archive subdataWithRange:NSMakeRange((NSUInteger)offset,size)];
}
@end
static NSString *Reference(NSString *name,NSData *d,TKUpdateClient *client){NSData *raw=Wrap(d);client.responses[TKWoWMD5(raw)]=raw;return [NSString stringWithFormat:@"%@ = %@ %@\n%@-size = %lu %lu\n",name,TKWoWMD5(d),TKWoWMD5(raw),name,(unsigned long)d.length,(unsigned long)raw.length];}
static NSData *IndexObjects(NSArray<NSData *> *objects){
    NSMutableData *d=[NSMutableData new];uint32_t offset=37;
    for(NSData *raw in objects){[d appendData:Hash(raw)];BE(d,raw.length,4);BE(d,offset,4);offset+=(uint32_t)raw.length;}
    d.length=4096;[d appendData:Hash(objects.lastObject)];[d appendData:Hash(d)];
    uint8_t f[20]={1,0,0,4,4,4,16,8,0,0,0,0};f[8]=(uint8_t)objects.count;
    NSData *digest=Hash([NSData dataWithBytes:f length:20]);memcpy(f+12,digest.bytes,8);[d appendBytes:f length:20];return d;
}
static NSData *Index(NSData *raw){return IndexObjects(@[raw]);}

int main(void){@autoreleasepool{
    TKUpdateClient *client=[TKUpdateClient new];NSData *old=Text(@"old code"),*original=Text(@"our own new code"),*raw=Wrap(original);
    NSData *asset=Wrap(Text(@"new asset")),*present=Wrap(Text(@"existing asset"));
    client.responses[TKWoWMD5(asset)]=asset;client.responses[TKWoWMD5(present)]=present;
    NSMutableData *install=[Text(@"IN") mutableCopy];BE(install,1,1);BE(install,16,1);BE(install,0,2);BE(install,1,4);
    [install appendData:Text(@"Synthetic.app/Contents/MacOS/Synthetic")];BE(install,0,1);[install appendData:Hash(original)];BE(install,original.length,4);
    NSMutableData *encoding=[Text(@"EN") mutableCopy];BE(encoding,1,1);BE(encoding,16,1);BE(encoding,16,1);BE(encoding,1,2);BE(encoding,1,2);BE(encoding,1,4);BE(encoding,0,4);BE(encoding,0,1);BE(encoding,0,4);encoding.length+=32;
    BE(encoding,1,1);BE(encoding,original.length,5);[encoding appendData:Hash(original)];[encoding appendData:Hash(raw)];encoding.length=22+32+1024;
    NSMutableData *download=[Text(@"DL") mutableCopy];BE(download,3,1);BE(download,16,1);BE(download,0,1);BE(download,2,4);BE(download,0,2);BE(download,0,1);BE(download,0,4);
    for(NSData *entry in @[asset,present]){[download appendData:Hash(entry)];BE(download,entry.length,5);BE(download,0,1);}
    NSString *configuration=[NSString stringWithFormat:@"build-uid = wow_classic_beta\nroot = %@\n%@%@%@",TKWoWMD5(original),Reference(@"install",install,client),Reference(@"encoding",encoding,client),Reference(@"download",download,client)];
    NSString *build=TKWoWMD5(Text(configuration));client.responses[build]=Text(configuration);
    NSMutableData *archive=[NSMutableData dataWithLength:37];[archive appendData:raw];client.archive=archive;NSString *archiveKey=TKWoWMD5(archive);
    client.responses[[archiveKey stringByAppendingString:@".index"]]=Index(raw);
    NSData *cdnData=Text([NSString stringWithFormat:@"archives = %@\n",archiveKey]);NSString *cdn=TKWoWMD5(cdnData);client.responses[cdn]=cdnData;
    client.responses[@"versions"]=Text([NSString stringWithFormat:@"Region|BuildConfig|CDNConfig|VersionsName\neu|%@|%@|synthetic-2\n",build,cdn]);
    client.responses[@"cdns"]=Text(@"Name|Path|Servers\neu|tpr/wow|https://level3.ssl.blizzard.com\n");
    NSError *error=nil;NSDictionary *plan=[client planForProduct:@"wow_classic_beta" region:@"eu" locale:@"enUS" error:&error];assert(plan);
    NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString],*root=[base stringByAppendingPathComponent:@"World of Warcraft"];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *exe=[root stringByAppendingPathComponent:@"_classic_beta_/Synthetic.app/Contents/MacOS/Synthetic"];
    assert([fm createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]);assert([old writeToFile:exe atomically:YES]);
    NSString *settings=[root stringByAppendingPathComponent:@"_classic_beta_/WTF/Config.wtf"],*addon=[root stringByAppendingPathComponent:@"_classic_beta_/Interface/AddOns/OurFixture.txt"];
    for(NSString *path in @[settings,addon]){assert([fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]);assert([Text(@"keep me") writeToFile:path atomically:YES]);}
    NSData *info=Text(@"Product|Active|Build Key|CDN Key|Version\nwow_classic_beta|1|11111111111111111111111111111111|22222222222222222222222222222222|synthetic-1\n");
    assert([info writeToFile:[root stringByAppendingPathComponent:@".build.info"] atomically:YES]);
    TKWoWCASCStore *source=[[TKWoWCASCStore alloc] initWithDirectory:[root stringByAppendingPathComponent:@"Data/data"] error:&error];assert(source);
    assert([source addData:present key:TKWoWMD5(present) error:&error]);assert([source checkpoint:&error]);source=nil;
    __block BOOL paused=NO;
    BOOL result=[[[TKWoWUpdater alloc] initWithClient:client] updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)done;(void)total;if([phase isEqual:@"download"]){paused=YES;[client cancel];}} error:&error];
    if(!paused)fprintf(stderr,"Cancel fixture failed before download: %s\n",error.localizedDescription.UTF8String);
    assert(!result && paused);assert([[NSData dataWithContentsOfFile:exe] isEqual:old]);assert([[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".build.info"]] isEqual:info]);
    assert([Text(@"settings edited while paused") writeToFile:settings atomically:YES]);
    TKUpdateClient *resume=[TKUpdateClient new];resume.responses=client.responses;resume.archive=archive;
    __block BOOL changedMetadata=NO;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        (void)done;(void)total;
        if([phase isEqual:@"download"] && !changedMetadata) {
            // The resumed job has already reused the downloaded asset's receipt.
            // Changing metadata must recheck it, not restart or lose the patch.
            NSString *segment=[base stringByAppendingPathComponent:[NSString stringWithFormat:
                @".tolkara-updates/wow_classic_beta-%@-enUS/installation/Data/data/data.001",build]];
            assert([fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSinceNow:10]}
                ofItemAtPath:segment error:NULL]);changedMetadata=YES;
        }
    } error:&error];
    if(!result)fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);assert(result);
    assert(changedMetadata);
    assert([[NSData dataWithContentsOfFile:exe] isEqual:original]);assert([[NSData dataWithContentsOfFile:addon] isEqual:Text(@"keep me")]);assert([[NSData dataWithContentsOfFile:settings] isEqual:Text(@"settings edited while paused")]);
    assert(!resume.counts[TKWoWMD5(asset)] && !resume.counts[TKWoWMD5(present)]);assert([resume.counts[@"range"] unsignedIntegerValue]==1);
    NSArray *rows=TKWoWTable([NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".build.info"]],&error);assert(TKWoWBuildCurrent(rows,@"wow_classic_beta",plan[@"version"]));
    source=[[TKWoWCASCStore alloc] initWithDirectory:[root stringByAppendingPathComponent:@"Data/data"] error:&error];assert(source);assert([[source readKey:TKWoWMD5(asset) size:asset.length] isEqual:asset]);assert([[source readKey:TKWoWMD5(present) size:present.length] isEqual:present]);source=nil;
    // A new transaction clones the prior receipts and reads no unchanged CASC
    // payload, while still validating metadata and the original loose file.
    TKWoWUpdater *warm=[[TKWoWUpdater alloc] initWithClient:resume];
    __block BOOL reused=NO;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        (void)done;(void)total;if([phase isEqual:@"reuse"])reused=YES;
    } error:&error];
    if(!result)fprintf(stderr,"Warm update: %s\n",error.localizedDescription.UTF8String);assert(result && reused);
    assert(warm.verificationBytesRead==0 && warm.verificationBytesReused>=asset.length+present.length);
    warm.fullVerification=YES;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(result && warm.verificationBytesRead>0 && warm.verificationBytesReused==0);
    // A published patch adds one object: unchanged payload is not reread and
    // exactly that new object is fetched, across another atomic clone/swap.
    NSData *patchAsset=Wrap(Text(@"our next patch asset"));resume.responses[TKWoWMD5(patchAsset)]=patchAsset;
    NSMutableData *nextDownload=[download mutableCopy];((uint8_t *)nextDownload.mutableBytes)[8]=3;
    [nextDownload appendData:Hash(patchAsset)];BE(nextDownload,patchAsset.length,5);BE(nextDownload,0,1);
    NSString *nextConfiguration=[configuration stringByReplacingOccurrencesOfString:Reference(@"download",download,resume)
        withString:Reference(@"download",nextDownload,resume)];
    NSString *nextBuild=TKWoWMD5(Text(nextConfiguration));resume.responses[nextBuild]=Text(nextConfiguration);
    resume.responses[@"versions"]=Text([NSString stringWithFormat:@"Region|BuildConfig|CDNConfig|VersionsName\neu|%@|%@|synthetic-3\n",nextBuild,cdn]);
    plan=[resume planForProduct:@"wow_classic_beta" region:@"eu" locale:@"enUS" error:&error];assert(plan);
    warm.fullVerification=NO;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    if(!result)fprintf(stderr,"Incremental patch: %s\n",error.localizedDescription.UTF8String);assert(result);
    assert(warm.verificationBytesRead==0 && warm.verificationBytesReused>=asset.length+present.length);
    assert([resume.counts[TKWoWMD5(patchAsset)] unsignedIntegerValue]==1);
    // An external edit to an existing segment is caught on the next update;
    // only the broken object is downloaded again and user folders survive.
    NSString *dataDirectory=[root stringByAppendingPathComponent:@"Data/data"];
    NSDictionary *receipt=TKWoWCASCVerificationSnapshot(dataDirectory);assert(receipt);
    BOOL damaged=NO;uint8_t assetKey[16];assert(TKWoWUnhex(TKWoWMD5(asset),assetKey));
    for(NSData *bucket in receipt[@"buckets"]) {
        const uint8_t *p=bucket.bytes;
        for(NSUInteger i=0;i<bucket.length;i+=25)if(!memcmp(p+i,assetKey,16)) {
            uint64_t location=0;for(unsigned j=0;j<5;j++)location=(location<<8)|p[i+16+j];
            NSString *path=[dataDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"data.%03llu",location>>30]];
            NSFileHandle *file=[NSFileHandle fileHandleForUpdatingAtPath:path];assert(file);
            [file seekToFileOffset:(location&0x3fffffff)+30+asset.length-1];[file writeData:Text(@"!")];[file closeFile];damaged=YES;
        }
    }
    assert(damaged);NSUInteger oldDownloads=[resume.counts[TKWoWMD5(asset)] unsignedIntegerValue];
    warm.fullVerification=NO;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    if(!result)fprintf(stderr,"Changed segment: %s\n",error.localizedDescription.UTF8String);assert(result);
    assert([resume.counts[TKWoWMD5(asset)] unsignedIntegerValue]==oldDownloads+1);
    assert([[NSData dataWithContentsOfFile:addon] isEqual:Text(@"keep me")]);
    // The receipt is optional: loss/corruption must produce full verification.
    assert([Text(@"broken receipt") writeToFile:[dataDirectory stringByAppendingPathComponent:@".wolkara-verified"] atomically:YES]);
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(result && warm.verificationBytesRead>0 && warm.verificationBytesReused==0);
    // A newly published build before activation leaves the previous root intact.
    resume.changed=NO;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)done;(void)total;if([phase isEqual:@"files"])resume.changed=YES;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"newer build"]);assert([[NSData dataWithContentsOfFile:exe] isEqual:original]);
    // Adjacent archive objects use one request; corrupt bytes never reach storage.
    TKUpdateClient *batch=[TKUpdateClient new];batch.archive=[NSMutableData dataWithLength:37];
    [(NSMutableData *)batch.archive appendData:asset];[(NSMutableData *)batch.archive appendData:present];
    NSString *batchArchive=TKWoWMD5(batch.archive);
    NSData *batchConfig=Text([NSString stringWithFormat:@"archives = %@\n",batchArchive]);
    batch.responses[TKWoWMD5(batchConfig)]=batchConfig;batch.responses[[batchArchive stringByAppendingString:@".index"]]=IndexObjects(@[asset,present]);
    NSMutableDictionary *batchPlan=[plan mutableCopy],*batchVersion=[plan[@"version"] mutableCopy];
    batchVersion[@"CDNConfig"]=TKWoWMD5(batchConfig);batchPlan[@"version"]=batchVersion;
    NSData *requests=TKWoWDownloads(download,@"enUS",@"eu",&error);__block NSUInteger consumed=0;
    NSString *indices=[base stringByAppendingPathComponent:@"batch-indices"];
    assert([batch downloadEntries:requests plan:batchPlan indices:indices consume:^BOOL(NSData *bytes,NSString *key,NSError **problem){
        (void)problem;assert(([@[asset,present] containsObject:bytes]));assert([TKWoWMD5(bytes) isEqual:key]);consumed++;return YES;
    } error:&error]);
    assert(consumed==2 && [batch.counts[@"range"] unsignedIntegerValue]==1);
    NSMutableData *broken=[batch.archive mutableCopy];((uint8_t *)broken.mutableBytes)[37+asset.length-1]^=1;batch.archive=broken;
    consumed=0;error=nil;
    assert(![batch downloadEntries:requests plan:batchPlan indices:indices consume:^BOOL(NSData *bytes,NSString *key,NSError **problem){
        (void)bytes;(void)key;(void)problem;consumed++;return YES;
    } error:&error]);
    assert(consumed==0 && [error.localizedDescription containsString:@"checksum"]);
    // Errors originating inside an autorelease pool remain valid to the caller.
    resume.changed=NO;
    NSMutableDictionary *protectedPlan=[plan mutableCopy];
    protectedPlan[@"files"]=@[@{@"path":@"WTF/Config.wtf",@"size":@1,@"contentKey":TKWoWMD5(Text(@"x"))}];
    error=nil;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:protectedPlan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"protected user data"]);
    assert([[NSData dataWithContentsOfFile:settings] isEqual:Text(@"settings edited while paused")]);
    // An escaping symlink must fail during cloning without reading its target.
    NSString *unsafeRoot=[base stringByAppendingPathComponent:@"unsafe"];
    assert([fm createDirectoryAtPath:unsafeRoot withIntermediateDirectories:YES attributes:nil error:&error]);
    assert([fm createSymbolicLinkAtPath:[unsafeRoot stringByAppendingPathComponent:@"escape"] withDestinationPath:@"/Applications" error:&error]);
    error=nil;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:unsafeRoot progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"outside its installation"]);
    assert([fm fileExistsAtPath:[unsafeRoot stringByAppendingPathComponent:@"escape"]]);
    // Optional packs and other platforms are excluded, common data remains.
    NSMutableData *tagged=[download mutableCopy];((uint8_t *)tagged.mutableBytes)[10]=2;
    [tagged appendData:Text(@"HighRes")];BE(tagged,0,1);BE(tagged,0x4000,2);BE(tagged,0x80,1);
    [tagged appendData:Text(@"OSX")];BE(tagged,0,1);BE(tagged,1,2);BE(tagged,0x40,1);
    NSData *selection=TKWoWDownloads(tagged,@"enUS",@"eu",&error);assert(selection.length==sizeof(TKWoWDownloadEntry));
    const TKWoWDownloadEntry *picked=selection.bytes;assert([TKWoWHex(picked->key,16) isEqual:TKWoWMD5(present)]);
    // Locale tags select German content instead of the English payload.
    NSMutableData *localized=[download mutableCopy];((uint8_t *)localized.mutableBytes)[10]=2;
    [localized appendData:Text(@"enUS")];BE(localized,0,1);BE(localized,3,2);BE(localized,0x80,1);
    [localized appendData:Text(@"deDE")];BE(localized,0,1);BE(localized,3,2);BE(localized,0x40,1);
    selection=TKWoWDownloads(localized,@"deDE",@"eu",&error);assert(selection.length==sizeof(TKWoWDownloadEntry));
    picked=selection.bytes;assert([TKWoWHex(picked->key,16) isEqual:TKWoWMD5(present)]);
    selection=TKWoWDownloads(localized,@"enUS",@"eu",&error);assert(selection.length==sizeof(TKWoWDownloadEntry));
    picked=selection.bytes;assert([TKWoWHex(picked->key,16) isEqual:TKWoWMD5(asset)]);
    // A fresh synthetic install activates all files and only initial locale/portal settings.
    NSString *freshRoot=[base stringByAppendingPathComponent:@"fresh-parent/World of Warcraft"];
    resume.changed=NO;error=nil;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:freshRoot progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    if(!result)fprintf(stderr,"Fresh install: %s\n",error.localizedDescription.UTF8String);assert(result);
    NSString *freshConfig=[NSString stringWithContentsOfFile:[freshRoot stringByAppendingPathComponent:@"_classic_beta_/WTF/Config.wtf"] encoding:NSUTF8StringEncoding error:&error];
    assert([freshConfig containsString:@"SET portal \"test\""] && [freshConfig containsString:@"SET textLocale \"enUS\""]);
    // German follows the same verified download/install pipeline, with German text and audio.
    error=nil;
    NSDictionary *germanPlan=[resume planForProduct:@"wow_classic_beta" region:@"eu" locale:@"deDE" error:&error];
    assert(germanPlan && !error && [germanPlan[@"locale"] isEqual:@"deDE"]);
    NSString *germanRoot=[base stringByAppendingPathComponent:@"german/World of Warcraft"];
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:germanPlan root:germanRoot progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    if(!result)fprintf(stderr,"German install: %s\n",error.localizedDescription.UTF8String);assert(result);
    NSString *germanConfig=[NSString stringWithContentsOfFile:[germanRoot stringByAppendingPathComponent:@"_classic_beta_/WTF/Config.wtf"] encoding:NSUTF8StringEncoding error:&error];
    assert([germanConfig containsString:@"SET portal \"test\""] && [germanConfig containsString:@"SET textLocale \"deDE\""] && [germanConfig containsString:@"SET audioLocale \"deDE\""]);
    NSArray *germanRows=TKWoWTable([NSData dataWithContentsOfFile:[germanRoot stringByAppendingPathComponent:@".build.info"]],&error);
    assert([germanRows[0][@"Tags"] containsString:@"deDE text?"] && [germanRows[0][@"Tags"] containsString:@"deDE speech?"]);
    // Reject oversized local metadata before cloning or allocating its contents.
    NSData *oversized=[NSMutableData dataWithLength:2*1024*1024+1];
    assert([oversized writeToFile:[freshRoot stringByAppendingPathComponent:@".build.info"] atomically:YES]);
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:freshRoot progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"oversized"]);
    // Malformed binary data is rejected, including every truncation of our DL fixture.
    for(NSUInteger n=0;n<download.length;n++)assert(!TKWoWDownloads([download subdataWithRange:NSMakeRange(0,n)],@"enUS",@"eu",NULL));
    NSMutableData *bad=[asset mutableCopy];((uint8_t *)bad.mutableBytes)[bad.length-1]^=1;assert(!TKWoWEncodedValid(bad,TKWoWMD5(asset),NULL));
    bad=[Index(raw) mutableCopy];((uint8_t *)bad.mutableBytes)[bad.length-1]^=1;assert(!TKWoWArchiveEntries(bad,0,NULL));
    assert(TKWoWJenkins("",0,NULL,0)==0xdeadbeef);
    assert([fm removeItemAtPath:base error:&error]);
    puts("WoW updater PASS: unchanged data reuse, archive ranges, cancel before activation, durable resume, atomic activation, settings/addon preservation, superseded build and malformed input.");
}return 0;}
