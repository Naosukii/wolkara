#import "AKPerformanceOverlay.h"
#import <mach/mach.h>
#import <os/proc.h>
#import <dlfcn.h>

NSNotificationName const AKPerformanceOverlayDidChangeNotification = @"AKPerformanceOverlayDidChange";

typedef double (*AKMetalFPSFunc)(void);
typedef double (*AKMetalFrameTimeFunc)(void);

static double ReadMetalFPS(void) {
    static AKMetalFPSFunc func = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        func = (AKMetalFPSFunc)dlsym(RTLD_DEFAULT, "AKMetalCurrentFPS");
    });
    return func ? func() : 0.0;
}

static double ReadMetalFrameTimeMs(void) {
    static AKMetalFrameTimeFunc func = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        func = (AKMetalFrameTimeFunc)dlsym(RTLD_DEFAULT, "AKMetalLastFrameTimeMs");
    });
    return func ? func() : 0.0;
}

@implementation AKPerformanceOverlay {
    UIStackView *_compactStack;
    UIStackView *_expandedStack;
    UILabel *_fpsLabel;
    UIView *_thermalDot;
    UILabel *_thermalLabel;
    UILabel *_compactSeparator;
    UILabel *_batteryLabel;

    UILabel *_headerLabel;
    UILabel *_expandedFPSLabel;
    UILabel *_expandedThermalLabel;
    UILabel *_expandedMemoryLabel;
    UILabel *_expandedBatteryLabel;
    UILabel *_expandedPowerLabel;
    UILabel *_hintLabel;

    NSTimer *_pollTimer;
    CADisplayLink *_displayLink;
    CFTimeInterval _lastDisplayLinkTimestamp;
    double _displayLinkFPS;
    CGPoint _panStartCenter;
    BOOL _userRepositioned;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        self.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.88];
        self.layer.cornerRadius = 15;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.45;
        self.layer.shadowRadius = 8;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.clipsToBounds = YES;
        self.accessibilityIdentifier = @"wolkara.overlay.performance";
        self.isAccessibilityElement = YES;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;

        [self buildSubviews];
        [self setupGestures];

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(thermalStateChanged:)
            name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    }
    return self;
}

- (void)buildSubviews {
    // Compact pill views
    _fpsLabel = [UILabel new];
    _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    _fpsLabel.textColor = UIColor.whiteColor;
    _fpsLabel.text = @"-- FPS";

    _thermalDot = [UIView new];
    _thermalDot.layer.cornerRadius = 4;
    _thermalDot.backgroundColor = UIColor.systemGreenColor;
    _thermalDot.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_thermalDot.widthAnchor constraintEqualToConstant:8],
        [_thermalDot.heightAnchor constraintEqualToConstant:8],
    ]];

    _thermalLabel = [UILabel new];
    _thermalLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _thermalLabel.textColor = UIColor.whiteColor;
    _thermalLabel.text = @"Nominal";

    _compactSeparator = [UILabel new];
    _compactSeparator.font = [UIFont systemFontOfSize:12 weight:UIFontWeightLight];
    _compactSeparator.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    _compactSeparator.text = @"·";

    _batteryLabel = [UILabel new];
    _batteryLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _batteryLabel.textColor = UIColor.whiteColor;
    _batteryLabel.text = @"";

    _compactStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        _fpsLabel, _compactSeparator, _thermalDot, _thermalLabel, _batteryLabel
    ]];
    _compactStack.axis = UILayoutConstraintAxisHorizontal;
    _compactStack.alignment = UIStackViewAlignmentCenter;
    _compactStack.spacing = 6;
    _compactStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_compactStack];

    // Expanded card views
    _headerLabel = [UILabel new];
    _headerLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    _headerLabel.textColor = UIColor.systemCyanColor;
    _headerLabel.text = @"PERFORMANCE & THERMALS";

    _expandedFPSLabel = [self detailLabel];
    _expandedThermalLabel = [self detailLabel];
    _expandedMemoryLabel = [self detailLabel];
    _expandedBatteryLabel = [self detailLabel];
    _expandedPowerLabel = [self detailLabel];

    _hintLabel = [UILabel new];
    _hintLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    _hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _hintLabel.text = @"Tap to collapse · Drag to reposition";

    _expandedStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        _headerLabel,
        _expandedFPSLabel,
        _expandedThermalLabel,
        _expandedMemoryLabel,
        _expandedBatteryLabel,
        _expandedPowerLabel,
        _hintLabel
    ]];
    _expandedStack.axis = UILayoutConstraintAxisVertical;
    _expandedStack.alignment = UIStackViewAlignmentLeading;
    _expandedStack.spacing = 5;
    _expandedStack.translatesAutoresizingMaskIntoConstraints = NO;
    _expandedStack.hidden = YES;
    [self addSubview:_expandedStack];

    [NSLayoutConstraint activateConstraints:@[
        [_compactStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_compactStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_compactStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_expandedStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_expandedStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [_expandedStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [_expandedStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
    ]];
}

- (UILabel *)detailLabel {
    UILabel *label = [UILabel new];
    label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    label.textColor = UIColor.whiteColor;
    label.numberOfLines = 1;
    return label;
}

- (void)setupGestures {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    (void)tap;
    [self setExpanded:!self.isExpanded animated:YES];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (!self.superview) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        _panStartCenter = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.superview];
        CGPoint newCenter = CGPointMake(_panStartCenter.x + translation.x, _panStartCenter.y + translation.y);
        self.center = [self clampedCenterForProposedCenter:newCenter];
        _userRepositioned = YES;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [self savePosition];
    }
}

