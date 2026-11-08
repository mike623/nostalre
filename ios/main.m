// iOS entry: hand the process to the Rust client (winit runs UIApplicationMain itself).
// Before that, register a launch hook that floats a small switcher button over the game:
// Native (nostalRE) | roBrowser | OpenKore panel. The web views live above winit's view
// and stay alive while hidden, so switching never reloads or drops a session.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

extern void nostalre_ios_main(void);

static BOOL webShown; // game = landscape only; web tabs may rotate to portrait
static NSString *const kRoKey = @"url.robrowser", *const kKoreKey = @"url.openkore";
static NSString *const kLastKey = @"last.view"; // reopen where the user left off: home | native | a url key

@interface Switcher : NSObject <WKUIDelegate>
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, strong) UIButton *pill;
@property(nonatomic, strong) UIView *landing; // entry screen: pick game / roBrowser / OpenKore
@property(nonatomic, strong) NSMutableDictionary<NSString *, WKWebView *> *webs;
@property(nonatomic, strong) NSURL *pending; // deep link that arrived before winit's window
- (BOOL)openDeepLink:(NSURL *)url;
@end

@implementation Switcher

+ (instancetype)shared { static Switcher *s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [Switcher new]; s.webs = [NSMutableDictionary new]; }); return s; }

- (NSString *)urlFor:(NSString *)key {
    NSString *u = [NSUserDefaults.standardUserDefaults stringForKey:key];
    if (u.length) return u;
    return [key isEqualToString:kRoKey] ? @"https://ro.namike.me/" : @"https://kore.namike.me/";
}

