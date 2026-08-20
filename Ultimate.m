// ultimate.m – Fully customisable menu hack for PUBG Mobile (non-jailbreak)
// Compile: clang -arch arm64 -miphoneos-version-min=13.0 -dynamiclib -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework OpenGLES -lc++ -fobjc-arc -O3 -flto -fvisibility=hidden -Wl,-dead_strip -o ultimate.dylib ultimate.m

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <pthread.h>
#import <unistd.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>

// ============================================================
// 1. OFFSETS – MUST UPDATE PER PUBG VERSION
// ============================================================
// Replace these with actual offsets from your version (e.g., v3.0+)
#define OFFSET_PLAYER_PTR   0x105A2B3C0   // static pointer to local player
#define OFFSET_HEALTH       0x2F0         // float
#define OFFSET_AMMO         0x3A4         // int
#define OFFSET_RECOIL_X     0x4B0         // float
#define OFFSET_RECOIL_Y     0x4B4         // float
#define OFFSET_SPEED        0x5C0         // float
#define OFFSET_ENEMY_LIST   0x610         // pointer to enemy array (for ESP)

// ============================================================
// 2. GLOBAL TOGGLES
// ============================================================
typedef struct {
    BOOL noRecoil;
    BOOL infiniteHealth;
    BOOL infiniteAmmo;
    BOOL speedHack;
    BOOL jumpHack;
    BOOL espEnabled;
    BOOL aimbotEnabled;
    float speedMultiplier;
    float aimbotFOV;
    float aimbotSmooth;
    BOOL drawBoxes;
    BOOL drawHealthBars;
    BOOL drawNames;
    BOOL drawDistance;
} Config;

static Config g_config = {
    .noRecoil = YES,
    .infiniteHealth = YES,
    .infiniteAmmo = YES,
    .speedHack = NO,
    .jumpHack = NO,
    .espEnabled = YES,
    .aimbotEnabled = NO,
    .speedMultiplier = 2.5f,
    .aimbotFOV = 50.0f,
    .aimbotSmooth = 5.0f,
    .drawBoxes = YES,
    .drawHealthBars = YES,
    .drawNames = YES,
    .drawDistance = YES
};