- (CGPoint)clampedCenterForProposedCenter:(CGPoint)proposed {
    if (!self.superview) return proposed;
    UIEdgeInsets insets = self.superview.safeAreaInsets;
    CGRect safe = UIEdgeInsetsInsetRect(self.superview.bounds, insets);
    CGFloat halfW = self.bounds.size.width / 2.0;
    CGFloat halfH = self.bounds.size.height / 2.0;
    CGFloat minX = safe.origin.x + halfW + 6;
    CGFloat maxX = CGRectGetMaxX(safe) - halfW - 6;
    CGFloat minY = safe.origin.y + halfH + 6;
    CGFloat maxY = CGRectGetMaxY(safe) - halfH - 6;
    if (minX > maxX) minX = maxX = CGRectGetMidX(safe);
    if (minY > maxY) minY = maxY = CGRectGetMidY(safe);
    return CGPointMake(MAX(minX, MIN(maxX, proposed.x)), MAX(minY, MIN(maxY, proposed.y)));
}

- (void)savePosition {
    if (!self.superview) return;
    UIEdgeInsets insets = self.superview.safeAreaInsets;
    CGRect safe = UIEdgeInsetsInsetRect(self.superview.bounds, insets);
    if (safe.size.width <= 0 || safe.size.height <= 0) return;
    CGFloat normX = (self.center.x - safe.origin.x) / safe.size.width;
    CGFloat normY = (self.center.y - safe.origin.y) / safe.size.height;
    [NSUserDefaults.standardUserDefaults setObject:@[@(normX), @(normY)] forKey:@"TKPerformanceOverlayPosition"];
}

- (void)restorePosition {
    if (!self.superview) return;
    UIEdgeInsets insets = self.superview.safeAreaInsets;
    CGRect safe = UIEdgeInsetsInsetRect(self.superview.bounds, insets);
    if (safe.size.width <= 0 || safe.size.height <= 0) return;

    NSArray *saved = [NSUserDefaults.standardUserDefaults objectForKey:@"TKPerformanceOverlayPosition"];
    if ([saved isKindOfClass:NSArray.class] && saved.count == 2) {
        CGFloat x = [saved[0] doubleValue] * safe.size.width + safe.origin.x;
        CGFloat y = [saved[1] doubleValue] * safe.size.height + safe.origin.y;
        self.center = [self clampedCenterForProposedCenter:CGPointMake(x, y)];
        _userRepositioned = YES;
        return;
    }

    // Default: upper right corner inside safe area
    CGFloat width = self.bounds.size.width > 0 ? self.bounds.size.width : 160;
    CGFloat height = self.bounds.size.height > 0 ? self.bounds.size.height : 30;
    CGFloat defX = CGRectGetMaxX(safe) - width / 2.0 - 12;
    CGFloat defY = safe.origin.y + height / 2.0 + 8;
    self.center = [self clampedCenterForProposedCenter:CGPointMake(defX, defY)];
}

