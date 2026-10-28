#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import "AKSupport.h"
#include <stdatomic.h>
#include <dlfcn.h>
#include <os/lock.h>

#define AK_FPS_HISTORY_COUNT 60
static double s_fpsTimestamps[AK_FPS_HISTORY_COUNT];
static NSUInteger s_fpsHead = 0;
static NSUInteger s_fpsCount = 0;
static os_unfair_lock s_fpsLock = OS_UNFAIR_LOCK_INIT;
static double s_cachedFPS = 0.0;
static double s_lastFrameDurationMs = 0.0;
static double s_lastPresentedAt = 0.0;

void AKRecordMetalFramePresented(double timestamp) {
    if (timestamp <= 0.0) timestamp = CACurrentMediaTime();
    os_unfair_lock_lock(&s_fpsLock);
    if (s_lastPresentedAt > 0.0) {
        double dt = timestamp - s_lastPresentedAt;
        if (dt > 0.0) s_lastFrameDurationMs = dt * 1000.0;
    }
    s_lastPresentedAt = timestamp;
    s_fpsTimestamps[s_fpsHead] = timestamp;
    s_fpsHead = (s_fpsHead + 1) % AK_FPS_HISTORY_COUNT;
    if (s_fpsCount < AK_FPS_HISTORY_COUNT) s_fpsCount++;
    if (s_fpsCount >= 2) {
        NSUInteger oldestIdx = (s_fpsHead + AK_FPS_HISTORY_COUNT - s_fpsCount) % AK_FPS_HISTORY_COUNT;
        NSUInteger newestIdx = (s_fpsHead + AK_FPS_HISTORY_COUNT - 1) % AK_FPS_HISTORY_COUNT;
        double span = s_fpsTimestamps[newestIdx] - s_fpsTimestamps[oldestIdx];
        if (span > 0.001) {
            s_cachedFPS = (double)(s_fpsCount - 1) / span;
        }
    }
    os_unfair_lock_unlock(&s_fpsLock);
}

__attribute__((visibility("default"))) double AKMetalCurrentFPS(void) {
    os_unfair_lock_lock(&s_fpsLock);
    double fps = s_cachedFPS;
    double last = s_lastPresentedAt;
    os_unfair_lock_unlock(&s_fpsLock);
    if (last > 0.0 && (CACurrentMediaTime() - last) > 0.5) {
        return 0.0;
    }
    return fps;
}

__attribute__((visibility("default"))) double AKMetalLastFrameTimeMs(void) {
    os_unfair_lock_lock(&s_fpsLock);
    double ms = s_lastFrameDurationMs;
    os_unfair_lock_unlock(&s_fpsLock);
    return ms;
}