- (void)attachTo:(UIWindow *)w {
    if (self.pill || !w) return;
    self.window = w;
    // winit's view controller decides orientation; make it follow which layer is on top.
    // class_replaceMethod touches only winit's subclass, not UIViewController itself.
    class_replaceMethod(object_getClass(w.rootViewController), @selector(supportedInterfaceOrientations),
        imp_implementationWithBlock(^UIInterfaceOrientationMask(id _) {
            return webShown ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskLandscape; }), "Q@:");
    [w.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:@"⇄" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    b.tintColor = UIColor.whiteColor;
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    b.layer.cornerRadius = 20;
    UIEdgeInsets safe = w.safeAreaInsets;
    // ponytail: fixed spawn spot top-right; drag it anywhere if it covers HUD.
    b.frame = CGRectMake(w.bounds.size.width - safe.right - 52, safe.top + 8, 40, 40);
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [b addTarget:self action:@selector(menu) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    // on the window: inside winit's view the game's render draws over it
    [w addSubview:b];
    self.pill = b;
    NSString *last = [NSUserDefaults.standardUserDefaults stringForKey:kLastKey];
    if ([last isEqualToString:@"home"]) [self home];
    else if ([last isEqualToString:@"native"]) [self show:nil];
    else [self show:[last isEqualToString:kRoKey] ? kRoKey : kKoreKey]; // OpenKore panel by default
    if (self.pending) { NSURL *u = self.pending; self.pending = nil; [self openDeepLink:u]; }
}

- (UIButton *)landingButton:(NSString *)title sub:(NSString *)sub action:(SEL)sel {
    UIButtonConfiguration *c = UIButtonConfiguration.filledButtonConfiguration;
    c.title = title;
    c.subtitle = sub;
    c.baseBackgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    c.baseForegroundColor = UIColor.whiteColor;
    c.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    c.contentInsets = NSDirectionalEdgeInsetsMake(16, 20, 16, 20);
    c.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *a) {
        NSMutableDictionary *m = a.mutableCopy; m[NSFontAttributeName] = [UIFont boldSystemFontOfSize:22]; return m; };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)pickNative { [self show:nil]; }
- (void)pickRo { [self show:kRoKey]; }
- (void)pickKore { [self show:kKoreKey]; }

// Landing screen over everything; the game keeps loading underneath meanwhile.
- (void)home {
    // on the window itself: inside winit's view the game's render covers it (no pickers here, so no VC needed)
    UIView *host = self.window;
    if (!self.landing) {
        UIView *l = [UIView new];
        l.translatesAutoresizingMaskIntoConstraints = NO; // host is still 0x0 at launch; pin to its edges
        l.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:1];
        UILabel *t = [UILabel new];
        t.text = @"Ragnarok Offline";
        t.font = [UIFont boldSystemFontOfSize:28];
        t.textColor = UIColor.whiteColor;
        t.textAlignment = NSTextAlignmentCenter;
        UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[t,
            [self landingButton:@"nostalRE" sub:@"Native client" action:@selector(pickNative)],
            [self landingButton:@"roBrowser" sub:@"Web client" action:@selector(pickRo)],
            [self landingButton:@"OpenKore" sub:@"Bot control panel" action:@selector(pickKore)]]];
        st.axis = UILayoutConstraintAxisVertical;
        st.spacing = 14;
        st.translatesAutoresizingMaskIntoConstraints = NO;
        [l addSubview:st];
        [NSLayoutConstraint activateConstraints:@[
            [st.centerXAnchor constraintEqualToAnchor:l.centerXAnchor],
            [st.centerYAnchor constraintEqualToAnchor:l.centerYAnchor],
            [st.widthAnchor constraintEqualToConstant:300]]];
        self.landing = l;
    }
    if (self.landing.superview != host) {
        [host addSubview:self.landing];
        [NSLayoutConstraint activateConstraints:@[
            [self.landing.topAnchor constraintEqualToAnchor:host.topAnchor],
            [self.landing.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
            [self.landing.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [self.landing.trailingAnchor constraintEqualToAnchor:host.trailingAnchor]]];
    }
    [host bringSubviewToFront:self.landing];
    [NSUserDefaults.standardUserDefaults setObject:@"home" forKey:kLastKey];
    self.landing.hidden = NO;
    self.pill.hidden = YES;
    webShown = YES; // landing may rotate either way
    [self.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.window];
    self.pill.center = CGPointMake(self.pill.center.x + d.x, self.pill.center.y + d.y);
    [g setTranslation:CGPointZero inView:self.window];
}

- (void)menu {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Home" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self home]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"nostalRE (native)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self show:nil]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"roBrowser" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self show:kRoKey]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OpenKore panel" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self show:kKoreKey]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reload current page" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self.visible reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Set roBrowser link…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self editURL:kRoKey]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Set OpenKore link (paste invite)…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self editURL:kKoreKey]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.pill; // iPad
    a.popoverPresentationController.sourceRect = self.pill.bounds;
    [self.top presentViewController:a animated:YES completion:nil];
}

- (UIViewController *)top {
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

- (WKWebView *)visible {
    for (WKWebView *v in self.webs.allValues) if (!v.hidden) return v;
    return nil;
}

- (WKWebView *)web:(NSString *)key {
    WKWebView *v = self.webs[key];
    if (v) return v;
    WKWebViewConfiguration *c = [WKWebViewConfiguration new];
    c.allowsInlineMediaPlayback = YES;
    c.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    c.websiteDataStore = WKWebsiteDataStore.defaultDataStore; // invite cookie + localStorage persist
    v = [[WKWebView alloc] initWithFrame:self.window.bounds configuration:c];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.backgroundColor = UIColor.blackColor;
    v.scrollView.bounces = NO;
    v.UIDelegate = self;
    v.inspectable = YES; // Safari Web Inspector from the Mac
    v.hidden = YES;
    [v loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[self urlFor:key]]]];
    // inside the root VC's view, not the window: WebKit presents <select>/file pickers from the owning VC
    UIView *host = self.window.rootViewController.view;
    v.frame = host.bounds;
    [host addSubview:v];
    self.webs[key] = v;
    return v;
}

