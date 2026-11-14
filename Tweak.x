// CamFix - tweak pendamping 26Cam (Legacy) untuk iPhone 7 / iOS 15.
// Foto  : preview dibuat memanjang sampai ke belakang tombol shutter (seperti mode Video).
// Square: preview dibuat kotak 1:1 yang rata dengan bagian atas kotaknya (tidak terpotong).
// Video : tidak disentuh.
// Pengaturan: Settings > CamFix.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface CAMPreviewView : UIView
@end

@interface CAMViewfinderViewController : UIViewController
@end

static BOOL gFixing = NO;
static CGSize gStale = {0, 0};

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

static UIView *CMXContainerFor(UIView *pv) {
    for (UIView *v = pv.superview; v; v = v.superview) {
        NSString *n = NSStringFromClass([v class]);
        if ([n containsString:@"PreviewContainer"] || [n containsString:@"MaskingView"]) return v;
    }
    return nil;
}

// Hitung frame yang seharusnya untuk preview. NO = jangan diubah (Video, atau dimatikan).
static BOOL CMXTargetRect(UIView *pv, CGRect f, CGRect *out) {
    if (CMXNum(CFSTR("Enabled"), 1) < 0.5) return NO;
    if (!pv.superview) return NO;
    UIView *c = CMXContainerFor(pv);
    if (!c) return NO;
    CGFloat cw = c.bounds.size.width, ch = c.bounds.size.height;
    if (f.size.height < 50.0 || f.size.width < 50.0) return NO;
    CGPoint p = [pv.superview convertPoint:CGPointZero fromView:c];

    if (fabs(f.size.height - f.size.width) < 6.0) {
        // Square (1:1)
        *out = CGRectMake(p.x, p.y + (CGFloat)CMXNum(CFSTR("SquareY"), 0), f.size.width, f.size.height);
        return YES;
    }
    if (f.size.height >= ch - 5.0) return NO;   // Video (layar penuh)

    // Foto
    CGFloat y = p.y + (CGFloat)CMXNum(CFSTR("PhotoY"), 0);
    if (CMXNum(CFSTR("PhotoFull"), 1) > 0.5) {
        CGFloat bottom = (CGFloat)CMXNum(CFSTR("PhotoBottom"), 40);
        CGFloat h = ch - bottom - (y - p.y);
        if (h < f.size.height) h = f.size.height;
        *out = CGRectMake(p.x, y, cw, h);
    } else {
        *out = CGRectMake(p.x, y, f.size.width, f.size.height);
    }
    return YES;
}

static BOOL CMXSizeNear(CGSize a, CGSize b) {
    return fabs(a.width - b.width) < 1.5 && fabs(a.height - b.height) < 1.5;
}

// Anak-anak preview yang masih berukuran lama ikut disesuaikan.
static void CMXFit(UIView *v, CGSize stale, CGSize now, int depth) {
    if (depth > 5) return;
    for (CALayer *l in v.layer.sublayers) {
        if (CMXSizeNear(l.bounds.size, stale)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            l.frame = CGRectMake(l.frame.origin.x, l.frame.origin.y, now.width, now.height);
            [CATransaction commit];
        }
    }
    for (UIView *s in v.subviews) {
        if (CMXSizeNear(s.bounds.size, stale)) {
            s.frame = CGRectMake(s.frame.origin.x, s.frame.origin.y, now.width, now.height);
        }
        CMXFit(s, stale, now, depth + 1);
    }
}

static void CMXApply(UIView *pv) {
    if (gFixing || !pv) return;
    CGRect f = pv.frame;
    CGRect t = CGRectZero;
    if (!CMXTargetRect(pv, f, &t)) return;
    gFixing = YES;
    if (fabs(f.origin.y - t.origin.y) > 0.5 || fabs(f.origin.x - t.origin.x) > 0.5 ||
        fabs(f.size.width - t.size.width) > 0.5 || fabs(f.size.height - t.size.height) > 0.5) {
        if (!CMXSizeNear(f.size, t.size)) gStale = f.size;
        pv.frame = t;
    }
    if (gStale.width > 0 && !CMXSizeNear(gStale, pv.bounds.size)) {
        CMXFit(pv, gStale, pv.bounds.size, 0);
    }
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
        CGRect t = CGRectZero;
        if (CMXTargetRect((UIView *)self, f, &t)) {
            if (!CMXSizeNear(f.size, t.size)) gStale = f.size;
            f = t;
        }
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
@property (nonatomic, strong) UILabel *dbg;
- (void)start;
- (void)stop;
@end

@implementation CMXTicker
- (void)tick {
    UIViewController *v = self.vc;
    if (!v || !v.viewIfLoaded.window) return;
    if (!self.pv || !self.pv.window) self.pv = CMXFindPreview(v.view, 0);
    CMXApply(self.pv);

    UIWindow *w = v.viewIfLoaded.window;
    if (CMXNum(CFSTR("Debug"), 0) > 0.5 && self.pv) {
        if (!self.dbg) {
            self.dbg = [[UILabel alloc] init];
            self.dbg.font = [UIFont systemFontOfSize:9];
            self.dbg.textColor = [UIColor greenColor];
            self.dbg.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
            self.dbg.userInteractionEnabled = NO;
        }
        if (self.dbg.superview != w) [w addSubview:self.dbg];
        CGRect r = [self.pv convertRect:self.pv.bounds toView:nil];
        self.dbg.text = [NSString stringWithFormat:@" CamFix preview win=(%.0f,%.0f %.0fx%.0f) ", r.origin.x, r.origin.y, r.size.width, r.size.height];
        self.dbg.frame = CGRectMake(4, 24, 260, 14);
        [w bringSubviewToFront:self.dbg];
    } else if (self.dbg) {
        [self.dbg removeFromSuperview];
    }
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
