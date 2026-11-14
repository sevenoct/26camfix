// CamFull - pendamping 26Cam (Legacy), khusus iPhone 7 / iOS 15 (layar 375x667).
// Dasar: hasil dump hierarki view (CAMPreviewView berada di dalam ...MaskingView).
//  - Foto : PreviewView 375x500 y=-24  -> diisi penuh 375x667 (di belakang shutter) = tampilan 16:9
//  - Video: PreviewView 375x667 y=-40  -> diisi penuh (hilangkan strip hitam bawah)
//  - Square: PreviewView y=-24 menggeser gambar keluar kotak -> dirapatkan ke kotak square
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static BOOL gEnabled = YES, gFullPhoto = YES, gFullVideo = YES, gFixSquare = YES, gDebug = YES, gAspectHook = NO;
static CGFloat gPhotoY = 0;
static __weak UIView *gPV;
static CGRect gReq;            // frame terakhir yang diminta oleh Kamera/26Cam
static BOOL gReqValid, gInternal;
static NSString *gMode = @"-";
static UILabel *gLabel;

#pragma mark - Pengaturan

static void CFullLoad(void) {
    CFStringRef dom = CFSTR("com.hasan.camfull");
    CFPreferencesAppSynchronize(dom);
    id (^get)(NSString *) = ^id(NSString *k) { return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)k, dom); };
    BOOL (^b)(NSString *, BOOL) = ^BOOL(NSString *k, BOOL d) { id v = get(k); return [v isKindOfClass:NSNumber.class] ? [v boolValue] : d; };
    gEnabled = b(@"Enabled", YES);
    gFullPhoto = b(@"FullPhoto", YES);
    gFullVideo = b(@"FullVideo", YES);
    gFixSquare = b(@"FixSquare", YES);
    gAspectHook = b(@"AspectHook", NO);
    gDebug = b(@"Debug", YES);
    id y = get(@"PhotoY");
    gPhotoY = [y isKindOfClass:NSNumber.class] ? [y doubleValue] : 0;
}

#pragma mark - Logika frame

static UIView *CFullMask(UIView *pv) {
    for (UIView *v = pv.superview; v; v = v.superview)
        if ([NSStringFromClass(v.class) containsString:@"MaskingView"]) return v;
    return nil;
}

static CGRect CFullTarget(UIView *pv, CGRect cur) {
    if (!gEnabled) return cur;
    UIView *m = CFullMask(pv), *par = pv.superview;
    if (!m || !par) return cur;
    CGRect mr = [par convertRect:m.bounds fromView:m];
    CGFloat w = mr.size.width, h = mr.size.height;
    if (w < 1) return cur;
    if (fabs(w - h) < 2) {                       // Square
        gMode = @"square";
        return gFixSquare ? mr : cur;
    }
    if (fabs(cur.size.height - cur.size.width * 4.0 / 3.0) < 3) {   // Foto 4:3
        gMode = gFullPhoto ? @"photo-full" : @"photo-4:3";
        if (gFullPhoto) return mr;
        return CGRectMake(mr.origin.x, mr.origin.y + gPhotoY, cur.size.width, cur.size.height);
    }
    if (cur.size.height >= h - 2) {              // Video / layar penuh
        gMode = gFullVideo ? @"video-full" : @"video";
        return gFullVideo ? mr : cur;
    }
    gMode = @"other";
    return cur;
}

static void CFullEnforce(UIView *pv) {
    if (!pv || !pv.superview) return;
    CGRect cur = gReqValid ? gReq : pv.frame;
    CGRect t = CFullTarget(pv, cur);
    if (!CGRectEqualToRect(pv.frame, t)) {
        gInternal = YES;
        pv.frame = t;
        gInternal = NO;
    }
}

#pragma mark - Debug label + display link (penegak tiap frame)

@interface CFullTicker : NSObject
+ (void)start;
@end
@implementation CFullTicker
+ (void)start {
    static CADisplayLink *dl; static CFullTicker *t;
    if (dl) return;
    t = [CFullTicker new];
    dl = [CADisplayLink displayLinkWithTarget:t selector:@selector(tick)];
    [dl addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)tick {
    static int n;
    UIView *pv = gPV;
    if (!pv) return;
    CFullEnforce(pv);
    if (!gDebug) { [gLabel removeFromSuperview]; gLabel = nil; return; }
    if (++n % 20) return;
    UIWindow *w = pv.window;
    if (!w) return;
    if (!gLabel) {
        gLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 40, w.bounds.size.width - 12, 34)];
        gLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        gLabel.textColor = UIColor.greenColor;
        gLabel.numberOfLines = 3;
        gLabel.userInteractionEnabled = NO;
    }
    if (gLabel.superview != w) [w addSubview:gLabel];
    [w bringSubviewToFront:gLabel];
    UIView *m = CFullMask(pv);
    gLabel.text = [NSString stringWithFormat:@"CamFull 0.1 | mode:%@\npv:%@\nmask:%@", gMode,
        NSStringFromCGRect([pv.superview convertRect:pv.frame toView:nil]),
        m ? NSStringFromCGRect([m.superview convertRect:m.frame toView:nil]) : @"-"];
}
@end

#pragma mark - Hook

%hook CAMPreviewView
- (void)didMoveToWindow {
    %orig;
    gPV = (UIView *)self;
    [CFullTicker start];
}
- (void)setFrame:(CGRect)f {
    if (gInternal) { %orig; return; }
    gReq = f; gReqValid = YES;
    gPV = (UIView *)self;
    UIView *pv = (UIView *)self;
    %orig(pv.superview ? CFullTarget(pv, f) : f);
}
- (void)layoutSubviews {
    %orig;
    CFullEnforce((UIView *)self);
}
%end

// Opsional: tombol ASPECT di sheet pengaturan 26Cam berganti 4:3 <-> 16:9 (layar penuh)
static void CFullSetAspectLabel(UIView *btn, NSString *text) {
    if ([btn isKindOfClass:UILabel.class]) {
        UILabel *l = (UILabel *)btn;
        if ([l.text containsString:@":"]) l.text = text;
    }
    for (UIView *s in btn.subviews) CFullSetAspectLabel(s, text);
}

%hook CAM26SettingsSheet
- (void)aspectTapped {
    if (!gAspectHook) { %orig; return; }
    gFullPhoto = !gFullPhoto;
    @try { CFullSetAspectLabel([(id)self valueForKey:@"aspectBtn"], gFullPhoto ? @"16:9" : @"4:3"); } @catch (id e) {}
    CFullEnforce(gPV);
}
%end

static void CFullPrefs(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{ CFullLoad(); CFullEnforce(gPV); });
}

%ctor {
    @autoreleasepool {
        CFullLoad();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CFullPrefs,
            CFSTR("com.hasan.camfull/prefs"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
}