// key nil = back to the native game underneath
- (void)show:(NSString *)key {
    WKWebView *target = key ? [self web:key] : nil;
    [NSUserDefaults.standardUserDefaults setObject:key ?: @"native" forKey:kLastKey];
    for (WKWebView *v in self.webs.allValues) v.hidden = (v != target);
    self.landing.hidden = YES;
    self.pill.hidden = NO;
    webShown = target != nil;
    [self.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
    // the panel is a phone-shaped page: turn to portrait on open (roBrowser follows the device)
    if ([key isEqualToString:kKoreKey])
        [self.window.windowScene requestGeometryUpdateWithPreferences:
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait]
            errorHandler:nil];
    if (target) [target.superview bringSubviewToFront:target];
    [self.window bringSubviewToFront:self.pill];
}

- (void)editURL:(NSString *)key {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Link" message:@"Full URL, e.g. https://kore.namike.me/#invite=…" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = [self urlFor:key]; f.keyboardType = UIKeyboardTypeURL; f.clearButtonMode = UITextFieldViewModeAlways; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSURL *u = [NSURL URLWithString:a.textFields.firstObject.text];
        if (!u.scheme) return;
        // keep the invite out of the saved default: the page trades it for a cookie on first load
        NSURLComponents *keep = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
        keep.fragment = nil;
        [NSUserDefaults.standardUserDefaults setObject:keep.URL.absoluteString forKey:key];
        [[self web:key] loadRequest:[NSURLRequest requestWithURL:u]];
        [self show:key];
    }]];
    [self.top presentViewController:a animated:YES completion:nil];
}

// window.open / target=_blank: load in place instead of silently dropping it
- (WKWebView *)webView:(WKWebView *)w createWebViewWithConfiguration:(WKWebViewConfiguration *)c forNavigationAction:(WKNavigationAction *)n windowFeatures:(WKWindowFeatures *)f {
    [w loadRequest:n.request];
    return nil;
}

- (void)webView:(WKWebView *)w runJavaScriptAlertPanelWithMessage:(NSString *)m initiatedByFrame:(WKFrameInfo *)fr completionHandler:(void (^)(void))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { done(); }]];
    [self.top presentViewController:a animated:YES completion:nil];
}

- (void)webView:(WKWebView *)w runJavaScriptConfirmPanelWithMessage:(NSString *)m initiatedByFrame:(WKFrameInfo *)fr completionHandler:(void (^)(BOOL))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *_) { done(NO); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { done(YES); }]];
    [self.top presentViewController:a animated:YES completion:nil];
}

// nostalre://kore#invite=X -> https://kore.namike.me/#invite=X (host "ro" -> roBrowser).
// Path/query/fragment ride along; the page trades the invite for a cookie on load.
- (BOOL)openDeepLink:(NSURL *)url {
    if (![url.scheme isEqualToString:@"nostalre"]) return NO;
    if (!self.pill) { self.pending = url; return YES; }
    NSString *key = [url.host isEqualToString:@"ro"] ? kRoKey : [url.host isEqualToString:@"kore"] ? kKoreKey : nil;
    if (!key) { [self show:nil]; return YES; } // nostalre://game or anything else -> native
    NSURLComponents *base = [NSURLComponents componentsWithString:[self urlFor:key]];
    NSURLComponents *in = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (in.path.length) base.path = in.path;
    base.query = in.query;
    base.fragment = in.fragment;
    [[self web:key] loadRequest:[NSURLRequest requestWithURL:base.URL]];
    [self show:key];
    return YES;
}

@end

// winit runs UIApplicationMain with no delegate on purpose, leaving room for this one.
@interface LinkDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation LinkDelegate
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)o { return [Switcher.shared openDeepLink:url]; }
@end

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        static LinkDelegate *delegate; // UIApplication.delegate is weak
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
            Switcher.shared.pending = n.userInfo[UIApplicationLaunchOptionsURLKey];
            delegate = [LinkDelegate new];
            UIApplication.sharedApplication.delegate = delegate;
        }];
        // winit makes its window key once it exists; float the switcher over it then.
        [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            [Switcher.shared attachTo:n.object];
        }];
    }
    nostalre_ios_main();
    return 0;
}
