// Delta FrameTrace 0.9 — read-only instrumentation for Roblox iOS / Delta 2.745.
// No FPS overrides, no engine patches. Counts callbacks and Metal API events,
// which DO NOT establish how many distinct images reached the physical display.
// This diagnostic is intended for an isolated LiveContainer tweak folder.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static _Atomic uint64_t gTicks, gDrawableOK, gDrawableNil;
static _Atomic uint64_t gCommits, gCompleted, gPresent, gPresentAt, gPresentAfter;
static _Atomic uint64_t gTotalTicks, gTotalDrawable, gTotalCommits, gTotalCompleted, gTotalPresent;
static id (*origNextDrawable)(id,SEL);
static void (*origTick)(id,SEL,id);
static void (*origCommit)(id,SEL);
static void (*origPresent)(id,SEL,id);
static void (*origPresentAt)(id,SEL,id,double);
static void (*origPresentAfter)(id,SEL,id,double);
static BOOL tickHooked=NO, nextHooked=NO, cbHooked=NO;

static id traceNextDrawable(id self,SEL cmd) {
    id drawable = origNextDrawable ? origNextDrawable(self,cmd) : nil;
    if(drawable) { atomic_fetch_add(&gDrawableOK,1); atomic_fetch_add(&gTotalDrawable,1); }
    else atomic_fetch_add(&gDrawableNil,1);
    return drawable;
}
static void traceTick(id self,SEL cmd,id link) {
    atomic_fetch_add(&gTicks,1);
    atomic_fetch_add(&gTotalTicks,1);
    if(origTick) origTick(self,cmd,link);
}
static void tracePresent(id self,SEL cmd,id drawable) {
    atomic_fetch_add(&gPresent,1);
    atomic_fetch_add(&gTotalPresent,1);
    if(origPresent) origPresent(self,cmd,drawable);
}
static void tracePresentAt(id self,SEL cmd,id drawable,double when) {
    atomic_fetch_add(&gPresentAt,1);
    atomic_fetch_add(&gTotalPresent,1);
    if(origPresentAt) origPresentAt(self,cmd,drawable,when);
}
static void tracePresentAfter(id self,SEL cmd,id drawable,double delay) {
    atomic_fetch_add(&gPresentAfter,1);
    atomic_fetch_add(&gTotalPresent,1);
    if(origPresentAfter) origPresentAfter(self,cmd,drawable,delay);
}
static void traceCommit(id self,SEL cmd) {
    atomic_fetch_add(&gCommits,1);
    atomic_fetch_add(&gTotalCommits,1);
    // Add a passive completion callback to count command buffers completed on GPU.
    // Does not count unique finished scene images.
    @try {
        [(id<MTLCommandBuffer>)self addCompletedHandler:^(id<MTLCommandBuffer> b) {
            (void)b;
            atomic_fetch_add(&gCompleted,1);
            atomic_fetch_add(&gTotalCompleted,1);
        }];
    } @catch(NSException *e) { (void)e; }
    if(origCommit) origCommit(self,cmd);
}
// Install override on the concrete class to avoid unexpectedly modifying a shared superclass.
static IMP traceSwizzle(Class cls,SEL sel,IMP replacement) {
    if(!cls || !sel) return NULL;
    Method m=class_getInstanceMethod(cls,sel);
    if(!m) return NULL;
    IMP previous=method_getImplementation(m);
    if(previous==replacement) return NULL;
    const char *types=method_getTypeEncoding(m);
    if(class_addMethod(cls,sel,replacement,types)) return previous;
    return method_setImplementation(m,replacement);
}
static void installHooks(void) {
    if(!nextHooked) {
        origNextDrawable=(id(*)(id,SEL))traceSwizzle([CAMetalLayer class],@selector(nextDrawable),(IMP)traceNextDrawable);
        nextHooked=(origNextDrawable!=NULL);
    }
    if(!tickHooked) {
        Class cls=NSClassFromString(@"AdaptiveSync");
        origTick=(void(*)(id,SEL,id))traceSwizzle(cls,NSSelectorFromString(@"displayLinkCallback:"),(IMP)traceTick);
        tickHooked=(origTick!=NULL);
    }
    if(!cbHooked) {
        id<MTLDevice> device=MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> queue=[device newCommandQueue];
        id<MTLCommandBuffer> cmd=[queue commandBuffer];
        Class cls=cmd?object_getClass(cmd):Nil;
        if(cls) {
            origCommit=(void(*)(id,SEL))traceSwizzle(cls,@selector(commit),(IMP)traceCommit);
            origPresent=(void(*)(id,SEL,id))traceSwizzle(cls,@selector(presentDrawable:),(IMP)tracePresent);
            origPresentAt=(void(*)(id,SEL,id,double))traceSwizzle(cls,@selector(presentDrawable:atTime:),(IMP)tracePresentAt);
            origPresentAfter=(void(*)(id,SEL,id,double))traceSwizzle(cls,@selector(presentDrawable:afterMinimumDuration:),(IMP)tracePresentAfter);
            cbHooked=(origCommit!=NULL);
        }
    }
}