- (void)setExpanded:(BOOL)expanded {
    [self setExpanded:expanded animated:NO];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (_expanded == expanded) return;
    _expanded = expanded;

    void (^changes)(void) = ^{
        self->_compactStack.hidden = expanded;
        self->_expandedStack.hidden = !expanded;
        self.layer.cornerRadius = expanded ? 16 : 15;
        [self updateMetrics];
        [self sizeToFit];
        self.center = [self clampedCenterForProposedCenter:self.center];
    };

    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0
            options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (CGSize)sizeThatFits:(CGSize)size {
    (void)size;
    if (_expanded) {
        CGSize stackSize = [_expandedStack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        return CGSizeMake(MAX(220, stackSize.width + 28), stackSize.height + 20);
    } else {
        CGSize stackSize = [_compactStack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        return CGSizeMake(stackSize.width + 24, 30);
    }
}

- (void)updateMetrics {
    double metalFPS = ReadMetalFPS();
    double frameTimeMs = ReadMetalFrameTimeMs();
    double fps = metalFPS > 0.0 ? metalFPS : _displayLinkFPS;
    if (frameTimeMs <= 0.0 && fps > 0.0) frameTimeMs = 1000.0 / fps;

    // Thermal State
    NSProcessInfoThermalState thermal = NSProcessInfo.processInfo.thermalState;
    NSString *thermalName = @"Nominal";
    NSString *thermalDetail = @"Normal load";
    UIColor *thermalColor = UIColor.systemGreenColor;
    switch (thermal) {
        case NSProcessInfoThermalStateNominal:
            thermalName = @"Nominal";
            thermalDetail = @"Cool";
            thermalColor = UIColor.systemGreenColor;
            break;
        case NSProcessInfoThermalStateFair:
            thermalName = @"Fair";
            thermalDetail = @"Warm";
            thermalColor = UIColor.systemYellowColor;
            break;
        case NSProcessInfoThermalStateSerious:
            thermalName = @"Serious";
            thermalDetail = @"Throttling active";
            thermalColor = UIColor.systemOrangeColor;
            break;
        case NSProcessInfoThermalStateCritical:
            thermalName = @"Critical";
            thermalDetail = @"Heavy throttle";
            thermalColor = UIColor.systemRedColor;
            break;
    }

    // Battery
    float battLevel = [UIDevice currentDevice].batteryLevel;
    UIDeviceBatteryState battState = [UIDevice currentDevice].batteryState;
    NSString *battString = @"";
    NSString *battExpanded = @"Battery: AC power";
    if (battLevel >= 0.0f) {
        int percent = (int)(battLevel * 100.0f + 0.5f);
        BOOL charging = (battState == UIDeviceBatteryStateCharging || battState == UIDeviceBatteryStateFull);
        battString = [NSString stringWithFormat:@"%d%%%@", percent, charging ? @" ⚡" : @""];
        battExpanded = [NSString stringWithFormat:@"Battery: %d%% (%@)", percent,
            charging ? @"Charging" : @"Unplugged"];
    }

    // Memory
    size_t availBytes = 0;
    if (&os_proc_available_memory != NULL) {
        availBytes = os_proc_available_memory();
    }
    size_t footprintBytes = 0;
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count) == KERN_SUCCESS) {
        footprintBytes = (size_t)vmInfo.phys_footprint;
    }
    double usedMB = (double)footprintBytes / (1024.0 * 1024.0);
    double freeMB = (double)availBytes / (1024.0 * 1024.0);

    BOOL lowPower = NSProcessInfo.processInfo.isLowPowerModeEnabled;

    // Apply to compact UI
    _fpsLabel.text = fps > 0.0 ? [NSString stringWithFormat:@"%.1f FPS", fps] : @"-- FPS";
    _thermalDot.backgroundColor = thermalColor;
    _thermalLabel.text = thermalName;
    _batteryLabel.text = battString;
    _compactSeparator.hidden = (battString.length == 0);

    // Apply to expanded UI
    _expandedFPSLabel.text = fps > 0.0
        ? [NSString stringWithFormat:@"Frame Rate: %.1f FPS (%.1f ms)", fps, frameTimeMs]
        : @"Frame Rate: Waiting for frames…";
    _expandedThermalLabel.text = [NSString stringWithFormat:@"Thermal State: %@ (%@)", thermalName, thermalDetail];
    _expandedMemoryLabel.text = [NSString stringWithFormat:@"RAM Footprint: %.0f MB · Free: %.0f MB", usedMB, freeMB];
    _expandedBatteryLabel.text = battExpanded;
    _expandedPowerLabel.text = [NSString stringWithFormat:@"Low Power Mode: %@", lowPower ? @"On" : @"Off"];

    self.accessibilityValue = [NSString stringWithFormat:@"%.1f FPS, Thermal %@", fps, thermalName];
}

- (void)displayLinkFired:(CADisplayLink *)link {
    if (_lastDisplayLinkTimestamp > 0.0) {
        CFTimeInterval delta = link.timestamp - _lastDisplayLinkTimestamp;
        if (delta > 0.001) {
            double current = 1.0 / delta;
            _displayLinkFPS = _displayLinkFPS > 0.0 ? (_displayLinkFPS * 0.9 + current * 0.1) : current;
        }
    }
    _lastDisplayLinkTimestamp = link.timestamp;
}

- (void)thermalStateChanged:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateMetrics];
    });
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && !self.hidden) {
        [self startMonitoring];
        [self sizeToFit];
        if (!_userRepositioned) [self restorePosition];
    } else {
        [self stopMonitoring];
    }
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if (hidden) {
        [self stopMonitoring];
    } else if (self.window) {
        [self startMonitoring];
        [self sizeToFit];
        if (!_userRepositioned) [self restorePosition];
    }
}

- (void)startMonitoring {
    if (!_pollTimer) {
        __weak AKPerformanceOverlay *weakSelf = self;
        _pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf updateMetrics];
        }];
    }
    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    [self updateMetrics];
}

- (void)stopMonitoring {
    [_pollTimer invalidate];
    _pollTimer = nil;
    [_displayLink invalidate];
    _displayLink = nil;
    _lastDisplayLinkTimestamp = 0.0;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopMonitoring];
}

@end