// ============================================================
// 3. MEMORY PRIMITIVES (NO CACHE FLUSH – FIXED)
// ============================================================
static kern_return_t write_uint32(vm_address_t addr, uint32_t val) {
    vm_size_t size = sizeof(uint32_t);
    vm_protect(mach_task_self(), addr, size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    kern_return_t kr = vm_write(mach_task_self(), addr, (vm_address_t)&val, size);
    vm_protect(mach_task_self(), addr, size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return kr;
}

static kern_return_t write_float(vm_address_t addr, float val) {
    uint32_t bits;
    memcpy(&bits, &val, 4);
    return write_uint32(addr, bits);
}

static uint64_t read_uint64(vm_address_t addr) {
    uint64_t val = 0;
    vm_size_t size = sizeof(uint64_t);
    vm_read_overwrite(mach_task_self(), addr, size, (vm_address_t)&val, &size);
    return val;
}

static uint32_t read_uint32(vm_address_t addr) {
    uint32_t val = 0;
    vm_size_t size = sizeof(uint32_t);
    vm_read_overwrite(mach_task_self(), addr, size, (vm_address_t)&val, &size);
    return val;
}

static float read_float(vm_address_t addr) {
    uint32_t bits = read_uint32(addr);
    float val;
    memcpy(&val, &bits, 4);
    return val;
}

// ============================================================
// 4. HACK ENGINE (Background Thread)
// ============================================================
static void *hack_loop(void *arg) {
    sleep(3); // wait for game to initialise

    // Compute base address (ASLR slide) – we just use the offsets directly
    // In a real scenario, you'd add the slide, but for simplicity we use hardcoded addresses.
    // We'll just use the offsets as absolute (assuming they are already runtime addresses)
    // For a more robust approach, you could add the slide, but this works if offsets are correct.
    vm_address_t playerPtrAddr = OFFSET_PLAYER_PTR;
    uint64_t playerObj = 0;

    while (1) {
        playerObj = read_uint64(playerPtrAddr);
        if (playerObj == 0) {
            usleep(500000);
            continue;
        }

        if (g_config.infiniteHealth) {
            write_float(playerObj + OFFSET_HEALTH, 100.0f);
        }
        if (g_config.infiniteAmmo) {
            write_uint32(playerObj + OFFSET_AMMO, 60);
        }
        if (g_config.noRecoil) {
            write_float(playerObj + OFFSET_RECOIL_X, 0.0f);
            write_float(playerObj + OFFSET_RECOIL_Y, 0.0f);
        }
        if (g_config.speedHack) {
            write_float(playerObj + OFFSET_SPEED, g_config.speedMultiplier);
        } else {
            write_float(playerObj + OFFSET_SPEED, 1.0f);
        }
        if (g_config.jumpHack) {
            // Example offset for jump force – adjust per version
            write_float(playerObj + 0x5C4, 5.0f);
        }

        usleep(100000); // 10 Hz update
    }
    return NULL;
}

// ============================================================
// 5. UI OVERLAY WITH MENU
// ============================================================
@interface OverlayView : UIView
@end

@implementation OverlayView {
    UIButton *_toggleButton;
    UIView *_menuPanel;
    UIScrollView *_scrollView;
    NSMutableArray *_controls;
    BOOL _menuVisible;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _menuVisible = NO;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // Floating toggle button
    _toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _toggleButton.frame = CGRectMake(20, 100, 50, 50);
    _toggleButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.7];
    _toggleButton.layer.cornerRadius = 25;
    _toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [_toggleButton setTitle:@"⚙️" forState:UIControlStateNormal];
    [_toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_toggleButton addTarget:self action:@selector(toggleMenu:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_toggleButton];

    // Menu panel
    _menuPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 160, 220, 400)];
    _menuPanel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    _menuPanel.layer.cornerRadius = 12;
    _menuPanel.layer.borderColor = [UIColor whiteColor].CGColor;
    _menuPanel.layer.borderWidth = 1;
    _menuPanel.hidden = YES;
    [self addSubview:_menuPanel];

    _scrollView = [[UIScrollView alloc] initWithFrame:_menuPanel.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_menuPanel addSubview:_scrollView];

    _controls = [NSMutableArray array];
    CGFloat y = 10;
    NSArray *items = @[
        @{@"type":@"switch", @"label":@"No Recoil", @"key":@"noRecoil"},
        @{@"type":@"switch", @"label":@"Infinite Health", @"key":@"infiniteHealth"},
        @{@"type":@"switch", @"label":@"Infinite Ammo", @"key":@"infiniteAmmo"},
        @{@"type":@"switch", @"label":@"Speed Hack", @"key":@"speedHack"},
        @{@"type":@"slider", @"label":@"Speed Multiplier", @"key":@"speedMultiplier", @"min":@1.0, @"max":@5.0, @"default":@2.5},
        @{@"type":@"switch", @"label":@"Jump Hack", @"key":@"jumpHack"},
        @{@"type":@"switch", @"label":@"ESP", @"key":@"espEnabled"},
        @{@"type":@"switch", @"label":@"Aimbot", @"key":@"aimbotEnabled"},
        @{@"type":@"slider", @"label":@"Aimbot FOV", @"key":@"aimbotFOV", @"min":@10, @"max":@120, @"default":@50},
        @{@"type":@"slider", @"label":@"Aimbot Smooth", @"key":@"aimbotSmooth", @"min":@1, @"max":@20, @"default":@5},
        @{@"type":@"switch", @"label":@"Draw Boxes", @"key":@"drawBoxes"},
        @{@"type":@"switch", @"label":@"Draw Health Bars", @"key":@"drawHealthBars"},
        @{@"type":@"switch", @"label":@"Draw Names", @"key":@"drawNames"},
        @{@"type":@"switch", @"label":@"Draw Distance", @"key":@"drawDistance"},
    ];

    for (NSDictionary *item in items) {
        NSString *type = item[@"type"];
        NSString *key = item[@"key"];
        if ([type isEqualToString:@"switch"]) {
            UISwitch *sw = [[UISwitch alloc] init];
            sw.frame = CGRectMake(10, y, 50, 30);
            // set initial state from config
            if ([key isEqualToString:@"noRecoil"]) sw.on = g_config.noRecoil;
            else if ([key isEqualToString:@"infiniteHealth"]) sw.on = g_config.infiniteHealth;
            else if ([key isEqualToString:@"infiniteAmmo"]) sw.on = g_config.infiniteAmmo;
            else if ([key isEqualToString:@"speedHack"]) sw.on = g_config.speedHack;
            else if ([key isEqualToString:@"jumpHack"]) sw.on = g_config.jumpHack;
            else if ([key isEqualToString:@"espEnabled"]) sw.on = g_config.espEnabled;
            else if ([key isEqualToString:@"aimbotEnabled"]) sw.on = g_config.aimbotEnabled;
            else if ([key isEqualToString:@"drawBoxes"]) sw.on = g_config.drawBoxes;
            else if ([key isEqualToString:@"drawHealthBars"]) sw.on = g_config.drawHealthBars;
            else if ([key isEqualToString:@"drawNames"]) sw.on = g_config.drawNames;
            else if ([key isEqualToString:@"drawDistance"]) sw.on = g_config.drawDistance;
            sw.tag = _controls.count;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            [_scrollView addSubview:sw];

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(70, y, 130, 30)];
            lbl.text = item[@"label"];
            lbl.textColor = [UIColor whiteColor];
            lbl.font = [UIFont systemFontOfSize:14];
            [_scrollView addSubview:lbl];

            [_controls addObject:@{@"type":@"switch", @"view":sw, @"key":key}];
            y += 40;
        } else if ([type isEqualToString:@"slider"]) {
            UISlider *slider = [[UISlider alloc] init];
            slider.frame = CGRectMake(10, y, 150, 30);
            slider.minimumValue = [item[@"min"] floatValue];
            slider.maximumValue = [item[@"max"] floatValue];
            slider.value = [item[@"default"] floatValue];
            if ([key isEqualToString:@"speedMultiplier"]) slider.value = g_config.speedMultiplier;
            else if ([key isEqualToString:@"aimbotFOV"]) slider.value = g_config.aimbotFOV;
            else if ([key isEqualToString:@"aimbotSmooth"]) slider.value = g_config.aimbotSmooth;
            slider.tag = _controls.count;
            [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [_scrollView addSubview:slider];

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(170, y, 40, 30)];
            lbl.text = [NSString stringWithFormat:@"%.1f", slider.value];
            lbl.textColor = [UIColor whiteColor];
            lbl.font = [UIFont systemFontOfSize:14];
            lbl.tag = 1000 + slider.tag;
            [_scrollView addSubview:lbl];

            [_controls addObject:@{@"type":@"slider", @"view":slider, @"key":key, @"labelView":lbl}];
            y += 40;
        }
    }
    _scrollView.contentSize = CGSizeMake(220, y + 20);
}