@interface DeltaTracePanel : NSObject
@property (nonatomic,strong) UIView *panel;
@property (nonatomic,strong) UILabel *stats;
@property (nonatomic,strong) NSMutableArray<NSString *> *lines;
@property (nonatomic,assign) CFTimeInterval last;
@property (nonatomic,assign) CFTimeInterval begun;
@property (nonatomic,assign) BOOL compact;
@end
@implementation DeltaTracePanel
- (UIWindow *)findWindow {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for(UIWindow *w in ((UIWindowScene *)scene).windows) {
            if(w.isKeyWindow && !w.hidden) return w;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}
- (UIButton *)button:(NSString *)title x:(CGFloat)x target:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.frame=CGRectMake(x,52,106,28);
    b.backgroundColor=[UIColor colorWithRed:0.18 green:0.28 blue:0.40 alpha:0.95];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont boldSystemFontOfSize:12];
    b.layer.cornerRadius=7;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)mountIfNeeded {
    if(self.panel.superview) return;
    UIWindow *win=[self findWindow]; if(!win) return;
    // A very small overlay, attached only to the guest app's foreground window.
    UIView *v=[[UIView alloc] initWithFrame:CGRectMake(12,50,252,88)];
    v.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.84];
    v.layer.cornerRadius=11;
    v.layer.borderWidth=1;
    v.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.16].CGColor;
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(9,7,234,41)];
    label.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    label.numberOfLines=2;
    label.textColor=UIColor.whiteColor;
    label.text=@"Native FPS trace initializing...";
    [v addSubview:label];self.stats=label;
    [v addSubview:[self button:@"Copy report" x:9 target:@selector(copyReport)]];
    UIButton *min=[self button:@"Minimize" x:124 target:@selector(toggleCompact)];
    [v addSubview:min];
    [win addSubview:v];self.panel=v;
}
- (void)toggleCompact {
    self.compact=!self.compact;
    self.panel.frame=CGRectMake(self.panel.frame.origin.x,self.panel.frame.origin.y,252,self.compact?34:88);
    for(UIView *view in self.panel.subviews) if([view isKindOfClass:UIButton.class])view.hidden=self.compact;
    self.stats.frame=CGRectMake(9,4,234,self.compact?26:41);
}
- (void)copyReport {
    NSMutableArray *report=[NSMutableArray arrayWithObjects:
      @"DELTA NATIVE FRAME TRACE 0.9 — Roblox iOS", 
      @"Counts are API events, NOT proof of distinct GPU-rendered images or screen refresh rate.",
      [NSString stringWithFormat:@"Hooks: AdaptiveSync=%@ CAMetalLayer=%@ MTLCommandBuffer=%@",tickHooked?@"yes":@"no",nextHooked?@"yes":@"no",cbHooked?@"yes":@"no"],
      [NSString stringWithFormat:@"Totals: displayTick=%llu drawable=%llu commits=%llu GPU-completed=%llu presents=%llu",
      (unsigned long long)atomic_load(&gTotalTicks),(unsigned long long)atomic_load(&gTotalDrawable),
      (unsigned long long)atomic_load(&gTotalCommits),(unsigned long long)atomic_load(&gTotalCompleted),
      (unsigned long long)atomic_load(&gTotalPresent)],nil];
    [report addObjectsFromArray:self.lines];
    UIPasteboard.generalPasteboard.string=[report componentsJoinedByString:@"\n"];
    self.stats.text=@"Report copied! Paste it into ChatGPT.";
}
- (instancetype)init {
    if((self=[super init])) {
        self.lines=[NSMutableArray array];self.last=CACurrentMediaTime();self.begun=self.last;
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
    }
    return self;
}
- (void)onTimer:(NSTimer *)timer {
    (void)timer;
    installHooks();
    [self mountIfNeeded];
    CFTimeInterval now=CACurrentMediaTime();
    double elapsed=now-self.last;
    if(elapsed<=0) return;
    self.last=now;
    unsigned long long dt=atomic_exchange(&gTicks,0);
    unsigned long long drawable=atomic_exchange(&gDrawableOK,0);
    unsigned long long drawableNil=atomic_exchange(&gDrawableNil,0);
    unsigned long long commit=atomic_exchange(&gCommits,0);
    unsigned long long completed=atomic_exchange(&gCompleted,0);
    unsigned long long present=atomic_exchange(&gPresent,0);
    unsigned long long at=atomic_exchange(&gPresentAt,0);
    unsigned long long after=atomic_exchange(&gPresentAfter,0);
    NSString *line=[NSString stringWithFormat:@"t=%.1fs window=%.3fs | displayTick=%.1f/s drawable=%.1f/s nil=%llu | commit=%.1f/s complete=%.1f/s | present=%.1f/s timed=%.1f/s delayed=%.1f/s",
      now-self.begun,elapsed,dt/elapsed,drawable/elapsed,drawableNil,commit/elapsed,
      completed/elapsed,present/elapsed,at/elapsed,after/elapsed];
    [self.lines addObject:line];
    if(self.lines.count>180)[self.lines removeObjectAtIndex:0];
    if(self.stats && !self.compact)self.stats.text=[NSString stringWithFormat:@"Display %.0f / drawable %.0f / commit %.0f\nGPU done %.0f / present %.0f  (per sec)",dt/elapsed,drawable/elapsed,commit/elapsed,completed/elapsed,(present+at+after)/elapsed];
}
@end
static DeltaTracePanel *gPanel;
__attribute__((constructor)) static void startFrameTrace(void) {
    // Delay UIKit operations until main runloop has started.
    dispatch_async(dispatch_get_main_queue(),^{
       @autoreleasepool { gPanel=[DeltaTracePanel new]; }
    });
}

