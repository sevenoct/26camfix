// CamFix - tweak pendamping 26Cam (Legacy) untuk iPhone 7 / iOS 15.
// Masalah: pada mode Foto/Square, 26Cam menaruh CAMPreviewView di y mutlak (-24)
// tanpa memperhitungkan posisi container-nya, sehingga preview terpotong.
// Perbaikan: untuk preview yang tingginya < 600pt (Foto 4:3, Square), ratakan bagian
// atas preview dengan bagian atas container-nya. Mode Video (layar penuh) tidak disentuh.
// Pengaturan: Settings > CamFix (PhotoY / SquareY / Enabled).

#import <UIKit/UIKit.h>

static BOOL gFixing = NO;

static double CMXNum(CFStringRef key, double def) {
    double r = def;
    CFPropertyListRef v = CFPreferencesCopyAppValue(key, CFSTR("com.hasan.camfix"));
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &r);
        else if (CFGetTypeID(v) == CFBooleanGetTypeID()) r = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
        CFRelease(v);
    }
    return r;
}

// Foto (tinggi ~500) memakai PhotoY, Square (tinggi ~375) memakai SquareY.
static CGFloat CMXExtraY(CGFloat height) {
    return (CGFloat)(height > 440.0 ? CMXNum(CFSTR("PhotoY"), 0) : CMXNum(CFSTR("SquareY"), 0));
}

static UIView *CMXContainerFor(UIView *pv) {
    for (UIView *v = pv.superview; v; v = v.superview) {
        if ([NSStringFromClass([v class]) containsString:@"PreviewContainer"] ||
            [NSStringFromClass([v class]) containsString:@"MaskingView"]) return v;
    }
    return nil;
}

static BOOL CMXTargetY(UIView *pv, CGFloat height, CGFloat *outY) {
    if (CMXNum(CFSTR("Enabled"), 1) < 0.5) return NO;
    if (!pv.superview || height >= 600.0 || height < 50.0) return NO;
    UIView *c = CMXContainerFor(pv);
    if (!c) return NO;
    CGPoint p = [pv.superview convertPoint:CGPointZero fromView:c];
    *outY = p.y + CMXExtraY(height);
    return YES;
}

static void CMXApply(UIView *pv) {
    if (gFixing || !pv) return;
    CGFloat y = 0;
    if (!CMXTargetY(pv, pv.frame.size.height, &y)) return;
    CGRect f = pv.frame;
    if (fabs(f.origin.y - y) < 0.5) return;
    f.origin.y = y;
    gFixing = YES;
    pv.frame = f;
    gFixing = NO;
}

static UIView *CMXFindPreview(UIView *root, int depth) {
    if (depth > 8) return nil;
    NSString *n = NSStringFromClass([root class]);
    if ([n isEqualToString:@"CAMPreviewView"] ||
        ([n hasSuffix:@"PreviewView"] && ![n containsString:@"Video"] && ![n containsString:@"Container"])) return root;
    for (UIView *s in root.subviews) {
        UIView *r = CMXFindPreview(s, depth + 1);
        if (r) return r;
    }
    return nil;
}

%hook CAMPreviewView
- (void)setFrame:(CGRect)f {
    if (!gFixing) {
        CGFloat y = 0;
        if (CMXTargetY((UIView *)self, f.size.height, &y)) f.origin.y = y;
    }
    %orig(f);
}
- (void)layoutSubviews {
    %orig;
    CMXApply((UIView *)self);
}
%end

@interface CMXTicker : NSObject
@property (nonatomic, weak) UIViewController *vc;
@property (nonatomic, weak) UIView *pv;
@property (nonatomic, strong) CADisplayLink *link;
- (void)start;
- (void)stop;
@end

@implementation CMXTicker
- (void)tick {
    UIViewController *v = self.vc;
    if (!v || !v.viewIfLoaded.window) return;
    if (!self.pv || !self.pv.window) self.pv = CMXFindPreview(v.view, 0);
    CMXApply(self.pv);
}
- (void)start {
    if (self.link) return;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)stop {
    [self.link invalidate];
    self.link = nil;
}
@end

static CMXTicker *gTicker = nil;

%hook CAMViewfinderViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    CMXApply(CMXFindPreview(vc.view, 0));
    if (!gTicker) gTicker = [CMXTicker new];
    gTicker.vc = vc;
    [gTicker start];
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    if (!gTicker) gTicker = [CMXTicker new];
    gTicker.vc = vc;
    [gTicker start];
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [gTicker stop];
}
%end

static void CMXPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            UIView *pv = CMXFindPreview(w, 0);
            if (pv) { CMXApply(pv); [pv.superview setNeedsLayout]; }
        }
    });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CMXPrefsChanged,
        CFSTR("com.hasan.camfix/prefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