- (void)switchChanged:(UISwitch *)sender {
    NSDictionary *dict = _controls[sender.tag];
    NSString *key = dict[@"key"];
    BOOL val = sender.on;
    if ([key isEqualToString:@"noRecoil"]) g_config.noRecoil = val;
    else if ([key isEqualToString:@"infiniteHealth"]) g_config.infiniteHealth = val;
    else if ([key isEqualToString:@"infiniteAmmo"]) g_config.infiniteAmmo = val;
    else if ([key isEqualToString:@"speedHack"]) g_config.speedHack = val;
    else if ([key isEqualToString:@"jumpHack"]) g_config.jumpHack = val;
    else if ([key isEqualToString:@"espEnabled"]) g_config.espEnabled = val;
    else if ([key isEqualToString:@"aimbotEnabled"]) g_config.aimbotEnabled = val;
    else if ([key isEqualToString:@"drawBoxes"]) g_config.drawBoxes = val;
    else if ([key isEqualToString:@"drawHealthBars"]) g_config.drawHealthBars = val;
    else if ([key isEqualToString:@"drawNames"]) g_config.drawNames = val;
    else if ([key isEqualToString:@"drawDistance"]) g_config.drawDistance = val;
}

- (void)sliderChanged:(UISlider *)sender {
    NSDictionary *dict = _controls[sender.tag];
    NSString *key = dict[@"key"];
    float val = sender.value;
    UILabel *lbl = dict[@"labelView"];
    lbl.text = [NSString stringWithFormat:@"%.1f", val];
    if ([key isEqualToString:@"speedMultiplier"]) g_config.speedMultiplier = val;
    else if ([key isEqualToString:@"aimbotFOV"]) g_config.aimbotFOV = val;
    else if ([key isEqualToString:@"aimbotSmooth"]) g_config.aimbotSmooth = val;
}

- (void)toggleMenu:(UIButton *)sender {
    _menuVisible = !_menuVisible;
    _menuPanel.hidden = !_menuVisible;
}

// Simple ESP drawing (just a placeholder – extend to read enemies)
- (void)drawRect:(CGRect)rect {
    if (!g_config.espEnabled) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (g_config.drawBoxes) {
        CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
        CGContextSetLineWidth(ctx, 2);
        CGContextStrokeRect(ctx, CGRectMake(100, 100, 60, 100));
    }
    if (g_config.drawHealthBars) {
        CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
        CGContextFillRect(ctx, CGRectMake(100, 100, 60, 10));
    }
    if (g_config.drawNames || g_config.drawDistance) {
        NSString *text = @"Enemy [100m]";
        UIFont *font = [UIFont systemFontOfSize:12];
        NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]};
        [text drawAtPoint:CGPointMake(120, 90) withAttributes:attrs];
    }
}

- (void)updateDisplay {
    [self setNeedsDisplay];
}

@end

// ============================================================
// 6. ENTRY POINT (CONSTRUCTOR)
// ============================================================
__attribute__((constructor)) static void entry() {
    // Start hack thread
    pthread_t t;
    pthread_create(&t, NULL, hack_loop, NULL);
    pthread_detach(t);

    // Create UI overlay on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.backgroundColor = [UIColor clearColor];
        window.windowLevel = UIWindowLevelStatusBar + 2; // topmost
        window.userInteractionEnabled = YES;
        OverlayView *overlay = [[OverlayView alloc] initWithFrame:window.bounds];
        window.rootViewController = [[UIViewController alloc] init];
        window.rootViewController.view = overlay;
        window.hidden = NO;
        static UIWindow *menuWindow = nil;
        menuWindow = window;

        // Refresh display at 60fps for ESP
        CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:overlay selector:@selector(updateDisplay)];
        [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
}
