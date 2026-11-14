// CamFix - tweak pendamping 26Cam (Legacy) untuk iPhone 7 / iOS 15.
// Masalah: pada mode Foto/Square, 26Cam menaruh CAMPreviewView di y mutlak (-24)
// tanpa memperhitungkan posisi container-nya, sehingga preview terpotong.
// Perbaikan: untuk preview yang tingginya < 600pt (Foto 4:3, Square), ratakan bagian
// atas preview dengan bagian atas container-nya. Mode Video (layar penuh) tidak disentuh.
// Geser manual (opsional): key "extraY" di /var/mobile/Library/Preferences/com.hasan.camfix.plist

#import <UIKit/UIKit.h>

static BOOL gFixing = NO;

static CGFloat CFExtraY(void) {
    CGFloat r = 0;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("extraY"), CFSTR("com.hasan.camfix"));
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            double d = 0;
            CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d);
            r = (CGFloat)d;
        }
        CFRelease(v);
    }
    return r;
}

static UIView *CFContainerFor(UIView *pv) {
    for (UIView *v = pv.superview; v; v = v.superview) {
        if ([NSStringFromClass([v class]) containsString:@"PreviewContainer"]) return v;
    }
    return nil;
}

static BOOL CFTargetY(UIView *pv, CGFloat height, CGFloat *outY) {
    if (!pv.superview || height >= 600.0 || height < 50.0) return NO;
    UIView *c = CFContainerFor(pv);
    if (!c) return NO;
    CGPoint p = [pv.superview convertPoint:CGPointZero fromView:c];
    *outY = p.y + CFExtraY();
    return YES;
}

static void CFApply(UIView *pv) {
    if (gFixing || !pv) return;
    CGFloat y = 0;
    if (!CFTargetY(pv, pv.frame.size.height, &y)) return;
    CGRect f = pv.frame;
    if (fabs(f.origin.y - y) < 0.5) return;
    f.origin.y = y;
    gFixing = YES;
    pv.frame = f;
    gFixing = NO;
}

static UIView *CFFindPreview(UIView *root, int depth) {
    if (depth > 8) return nil;
    if ([NSStringFromClass([root class]) isEqualToString:@"CAMPreviewView"]) return root;
    for (UIView *s in root.subviews) {
        UIView *r = CFFindPreview(s, depth + 1);
        if (r) return r;
    }
    return nil;
}

%hook CAMPreviewView
- (void)setFrame:(CGRect)f {
    if (!gFixing) {
        CGFloat y = 0;
        if (CFTargetY((UIView *)self, f.size.height, &y)) f.origin.y = y;
    }
    %orig(f);
}
- (void)layoutSubviews {
    %orig;
    CFApply((UIView *)self);
}
%end

%hook CAMViewfinderViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    CFApply(CFFindPreview(vc.view, 0));
    __weak UIViewController *weakVC = vc;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *s = weakVC;
        if (s) CFApply(CFFindPreview(s.view, 0));
    });
}
%end
