// CamFix - tweak pendamping 26Cam (Legacy) untuk iPhone 7 / iOS 15.
// Foto  : 4:3 = bawaan; 16:9 = preview memanjang sampai belakang shutter + bingkai atas/bawah transparan.
// Square: preview dibuat kotak 1:1 yang rata dengan bagian atas kotaknya (tidak terpotong).
// Video : tidak disentuh.
// Pengaturan: Settings > CamFix.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>

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

// Hitung frame yang seharusnya untuk preview. NO = jangan diubah.
// kind: 1 = Foto 16:9 (full-screen), 2 = Square
static BOOL CMXTargetRect(UIView *pv, CGRect f, CGRect *out, int *kind) {
    if (CMXNum(CFSTR("Enabled"), 1) < 0.5) return NO;
    if (!pv.superview) return NO;
    UIView *c = CMXContainerFor(pv);
    if (!c) return NO;
    CGFloat cw = c.bounds.size.width, ch = c.bounds.size.height;
    if (f.size.height < 50.0 || f.size.width < 50.0) return NO;
    CGPoint p = [pv.superview convertPoint:CGPointZero fromView:c];

    if (fabs(f.size.height - f.size.width) < 6.0) {
        if (CMXNum(CFSTR("SquareFix"), 1) < 0.5) return NO;
        *kind = 2;
        *out = CGRectMake(p.x, p.y, f.size.width, f.size.height);
        return YES;
    }
    if (f.size.height >= ch - 0.5) return NO;   // Video (layar penuh)
    if (CMXNum(CFSTR("PhotoAspect"), 1) < 0.5) return NO;   // 0 = 4:3 normal

    *kind = 1;
    *out = CGRectMake(p.x, p.y, cw, ch - 1.0);
    return YES;
}

// 26Cam memaksa y lewat setFrame, jadi untuk Square posisi digeser langsung di layer.
static void CMXShiftToContainerTop(UIView *pv) {
    UIView *c = CMXContainerFor(pv);
    if (!c || !pv.window) return;
    CGRect cw = [c convertRect:c.bounds toView:nil];
    CGRect pw = [pv convertRect:pv.bounds toView:nil];
    CGFloat dy = cw.origin.y - pw.origin.y;
    if (fabs(dy) < 0.5 || fabs(dy) > 800.0) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGPoint pos = pv.layer.position;
    pv.layer.position = CGPointMake(pos.x, pos.y + dy);
    [CATransaction commit];
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

static UIView *gDimTop = nil;
static UIView *gDimBot = nil;

static void CMXHideDims(void) {
    gDimTop.hidden = YES;
    gDimBot.hidden = YES;
}

static void CMXShowDims(UIView *pv) {
    UIView *c = CMXContainerFor(pv);
    UIView *vf = c.superview;
    if (!c || !vf) return;
    if (!gDimTop) {
        gDimTop = [[UIView alloc] init];
        gDimBot = [[UIView alloc] init];
        for (UIView *d in @[gDimTop, gDimBot]) {
            d.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];
            d.userInteractionEnabled = NO;
        }
    }
    for (UIView *d in @[gDimTop, gDimBot]) {
        if (d.superview != vf) [vf insertSubview:d aboveSubview:c];
        d.hidden = NO;
    }
    CGFloat w = vf.bounds.size.width, ch = c.bounds.size.height;
    CGFloat y0 = c.frame.origin.y;
    gDimTop.frame = CGRectMake(0, y0, w, ch * 0.15);
    gDimBot.frame = CGRectMake(0, y0 + ch * 0.76, w, ch * 0.24 + 2);
}

#pragma mark - Chromatic dispersion

static NSMutableSet<NSString *> *gDispNames = nil;

static BOOL CMXHasDisp(NSString *s) {
    return s && [s rangeOfString:@"ispersion" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL CMXPrimitiveEnc(const char *e) {
    if (!e || !e[0]) return NO;
    return strchr("BcCsSiIlLqQfd", e[0]) != NULL;
}

static void CMXKillDispersionObject(id obj) {
    Class cls = [obj class];
    while (cls && cls != [NSObject class] && cls != [UIView class] && cls != [CALayer class]) {
        unsigned n = 0;
        objc_property_t *props = class_copyPropertyList(cls, &n);
        for (unsigned i = 0; i < n; i++) {
            NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
            if (!CMXHasDisp(name)) continue;
            char *t = property_copyAttributeValue(props[i], "T");
            if (CMXPrimitiveEnc(t)) {
                @try { [obj setValue:@0 forKey:name]; [gDispNames addObject:[@"P:" stringByAppendingString:name]]; } @catch (id e) {}
            }
            if (t) free(t);
        }
        if (props) free(props);
        unsigned m = 0;
        Ivar *ivars = class_copyIvarList(cls, &m);
        for (unsigned i = 0; i < m; i++) {
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i])];
            if (!CMXHasDisp(name)) continue;
            if (CMXPrimitiveEnc(ivar_getTypeEncoding(ivars[i]))) {
                NSString *key = [name hasPrefix:@"_"] ? [name substringFromIndex:1] : name;
                @try { [obj setValue:@0 forKey:key]; [gDispNames addObject:[@"I:" stringByAppendingString:name]]; } @catch (id e) {}
            }
        }
        if (ivars) free(ivars);
        cls = class_getSuperclass(cls);
    }
}

