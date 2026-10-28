#import "Client.h"
#import "CASC.h"

// A client reuses one connection pool, with serial transfers and bounded buffers. No cookies,
// credentials, redirects, HTTP fallback, or application-installation writes.
@interface TKWoWTransfer : NSObject <NSURLSessionDataDelegate>
@property(nonatomic) NSMutableData *data;
@property(nonatomic) NSError *error;
@property(nonatomic) NSUInteger limit;
@property(nonatomic) NSString *range;
@property(nonatomic) dispatch_semaphore_t done;
@end
@implementation TKWoWTransfer
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    (void)session; (void)task;
    NSInteger status=[(NSHTTPURLResponse *)response statusCode];
    BOOL rangeOK=!self.range || (status==206 && [[(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"Content-Range"] hasPrefix:[self.range stringByAppendingString:@"/"]]);
    if (status!=(self.range?206:200) || !rangeOK || response.expectedContentLength>(int64_t)self.limit) {
        self.error=TKWoWError(status!=200 ? [NSString stringWithFormat:@"Download failed (HTTP %ld).",(long)status] : @"Download exceeds its size limit.");
        completion(NSURLSessionResponseCancel);
    } else completion(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)session;
    if (data.length>self.limit-self.data.length) {
        self.error=TKWoWError(@"Download exceeds its size limit."); [task cancel];
    } else [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest * _Nullable))completion {
    (void)session; (void)task; (void)response; (void)request;
    self.error=TKWoWError(@"Unexpected download redirect."); completion(nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session; (void)task;
    if (!self.error) self.error=error;
    dispatch_semaphore_signal(self.done);
}
@end

@implementation TKWoWClient {
    NSLock *_lock;
    BOOL _cancelled;
    NSURLSession *_session;
    TKWoWTransfer *_transfer;
    NSData *_archiveTable;
    NSArray<NSString *> *_archives;
    NSString *_archiveConfig;

}
- (instancetype)init {
    if ((self=[super init])) _lock=[NSLock new];
    return self;
}
- (void)dealloc { [_session invalidateAndCancel]; }
- (void)cancel {
    [_lock lock]; _cancelled=YES; [_session invalidateAndCancel]; [_lock unlock];
}
- (BOOL)cancelled { [_lock lock]; BOOL value=_cancelled; [_lock unlock]; return value; }
- (NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit error:(NSError **)error {
    return [self transferURL:url offset:0 size:0 limit:limit error:error];
}
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size error:(NSError **)error {
    return [self transferURL:url offset:offset size:size limit:size error:error];
}
- (NSData *)transferURL:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size limit:(NSUInteger)limit error:(NSError **)error {
    if (![url.scheme isEqualToString:@"https"] || !url.host.length || url.user || url.password) {
        if (error) *error=TKWoWError(@"A valid HTTPS download URL is required.");
        return nil;
    }
    [_lock lock];
    if(_cancelled) {
        [_lock unlock];if(error)*error=TKWoWError(@"Download cancelled.");return nil;
    }
    if(!_session) {
        _transfer=[TKWoWTransfer new];
        NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;config.URLCache=nil;
        config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
        config.timeoutIntervalForRequest=30;config.timeoutIntervalForResource=300;
        config.HTTPMaximumConnectionsPerHost=1;
        config.HTTPAdditionalHeaders=@{@"Accept-Encoding":@"identity"};
        NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;
        _session=[NSURLSession sessionWithConfiguration:config delegate:_transfer delegateQueue:queue];
    }
    TKWoWTransfer *transfer=_transfer;
    transfer.data=[NSMutableData new];transfer.error=nil;transfer.range=nil;
    transfer.limit=limit;transfer.done=dispatch_semaphore_create(0);
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    if(size) {
        NSString *bounds=[NSString stringWithFormat:@"%llu-%llu",offset,offset+size-1];
        [request setValue:[@"bytes=" stringByAppendingString:bounds] forHTTPHeaderField:@"Range"];
        transfer.range=[@"bytes " stringByAppendingString:bounds];
    }
    [[_session dataTaskWithRequest:request] resume];
    [_lock unlock];
    // Delegate completion is guaranteed by the resource timeout/cancellation.
    dispatch_semaphore_wait(transfer.done,DISPATCH_TIME_FOREVER);
    [_lock lock]; BOOL cancelled=_cancelled; [_lock unlock];
    if (transfer.error || cancelled) {
        if (error) *error=transfer.error?:TKWoWError(@"Download cancelled.");
        return nil;
    }
    if(size && transfer.data.length!=size) { if(error)*error=TKWoWError(@"Incomplete range download.");return nil; }
    return transfer.data;
}
- (NSDictionary *)rowAt:(NSURL *)url field:(NSString *)field value:(NSString *)value error:(NSError **)error {
    NSData *data=[self fetch:url limit:2*1024*1024 error:error];
    if (!data) return nil;
    NSArray *rows=TKWoWTable(data,error);
    if (!rows) return nil;
    NSDictionary *match=nil;
    for (NSDictionary *row in rows) if ([row[field] isEqualToString:value]) {
        if (match) { if (error) *error=TKWoWError(@"Ambiguous region metadata."); return nil; }
        match=row;
    }
    if (!match && error) *error=TKWoWError(@"This channel is not available in the selected region.");
    return match;
}
- (BOOL)validProduct:(NSString *)product region:(NSString *)region error:(NSError **)error {
    BOOL known=NO;
    for (NSDictionary *entry in TKWoWProducts()) if ([entry[@"id"] isEqualToString:product]) known=YES;
    if (!known || ![@[@"eu",@"us",@"kr",@"tw"] containsObject:region]) {
        if (error) *error=TKWoWError(@"Unknown product or region.");
        return NO;
    }
    return YES;
}
- (NSURL *)endpoint:(NSString *)product region:(NSString *)region name:(NSString *)name {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://%@.version.battle.net/v2/products/%@/%@",region,product,name]];
}
- (NSDictionary *)versionForProduct:(NSString *)product region:(NSString *)region error:(NSError **)error {
    if (![self validProduct:product region:region error:error]) return nil;
    NSDictionary *row=[self rowAt:[self endpoint:product region:region name:@"versions"] field:@"Region" value:region error:error];
    if (!row) return nil;
    if (!TKWoWHashValid(row[@"BuildConfig"]) || !TKWoWHashValid(row[@"CDNConfig"]) || ![row[@"VersionsName"] length]) {
        if (error) *error=TKWoWError(@"The channel has no usable build.");
        return nil;
    }
    return row;
}
- (NSString *)cdn:(NSString *)product region:(NSString *)region error:(NSError **)error {
    NSDictionary *row=[self rowAt:[self endpoint:product region:region name:@"cdns"] field:@"Name" value:region error:error];
    if (!row) return nil;
    if (![row[@"Path"] isEqualToString:@"tpr/wow"]) {
        if (error) *error=TKWoWError(@"Unsupported CDN path."); return nil;
    }
    for (NSString *server in [row[@"Servers"] componentsSeparatedByString:@" "]) {
        NSURL *url=[NSURL URLWithString:server];
        NSString *host=url.host.lowercaseString;
        if ([url.scheme isEqualToString:@"https"] && !url.user && !url.password && !url.port &&
            ([host hasSuffix:@".blizzard.com"] || [host hasSuffix:@".akamaihd.net"]))
            return [NSString stringWithFormat:@"https://%@/tpr/wow",host];
    }
    if (error) *error=TKWoWError(@"No supported HTTPS CDN is advertised.");
    return nil;
}
- (NSData *)object:(NSString *)key kind:(NSString *)kind cdn:(NSString *)cdn limit:(NSUInteger)limit error:(NSError **)error {
    if (!TKWoWHashValid(key)) { if (error) *error=TKWoWError(@"Invalid content hash."); return nil; }
    NSString *url=[NSString stringWithFormat:@"%@/%@/%@/%@/%@",cdn,kind,[key substringToIndex:2],[key substringWithRange:NSMakeRange(2,2)],key];
    return [self fetch:[NSURL URLWithString:url] limit:limit error:error];
}
static NSArray *Words(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @[];
    return [[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
}
static NSUInteger ManifestSize(NSString *text) {
    if (![text isKindOfClass:NSString.class] || !text.length || text.length>10 ||
        [text rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location!=NSNotFound) return 0;
    return (NSUInteger)text.longLongValue;
}
- (NSData *)manifest:(NSString *)name config:(NSDictionary *)config cdn:(NSString *)cdn error:(NSError **)error {
    NSArray *keys=Words(config[name]), *sizes=Words(config[[name stringByAppendingString:@"-size"]]);
    if (keys.count!=2 || sizes.count!=2 || !ManifestSize(sizes[0]) || !ManifestSize(sizes[1]) ||
        ManifestSize(sizes[0])>256*1024*1024 || ManifestSize(sizes[1])>256*1024*1024) {
        if (error) *error=TKWoWError(@"Unsupported manifest size or configuration."); return nil;
    }
    NSData *data=[self object:keys[1] kind:@"data" cdn:cdn limit:ManifestSize(sizes[1]) error:error];
    if (!data) return nil;
    if (data.length!=ManifestSize(sizes[1])) { if (error) *error=TKWoWError(@"Incomplete manifest download."); return nil; }
    return TKWoWDecode(data,keys[1],keys[0],ManifestSize(sizes[0]),256*1024*1024,error);
}
- (NSDictionary *)planForProduct:(NSString *)product region:(NSString *)region locale:(NSString *)locale error:(NSError **)error {
    if (![@[@"enUS",@"esES",@"deDE",@"frFR",@"itIT",@"esMX",@"ptBR",@"ruRU",@"koKR",@"zhTW"] containsObject:locale]) {
        if (error) *error=TKWoWError(@"Unsupported locale."); return nil;
    }
    NSDictionary *version=[self versionForProduct:product region:region error:error];
    if (!version) return nil;
    NSString *cdn=[self cdn:product region:region error:error];
    if (!cdn) return nil;
    NSData *data=[self object:version[@"BuildConfig"] kind:@"config" cdn:cdn limit:2*1024*1024 error:error];
    if (!data) return nil;
    if (![TKWoWMD5(data) isEqualToString:version[@"BuildConfig"]]) {
        if (error) *error=TKWoWError(@"Build configuration checksum mismatch."); return nil;
    }
    NSDictionary *config=TKWoWConfig(data,error);
    if (!config) return nil;
    if (![config[@"build-uid"] isEqualToString:product]) {
        if (error) *error=TKWoWError(@"The build belongs to a different product."); return nil;
    }
    NSData *install=[self manifest:@"install" config:config cdn:cdn error:error];
    if (!install) return nil;
    NSArray *entries=TKWoWInstall(install,error);
    if (!entries) return nil;
    NSArray *selected=TKWoWMacFiles(entries,locale,region);
    // Conflicting paths cannot be silently overwritten when eventually installing.
    NSMutableDictionary *seen=[NSMutableDictionary new];
    uint64_t total=0;
    for (NSDictionary *file in selected) {
        NSString *path=[file[@"path"] lowercaseString];
        if (seen[path]) { if (error) *error=TKWoWError(@"Ambiguous install tags: multiple files map to one path."); return nil; }
        seen[path]=file; total+=[file[@"size"] unsignedLongLongValue];
    }
    if (!selected.count) { if (error) *error=TKWoWError(@"No macOS ARM64 install files in this build."); return nil; }
    return @{@"product":product,@"region":region,@"locale":locale,@"version":version,@"cdn":cdn,
        @"config":config,@"files":selected,@"installFileBytes":@(total),@"complete":@NO};
}
- (NSString *)stageFile:(NSDictionary *)file plan:(NSDictionary *)plan directory:(NSString *)directory error:(NSError **)error {
    if (![plan[@"files"] containsObject:file] || !TKWoWHashValid(file[@"contentKey"]) ||
        ![file[@"size"] unsignedIntegerValue] || [file[@"size"] unsignedIntegerValue]>256*1024*1024) {
        if (error) *error=TKWoWError(@"File is absent from the plan or exceeds the extraction limit."); return nil;
    }
    // Re-query before a large operation; never continue an already superseded plan.
    NSDictionary *current=[self versionForProduct:plan[@"product"] region:plan[@"region"] error:error];
    if (!current) return nil;
    if (![current[@"BuildConfig"] isEqual:plan[@"version"][@"BuildConfig"]] ||
        ![current[@"CDNConfig"] isEqual:plan[@"version"][@"CDNConfig"]]) {
        if (error) *error=TKWoWError(@"A newer build is available. Check this channel again."); return nil;
    }
    NSData *encoding=[self encodingForPlan:plan directory:directory error:error];
    if(!encoding)return nil;
    NSString *key=TKWoWEncodingKey(encoding,file[@"contentKey"],error);
    if (!key) return nil;
    NSData *raw=[self encodedKey:key size:0 plan:plan indices:[directory stringByAppendingPathComponent:@"indices"] error:error];
    if(!raw)return nil;
    NSData *decoded=TKWoWDecode(raw,key,file[@"contentKey"],[file[@"size"] unsignedIntegerValue],256*1024*1024,error);
    if (!decoded) return nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    // Content-addressed flat output, never a path supplied by the manifest.
    NSString *path=[directory stringByAppendingPathComponent:[file[@"contentKey"] stringByAppendingString:@".original"]];
    if (![decoded writeToFile:path options:NSDataWritingAtomic error:error]) return nil;
    return path;
}
- (NSData *)encodingForPlan:(NSDictionary *)plan directory:(NSString *)directory error:(NSError **)error {
    NSArray *encodingKeys=Words(plan[@"config"][@"encoding"]), *encodingSizes=Words(plan[@"config"][@"encoding-size"]);
    if (encodingKeys.count!=2 || encodingSizes.count!=2 || !TKWoWHashValid(encodingKeys[0])) {
        if (error) *error=TKWoWError(@"Invalid encoding configuration."); return nil;
    }
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *cache=[directory stringByAppendingPathComponent:[encodingKeys[0] stringByAppendingString:@".encoding"]];
    NSData *encoding=nil;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:cache error:nil];
    if ([attributes[NSFileSize] unsignedLongLongValue]==ManifestSize(encodingSizes[0]) &&
        ManifestSize(encodingSizes[0])<=256*1024*1024) {
        NSData *cached=[NSData dataWithContentsOfFile:cache options:NSDataReadingMappedIfSafe error:nil];
        if (cached && [TKWoWMD5(cached) isEqual:encodingKeys[0]]) encoding=cached;
    }
    if (!encoding) {
        encoding=[self manifest:@"encoding" config:plan[@"config"] cdn:plan[@"cdn"] error:error];
        if (encoding && ![encoding writeToFile:cache options:NSDataWritingAtomic error:error]) return nil;
    }
    return encoding;
}
- (NSData *)productConfiguration:(NSString *)key cdn:(NSString *)cdn error:(NSError **)error {
    if (!TKWoWHashValid(key)) { if (error) *error=TKWoWError(@"Invalid content hash."); return nil; }
    NSURL *cdnURL=[NSURL URLWithString:cdn];
    NSString *host=cdnURL.host.length?cdnURL.host:@"level3.ssl.blizzard.com";
    NSString *url=[NSString stringWithFormat:@"https://%@/tpr/configs/data/%@/%@/%@",host,[key substringToIndex:2],[key substringWithRange:NSMakeRange(2,2)],key];
    NSData *data=[self fetch:[NSURL URLWithString:url] limit:2*1024*1024 error:error];
    if(!data && ![host isEqualToString:@"level3.ssl.blizzard.com"]) {
        NSString *fallbackUrl=[NSString stringWithFormat:@"https://level3.ssl.blizzard.com/tpr/configs/data/%@/%@/%@",[key substringToIndex:2],[key substringWithRange:NSMakeRange(2,2)],key];
        data=[self fetch:[NSURL URLWithString:fallbackUrl] limit:2*1024*1024 error:nil];
    }
    if(!data) {
        if(error && !*error) *error=TKWoWError(@"Failed to download product configuration.");
        return nil;
    }
    if(![TKWoWMD5(data) isEqual:key]) { if(error)*error=TKWoWError(@"Configuration checksum mismatch.");return nil; }
    return data;
}
- (NSData *)configuration:(NSString *)key cdn:(NSString *)cdn error:(NSError **)error {
    NSError *directError=nil;
    NSData *data=[self object:key kind:@"config" cdn:cdn limit:2*1024*1024 error:&directError];
    if(!data) {
        data=[self productConfiguration:key cdn:cdn error:nil];
    }
    if(!data) {
        if(error)*error=directError?:TKWoWError(@"Failed to download configuration.");
        return nil;
    }
    if(![TKWoWMD5(data) isEqual:key]) { if(error)*error=TKWoWError(@"Configuration checksum mismatch.");return nil; }
    return data;
}
static int CompareArchive(const void *a,const void *b) { return memcmp(a,b,16); }
- (BOOL)loadArchiveTable:(NSDictionary *)plan indices:(NSString *)directory error:(NSError **)error {
    NSString *key=plan[@"version"][@"CDNConfig"];
    if([_archiveConfig isEqual:key] && _archiveTable)return YES;
    NSData *raw=[self configuration:key cdn:plan[@"cdn"] error:error]; if(!raw)return NO;
    NSDictionary *config=TKWoWConfig(raw,error); if(!config)return NO;
    NSArray *archives=Words(config[@"archives"]);
    if(!archives.count || archives.count>20000) { if(error)*error=TKWoWError(@"Unsupported CDN archive list.");return NO; }
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error])return NO;
    NSMutableData *table=[NSMutableData new];
    NSError *failure=nil;
    @try {
    for(NSUInteger i=0;i<archives.count;i++) { @autoreleasepool {
        if(self.cancelled) { failure=TKWoWError(@"Download cancelled.");return NO; }
        NSString *archive=archives[i]; if(!TKWoWHashValid(archive)) { failure=TKWoWError(@"Invalid archive key.");return NO; }
        NSString *path=[directory stringByAppendingPathComponent:[archive stringByAppendingString:@".index"]];
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        NSData *index=nil, *entries=nil;
        if([attrs[NSFileSize] unsignedLongLongValue]<=64*1024*1024)index=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        if(index)entries=TKWoWArchiveEntries(index,(uint32_t)i,NULL);
        if(!entries) {
            NSString *url=[NSString stringWithFormat:@"%@/data/%@/%@/%@.index",plan[@"cdn"],[archive substringToIndex:2],[archive substringWithRange:NSMakeRange(2,2)],archive];
            index=[self fetch:[NSURL URLWithString:url] limit:64*1024*1024 error:&failure];
            if(!index)return NO; entries=TKWoWArchiveEntries(index,(uint32_t)i,&failure); if(!entries)return NO;
            if(![index writeToFile:path options:NSDataWritingAtomic error:&failure])return NO;
        }
        if(entries.length>256*1024*1024-table.length) { failure=TKWoWError(@"CDN archive table exceeds its memory budget.");return NO; }
        [table appendData:entries]; if(self.progress)self.progress(@"indices",i+1,archives.count);
    }}
    } @finally { if(failure && error)*error=failure; }
    qsort(table.mutableBytes,table.length/sizeof(TKWoWArchiveEntry),sizeof(TKWoWArchiveEntry),CompareArchive);
    _archives=archives;_archiveTable=table;_archiveConfig=key;return YES;
}
- (NSData *)encodedKey:(NSString *)key size:(uint64_t)size plan:(NSDictionary *)plan indices:(NSString *)indices error:(NSError **)error {
    if(!TKWoWHashValid(key) || size>256*1024*1024) { if(error)*error=TKWoWError(@"Invalid encoded object request.");return nil; }
    NSError *directError=nil;NSData *data=nil;BOOL triedDirect=NO;
    // Once the archive catalogue is known, avoid a failing standalone request
    // for every object that is already present in an archive.
    if(![_archiveConfig isEqual:plan[@"version"][@"CDNConfig"]] || !_archiveTable) {
        triedDirect=YES;
        data=[self object:key kind:@"data" cdn:plan[@"cdn"] limit:(NSUInteger)(size?:256*1024*1024) error:&directError];
        if(data && (!size || data.length==size) && TKWoWEncodedValid(data,key,&directError))return data;
    }
    if(self.cancelled) { if(error)*error=directError?:TKWoWError(@"Download cancelled.");return nil; }
    if(![self loadArchiveTable:plan indices:indices error:error])return nil;
    uint8_t hash[16];TKWoWUnhex(key,hash); const TKWoWArchiveEntry *entries=_archiveTable.bytes;
    NSUInteger lo=0,hi=_archiveTable.length/sizeof(*entries);
    while(lo<hi) { NSUInteger mid=lo+(hi-lo)/2; if(memcmp(entries[mid].key,hash,16)<0)lo=mid+1;else hi=mid; }
    if(lo==_archiveTable.length/sizeof(*entries) || memcmp(entries[lo].key,hash,16)) {
        if(!triedDirect) {
            data=[self object:key kind:@"data" cdn:plan[@"cdn"] limit:(NSUInteger)(size?:256*1024*1024) error:&directError];
            if(data && (!size || data.length==size) && TKWoWEncodedValid(data,key,&directError))return data;
        }
        if(error)*error=TKWoWError([NSString stringWithFormat:@"Object absent from CDN archives: %@ (%@)",key,directError.localizedDescription?:@"invalid object"]);return nil;
    }
    TKWoWArchiveEntry entry=entries[lo];
    if(size && entry.size!=size) { if(error)*error=TKWoWError(@"Archive size differs from the download manifest.");return nil; }
    NSString *archive=_archives[entry.archive];
    NSString *url=[NSString stringWithFormat:@"%@/data/%@/%@/%@",plan[@"cdn"], [archive substringToIndex:2],[archive substringWithRange:NSMakeRange(2,2)],archive];
    data=[self range:[NSURL URLWithString:url] offset:entry.offset size:entry.size error:error];
    if(!data || !TKWoWEncodedValid(data,key,error))return nil;return data;
}
static int CompareRanges(const void *a,const void *b) {
    const TKWoWArchiveEntry *x=a,*y=b;
    if(x->archive!=y->archive)return x->archive<y->archive?-1:1;
    return x->offset<y->offset?-1:x->offset>y->offset?1:0;
}
- (BOOL)downloadEntries:(NSData *)records plan:(NSDictionary *)plan indices:(NSString *)indices
    consume:(BOOL (^)(NSData *,NSString *,NSError **))consume error:(NSError **)error {
    if(records.length%sizeof(TKWoWDownloadEntry) || records.length>128*1024*1024) {
        if(error)*error=TKWoWError(@"Invalid download request list.");return NO;
    }
    if(!records.length)return YES;
    if(![self loadArchiveTable:plan indices:indices error:error])return NO;
    const TKWoWDownloadEntry *requested=records.bytes;NSUInteger count=records.length/sizeof(*requested);
    const TKWoWArchiveEntry *catalog=_archiveTable.bytes;NSUInteger catalogCount=_archiveTable.length/sizeof(*catalog);
    NSMutableData *ordered=[NSMutableData dataWithLength:count*sizeof(TKWoWArchiveEntry)];TKWoWArchiveEntry *entries=ordered.mutableBytes;
    for(NSUInteger i=0;i<count;i++) {
        NSUInteger lo=0,hi=catalogCount;
        while(lo<hi) { NSUInteger mid=lo+(hi-lo)/2;if(memcmp(catalog[mid].key,requested[i].key,16)<0)lo=mid+1;else hi=mid; }
        if(lo<catalogCount && !memcmp(catalog[lo].key,requested[i].key,16)) {
            if(catalog[lo].size!=requested[i].size) { if(error)*error=TKWoWError(@"Archive size differs from the download manifest.");return NO; }
            entries[i]=catalog[lo];
        } else {
            memcpy(entries[i].key,requested[i].key,16);entries[i].archive=UINT32_MAX;entries[i].size=(uint32_t)requested[i].size;
            if(!requested[i].size || requested[i].size>256*1024*1024) { if(error)*error=TKWoWError(@"Invalid download object size.");return NO; }
        }
    }
    qsort(entries,count,sizeof(*entries),CompareRanges);NSError *failure=nil;
    @try {
    for(NSUInteger i=0;i<count;) { @autoreleasepool {
        if(self.cancelled) { failure=TKWoWError(@"Download cancelled.");return NO; }
        TKWoWArchiveEntry first=entries[i];
        if(first.archive==UINT32_MAX) {
            NSString *key=TKWoWHex(first.key,16);
            NSData *raw=[self encodedKey:key size:first.size plan:plan indices:indices error:&failure];
            if(!raw || !consume(raw,key,&failure))return NO;i++;continue;
        }
        uint64_t end=(uint64_t)first.offset+first.size,payload=first.size;NSUInteger last=i+1;
        // Up to 16 MiB per grouped request. Small gaps are tolerated, with at
        // most 25% extra transfer plus 64 KiB. Large single objects stay bounded.
        while(last<count && entries[last].archive==first.archive) {
            uint64_t nextEnd=MAX(end,(uint64_t)entries[last].offset+entries[last].size);
            if(entries[last].offset>end+65536 || nextEnd-first.offset>16*1024*1024 ||
               nextEnd-first.offset>(payload+entries[last].size)*5/4+65536)break;
            end=nextEnd;payload+=entries[last].size;last++;
        }
        NSString *archive=_archives[first.archive];
        NSString *url=[NSString stringWithFormat:@"%@/data/%@/%@/%@",plan[@"cdn"],[archive substringToIndex:2],[archive substringWithRange:NSMakeRange(2,2)],archive];
        NSData *range=[self range:[NSURL URLWithString:url] offset:first.offset size:(NSUInteger)(end-first.offset) error:&failure];
        if(!range)return NO;
        for(NSUInteger j=i;j<last;j++) { @autoreleasepool {
            if(self.cancelled) { failure=TKWoWError(@"Download cancelled.");return NO; }
            NSString *key=TKWoWHex(entries[j].key,16);
            NSUInteger offset=entries[j].offset-first.offset;
            if(offset>range.length || entries[j].size>range.length-offset) { failure=TKWoWError(@"Truncated archive range.");return NO; }
            NSData *raw=[NSData dataWithBytesNoCopy:(uint8_t *)range.bytes+offset length:entries[j].size freeWhenDone:NO];
            if(!TKWoWEncodedValid(raw,key,&failure) || !consume(raw,key,&failure))return NO;
        }}
        i=last;
    }}
    } @finally { if(failure && error)*error=failure; }
    return YES;
}

@end