// Development-only presentation evidence. All normal execution stays native.
// The sample flag also saves one GPU readback after rendering, before present.
static id<CAMetalDrawable> (*originalNextDrawable)(id,SEL);
static void (*originalPresent)(id,SEL,id<MTLDrawable>);
static void (*originalPresentAt)(id,SEL,id<MTLDrawable>,CFTimeInterval);
static void (*originalPresentAfter)(id,SEL,id<MTLDrawable>,CFTimeInterval);
static void (*originalCommit)(id,SEL);
static atomic_uint_fast64_t obtained, presented;
static char captureMarker, captureTarget;
static char timingMarker;
static BOOL captureFrames, measureFrames;
@interface AKFrameTiming : NSObject
@property double start, previous, longest;
@property NSUInteger frames, slow;
- (void)presentedAt:(double)time;
@end
@implementation AKFrameTiming
- (void)presentedAt:(double)time {
    if(time<=0)return;
    @synchronized(self) {
        if(!_start) { _start=_previous=time; return; }
        if(time<=_previous)return;
        double gap=time-_previous; _previous=time; _frames++;
        _longest=MAX(_longest,gap); if(gap>.05)_slow++;
        double elapsed=time-_start;
        if(elapsed>=5) {
            AKLog(@"frame timing seconds=%.2f fps=%.1f max_gap_ms=%.1f gaps_over_50ms=%lu",elapsed,_frames/elapsed,_longest*1000,(unsigned long)_slow);
            _start=time; _frames=0; _slow=0; _longest=0;
        }
    }
}
@end
extern void AKInstallRenderDiagnostics(Class cls);
extern NSArray *AKRenderStatsForCommand(id command);
static id<CAMetalDrawable> observedNextDrawable(id layer, SEL selector) {
    // A framebuffer-only drawable cannot be copied for diagnostic readback.
    if(captureFrames) ((CAMetalLayer *)layer).framebufferOnly=NO;
    id<CAMetalDrawable> drawable=originalNextDrawable(layer,selector);
    if(drawable) {
        uint64_t count=atomic_fetch_add(&obtained,1)+1;
        if(count==1 || count==60 || count==600 || count==1800) AKLog(@"Metal drawable %llu acquired: %lux%lu format=%lu",(unsigned long long)count,(unsigned long)drawable.texture.width,(unsigned long)drawable.texture.height,(unsigned long)drawable.texture.pixelFormat);
        if(captureFrames && (count==60 || count==600 || count==1800)) { objc_setAssociatedObject(drawable,&captureMarker,@(count),OBJC_ASSOCIATION_RETAIN_NONATOMIC); CGRect r=((CALayer *)layer).frame; AKLog(@"drawable layer=%p super=%p frame=(%g,%g,%g,%g) hidden=%d",layer,((CALayer *)layer).superlayer,r.origin.x,r.origin.y,r.size.width,r.size.height,((CALayer *)layer).hidden); }
        AKFrameTiming *timing=nil;
        if(measureFrames) {
            @synchronized(layer) {
                timing=objc_getAssociatedObject(layer,&timingMarker);
                if(!timing) { timing=[AKFrameTiming new]; objc_setAssociatedObject(layer,&timingMarker,timing,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            }
        }
#if !TARGET_OS_SIMULATOR
        // Presentation timestamps are diagnostics; the simulator SDK lacks them.
        [drawable addPresentedHandler:^(id<MTLDrawable> frame) {
            AKRecordMetalFramePresented(frame.presentedTime);
            [timing presentedAt:frame.presentedTime];
            uint64_t count=atomic_fetch_add(&presented,1)+1;
            if(count==1 || count==60 || count==600 || count==1800) AKLog(@"Metal frame %llu presented at %.6f",(unsigned long long)count,frame.presentedTime);
        }];
#else
        AKRecordMetalFramePresented(CACurrentMediaTime());
        (void)presented;
        (void)timing;
#endif
    }
    return drawable;
}
static void markCapture(id command,id<MTLDrawable> drawable) {
    if(objc_getAssociatedObject(drawable,&captureMarker)) objc_setAssociatedObject(command,&captureTarget,drawable,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void observedPresent(id command,SEL selector,id<MTLDrawable> drawable) { markCapture(command,drawable); originalPresent(command,selector,drawable); }
static void observedPresentAt(id command,SEL selector,id<MTLDrawable> drawable,CFTimeInterval time) { markCapture(command,drawable); originalPresentAt(command,selector,drawable,time); }
static void observedPresentAfter(id command,SEL selector,id<MTLDrawable> drawable,CFTimeInterval time) { markCapture(command,drawable); originalPresentAfter(command,selector,drawable,time); }
static void observedCommit(id<MTLCommandBuffer> command,SEL selector) {
    id<CAMetalDrawable> drawable=objc_getAssociatedObject(command,&captureTarget);
    if(drawable) {
        NSNumber *captureNumber=objc_getAssociatedObject(drawable,&captureMarker);
        AKLog(@"Frame %@ render passes: %@",captureNumber,AKRenderStatsForCommand(command));
        objc_setAssociatedObject(drawable,&captureMarker,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        id<MTLTexture> texture=drawable.texture;
        NSUInteger width=texture.width,height=texture.height,stride=(width*4+255)&~255UL;
        MTLPixelFormat format=texture.pixelFormat;
        if(width && height && width<=16384 && height<=16384 && (format==MTLPixelFormatBGRA8Unorm || format==MTLPixelFormatBGRA8Unorm_sRGB)) {
            id<MTLBuffer> buffer=[command.device newBufferWithLength:stride*height options:MTLResourceStorageModeShared];
            if(buffer) {
                id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
                [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toBuffer:buffer destinationOffset:0 destinationBytesPerRow:stride destinationBytesPerImage:stride*height];
                [blit endEncoding];
                [command addCompletedHandler:^(id<MTLCommandBuffer> completed) { @autoreleasepool {
                    if(completed.status!=MTLCommandBufferStatusCompleted) { AKLog(@"Frame readback failed: %@",completed.error); return; }
                    NSData *pixels=[NSData dataWithBytes:buffer.contents length:stride*height];
                    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
                    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                    CGImageRef image=CGImageCreate(width,height,8,32,stride,space,kCGBitmapByteOrder32Little|(CGBitmapInfo)kCGImageAlphaPremultipliedFirst,provider,NULL,false,kCGRenderingIntentDefault);
                    NSURL *url=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/native-frame-%@.png",captureNumber]]];
                    CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL);
                    if(image && destination) { CGImageDestinationAddImage(destination,image,NULL); AKLog(@"GPU frame readback saved: %d",CGImageDestinationFinalize(destination)); }
                    if(destination) CFRelease(destination); if(image) CGImageRelease(image); CGColorSpaceRelease(space); CGDataProviderRelease(provider);
                } }];
            }
        }
        objc_setAssociatedObject(command,&captureTarget,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    originalCommit(command,selector);
}
static IMP replace(Class cls,SEL selector,IMP implementation) {
    Method method=class_getInstanceMethod(cls,selector); if(!method) return NULL;
    IMP original=method_getImplementation(method);
    class_replaceMethod(cls,selector,implementation,method_getTypeEncoding(method)); return original;
}
void AKInstallMetalPresentationDiagnostics(id<MTLDevice> device) {
    BOOL sample=[NSProcessInfo.processInfo.arguments containsObject:@"--sample-native"];
    BOOL measure=[NSProcessInfo.processInfo.arguments containsObject:@"--measure-native"];
    static dispatch_once_t once;
    dispatch_once(&once,^{
        captureFrames=sample; measureFrames=measure;
        originalNextDrawable=(void *)replace(CAMetalLayer.class,@selector(nextDrawable),(IMP)observedNextDrawable);
        // Timing observes presentation timestamps only. It never enables GPU
        // readback or changes framebuffer flags, even on authentication screens.
        if(!sample)return;
        id<MTLCommandQueue> queue=[device newCommandQueue]; id<MTLCommandBuffer> command=[queue commandBuffer]; Class cls=object_getClass(command);
        AKInstallRenderDiagnostics(cls);
        originalPresent=(void *)replace(cls,@selector(presentDrawable:),(IMP)observedPresent);
        originalPresentAt=(void *)replace(cls,@selector(presentDrawable:atTime:),(IMP)observedPresentAt);
        originalPresentAfter=(void *)replace(cls,@selector(presentDrawable:afterMinimumDuration:),(IMP)observedPresentAfter);
        originalCommit=(void *)replace(cls,@selector(commit),(IMP)observedCommit);
    });
}