static void CMXKillDispersionFilters(CALayer *l, int depth) {
    if (depth > 4) return;
    for (NSString *prop in @[@"filters", @"backgroundFilters"]) {
        NSArray *fs = nil;
        @try { fs = [l valueForKey:prop]; } @catch (id e) {}
        BOOL changed = NO;
        for (id f in fs) {
            if (![f respondsToSelector:@selector(inputKeys)]) continue;
            NSArray *keys = nil;
            @try { keys = [f performSelector:@selector(inputKeys)]; } @catch (id e) {}
            for (id k in keys) {
                if ([k isKindOfClass:[NSString class]] && CMXHasDisp(k)) {
                    @try { [f setValue:@0 forKey:k]; changed = YES; [gDispNames addObject:[@"F:" stringByAppendingString:k]]; } @catch (id e) {}
                }
            }
        }
        if (changed) { @try { [l setValue:fs forKey:prop]; } @catch (id e) {} }
    }
    if (CMXHasDisp(l.name)) { l.hidden = YES; [gDispNames addObject:[@"L:" stringByAppendingString:l.name]]; }
    for (CALayer *s in l.sublayers) CMXKillDispersionFilters(s, depth + 1);
}

static void CMXKillDispersionView(UIView *v, int depth) {
    if (depth > 14) return;
    NSString *cn = NSStringFromClass([v class]);
    if (CMXHasDisp(cn)) { v.hidden = YES; [gDispNames addObject:[@"V:" stringByAppendingString:cn]]; }
    BOOL glass = [cn hasPrefix:@"LG"] || [cn containsString:@"Glass"] || [cn containsString:@"Liquid"] ||
                 [cn hasPrefix:@"CAM26"] || [cn containsString:@"Backdrop"];
    if (glass) {
        CMXKillDispersionObject(v);
        CMXKillDispersionFilters(v.layer, 0);
    }
    for (UIView *s in v.subviews) CMXKillDispersionView(s, depth + 1);
}

static void CMXScanDispersion(void) {
    if (!gDispNames) gDispNames = [NSMutableSet set];
    for (UIWindow *w in UIApplication.sharedApplication.windows) CMXKillDispersionView(w, 0);
}

static void CMXApply(UIView *pv) {
    if (gFixing || !pv) return;
    CGRect f = pv.frame;
    CGRect t = CGRectZero;
    int kind = 0;
    if (!CMXTargetRect(pv, f, &t, &kind)) { CMXHideDims(); return; }
    gFixing = YES;
    if (kind == 1) {
        if (fabs(f.origin.x - t.origin.x) > 0.5 ||
            fabs(f.size.width - t.size.width) > 0.5 || fabs(f.size.height - t.size.height) > 0.5) {
            if (!CMXSizeNear(f.size, t.size)) gStale = f.size;
            pv.frame = t;
        }
        if (gStale.width > 0 && !CMXSizeNear(gStale, pv.bounds.size)) {
            CMXFit(pv, gStale, pv.bounds.size, 0);
        }
        CMXShiftToContainerTop(pv);
        if (CMXNum(CFSTR("Translucent"), 1) > 0.5) CMXShowDims(pv); else CMXHideDims();
    } else if (kind == 2) {
        CMXShiftToContainerTop(pv);
        CMXHideDims();
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
        int kind = 0;
        if (CMXTargetRect((UIView *)self, f, &t, &kind) && kind == 1) {
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
@property (nonatomic, assign) NSUInteger frames;
- (void)start;
- (void)stop;
@end

@implementation CMXTicker
- (void)tick {
    UIViewController *v = self.vc;
    if (!v || !v.viewIfLoaded.window) return;
    if (!self.pv || !self.pv.window) self.pv = CMXFindPreview(v.view, 0);
    CMXApply(self.pv);

    self.frames++;
    if (CMXNum(CFSTR("NoDispersion"), 1) > 0.5 && (self.frames % 20) == 1) CMXScanDispersion();

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
        NSString *disp = gDispNames.count ? [[gDispNames allObjects] componentsJoinedByString:@","] : @"-";
        self.dbg.numberOfLines = 3;
        self.dbg.text = [NSString stringWithFormat:@" CamFix win=(%.0f,%.0f %.0fx%.0f) disp:%@ ", r.origin.x, r.origin.y, r.size.width, r.size.height, disp];
        self.dbg.frame = CGRectMake(4, 24, 330, 36);
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
