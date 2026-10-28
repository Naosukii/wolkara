#import "TouchGamepad.h"
#import "TouchGamepadLayout.h"
#import "TouchHaptics.h"
#include <math.h>

CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size) {
    if (!isfinite(point.x) || !isfinite(point.y) || !isfinite(size.width) || !isfinite(size.height) ||
        size.width <= 0 || size.height <= 0) return CGPointZero;
    CGFloat radius = MIN(size.width,size.height) / 2;
    CGFloat x = (point.x - size.width / 2) / radius, y = (size.height / 2 - point.y) / radius;
    CGFloat length = hypot(x,y);
    if (!isfinite(x) || !isfinite(y) || !isfinite(length)) return CGPointZero;
    if (length < 0.10) return CGPointZero;
    CGFloat scale = MIN(1,(length - 0.10) / 0.90) / length;
    return CGPointMake(x * scale,y * scale);
}

@interface AKGamepadButton : UIButton
@property(nonatomic, copy) NSString *element;
@property(nonatomic, readonly) BOOL pressed;
@property(nonatomic) NSInteger sector;
- (void)releaseInput;
@end
@implementation AKGamepadButton { CAShapeLayer *_sectorLayer; UIBezierPath *_sectorPath; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _sector = -1;
        self.exclusiveTouch = NO;
        self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.layer.cornerRadius = 22; self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
        self.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.64];
        [self setTitleColor:[UIColor colorWithWhite:1 alpha:0.95] forState:UIControlStateNormal];
        [self addTarget:self action:@selector(pressInput) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(releaseInput) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
    }
    return self;
}
- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    UIColor *color = pressed ? [UIColor colorWithRed:0.1 green:0.55 blue:0.65 alpha:0.8] : [UIColor colorWithWhite:0.13 alpha:0.64];
    if (_sector >= 0) _sectorLayer.fillColor = color.CGColor; else self.backgroundColor = color;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)setSector:(NSInteger)sector {
    _sector = sector; self.backgroundColor = UIColor.clearColor; self.layer.borderWidth = 0;
    if (!_sectorLayer) { _sectorLayer = [CAShapeLayer layer]; [self.layer insertSublayer:_sectorLayer atIndex:0]; }
    _sectorLayer.fillColor = [UIColor colorWithWhite:0.13 alpha:0.64].CGColor;
    _sectorLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor; _sectorLayer.lineWidth = 1;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews]; if (_sector < 0) return;
    CGPoint center = CGPointMake(self.bounds.size.width/2,self.bounds.size.height/2);
    CGFloat angle = (_sector - 1) * M_PI_2, start = angle - M_PI_4 + 0.045, end = angle + M_PI_4 - 0.045;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path addArcWithCenter:center radius:104 startAngle:start endAngle:end clockwise:YES];
    [path addArcWithCenter:center radius:60 startAngle:end endAngle:start clockwise:NO]; [path closePath];
    _sectorPath = path; _sectorLayer.frame = self.bounds; _sectorLayer.path = path.CGPath;
    self.titleLabel.frame = CGRectMake(center.x+82*cos(angle)-26,center.y+82*sin(angle)-18,52,36);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (_sector >= 0) return [_sectorPath containsPoint:point];
    return [super pointInside:point withEvent:event];
}
- (CGPoint)accessibilityActivationPoint {
    if (_sector < 0 || !self.window) return super.accessibilityActivationPoint;
    CGPoint point = [self convertPoint:self.titleLabel.center toView:self.window];
    return [self.window convertPoint:point toCoordinateSpace:self.window.screen.coordinateSpace];
}
- (void)pressInput { [self setPressed:YES]; }
- (void)releaseInput { [self setPressed:NO]; }
@end

@interface AKGamepadStick : UIControl
@property(nonatomic, copy) NSString *element;
@property(nonatomic, readonly) CGPoint position;
- (void)reset;
@end
@implementation AKGamepadStick { UIView *_knob; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.exclusiveTouch = NO;
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.48];
        self.layer.borderWidth = 1; self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        _knob = [UIView new]; _knob.userInteractionEnabled = NO;
        _knob.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.55]; [self addSubview:_knob];
        self.isAccessibilityElement = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat diameter = MIN(self.bounds.size.width,self.bounds.size.height);
    self.layer.cornerRadius = diameter/2;
    _knob.bounds = CGRectMake(0,0,diameter*0.42,diameter*0.42); _knob.layer.cornerRadius = diameter*0.21;
    _knob.center = CGPointMake(self.bounds.size.width/2 + _position.x*diameter*0.27,
                               self.bounds.size.height/2 - _position.y*diameter*0.27);
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return hypot(point.x-self.bounds.size.width/2,point.y-self.bounds.size.height/2) <= MIN(self.bounds.size.width,self.bounds.size.height)/2;
}
- (void)updatePosition:(CGPoint)position {
    if (CGPointEqualToPoint(_position,position)) return;
    _position = position; [self setNeedsLayout]; [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event; [self updatePosition:AKTouchGamepadStickPosition([touch locationInView:self],self.bounds.size)]; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event; [self updatePosition:AKTouchGamepadStickPosition([touch locationInView:self],self.bounds.size)]; return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)touch; (void)event; [self reset]; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { (void)event; [self reset]; }
- (void)reset { [self updatePosition:CGPointZero]; }
@end

@interface AKGamepadOverlay : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, readonly) NSDictionary<NSString *,AKGamepadButton *> *buttons;
@property(nonatomic, readonly) AKGamepadStick *leftStick;
@property(nonatomic, readonly) AKGamepadStick *rightStick;
@property(nonatomic, readonly) AKGamepadLayout *preferences;
@property(nonatomic) BOOL controlsVisible;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, readonly) BOOL editing;
@property(nonatomic, copy) void (^configurationChanged)(void);
- (void)reset;
- (void)toggleSettings;
- (void)finishConfiguration;
@end
@implementation AKGamepadOverlay {
    NSDictionary<NSString *,UIView *> *_items;
    NSMutableDictionary<NSString *,NSValue *> *_dragOrigins;
    UIView *_settings;
    UIButton *_editDone;
    UILabel *_hint;
    UISwitch *_editSwitch, *_hapticsSwitch, *_overlaySwitch;
    NSArray<UISlider *> *_sliders;
    NSArray<UILabel *> *_values;
    CAShapeLayer *_editGrid, *_editAxes;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        // Above the guest surface, below the cursor and keyboard toolbar.
        self.layer.zPosition = 99999;
        _preferences = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        _dragOrigins = [NSMutableDictionary new];
        _editGrid = [CAShapeLayer layer]; _editAxes = [CAShapeLayer layer];
        _editGrid.name = @"WolkaraEditGrid"; _editAxes.name = @"WolkaraEditAxes";
        for (CAShapeLayer *layer in @[_editGrid, _editAxes]) {
            layer.fillColor = nil; layer.zPosition = -1; [self.layer addSublayer:layer];
        }
        _editGrid.strokeColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor; _editGrid.lineWidth = 0.5;
        _editAxes.strokeColor = [UIColor.systemYellowColor colorWithAlphaComponent:0.6].CGColor; _editAxes.lineWidth = 1;
        _editAxes.lineDashPattern = @[@4,@4];
        NSArray *elements = @[GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,
            GCInputLeftShoulder,GCInputLeftTrigger,GCInputRightTrigger,GCInputRightShoulder,
            GCInputButtonMenu,@"dpad.up",@"dpad.right",@"dpad.down",@"dpad.left"];
        NSArray *titles = @[@"A",@"B",@"X",@"Y",@"LB",@"LT",@"RT",@"RB",@"+",@"↑",@"→",@"↓",@"←"];
        NSMutableDictionary *buttons = [NSMutableDictionary new];
        UIView *left = [UIView new], *right = [UIView new];
        left.multipleTouchEnabled = right.multipleTouchEnabled = YES;
        [self addSubview:left]; [self addSubview:right];
        for (NSUInteger i=0; i<elements.count; i++) {
            AKGamepadButton *button = [AKGamepadButton new]; button.element = elements[i];
            [button setTitle:titles[i] forState:UIControlStateNormal];
            button.accessibilityLabel = [@"Controller " stringByAppendingString:elements[i]];
            button.accessibilityIdentifier = [@"tolkara.gamepad." stringByAppendingString:elements[i]];
            buttons[elements[i]] = button;
            [(i<4 ? right : i>=9 ? left : self) addSubview:button];
        }
        _buttons = buttons;
        _leftStick = [AKGamepadStick new]; _rightStick = [AKGamepadStick new];
        _leftStick.element = GCInputLeftThumbstick; _rightStick.element = GCInputRightThumbstick;
        _leftStick.accessibilityLabel = @"Controller left stick"; _rightStick.accessibilityLabel = @"Controller right stick";
        _leftStick.accessibilityIdentifier = @"tolkara.gamepad.leftStick"; _rightStick.accessibilityIdentifier = @"tolkara.gamepad.rightStick";
        [left addSubview:_leftStick]; [right addSubview:_rightStick];
        _items = @{@"left":left,@"right":right,@"LB":buttons[GCInputLeftShoulder],@"LT":buttons[GCInputLeftTrigger],
            @"RB":buttons[GCInputRightShoulder],@"RT":buttons[GCInputRightTrigger],@"menu":buttons[GCInputButtonMenu]};
        for (NSString *name in _items) {
            UIView *item = _items[name]; item.accessibilityIdentifier = [@"wolkara.layout." stringByAppendingString:name];
            // Retain button identifiers used by input tests and accessibility.
            if ([item isKindOfClass:AKGamepadButton.class]) item.accessibilityIdentifier = [@"tolkara.gamepad." stringByAppendingString:((AKGamepadButton *)item).element];
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
            pan.delegate = self; [item addGestureRecognizer:pan];
        }
        _editDone = [UIButton buttonWithType:UIButtonTypeSystem];
        [_editDone setTitle:@"Done editing" forState:UIControlStateNormal];
        _editDone.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        _editDone.tintColor = UIColor.systemYellowColor; _editDone.layer.cornerRadius = 14;
        _editDone.accessibilityIdentifier = @"wolkara.layout.done";
        [_editDone addTarget:self action:@selector(finishConfiguration) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_editDone];
        _hint = [UILabel new]; _hint.text = @"Drag controls to move them";
        _hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _hint.textColor = UIColor.whiteColor; _hint.textAlignment = NSTextAlignmentCenter;
        _hint.userInteractionEnabled = NO; [self addSubview:_hint];
        [self updateAppearance];
    }
    return self;
}
- (BOOL)configuring { return _settings != nil || _editing; }
- (void)setControlsVisible:(BOOL)visible { _controlsVisible = visible; [self updateAppearance]; }
- (void)updateAppearance {
    self.hidden = !_controlsVisible && !self.configuring;
    for (UIView *item in _items.allValues) {
        item.hidden = !_controlsVisible && !self.configuring;
        item.alpha = _editing ? MAX(0.5,_preferences.opacity) : _preferences.opacity;
        item.layer.borderWidth = _editing ? 1 : ([item isKindOfClass:AKGamepadButton.class] ? 1 : 0);
        item.layer.borderColor = (_editing ? UIColor.systemYellowColor : [UIColor colorWithWhite:1 alpha:0.3]).CGColor;
    }
    // An enabled UIControl is needed for its own pan recognizer to receive
    // touches. The manager suppresses game input throughout configuration.
    for (AKGamepadButton *button in _buttons.allValues) button.enabled = !self.configuring || _editing;
    _leftStick.enabled = _rightStick.enabled = !self.configuring;
    _editDone.hidden = _hint.hidden = !_editing;
    _editGrid.hidden = _editAxes.hidden = !_editing;
    [self setNeedsLayout];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.configuring) return hit; // Editing/settings must never click the game.
    if (hit == self || hit == _items[@"left"] || hit == _items[@"right"]) return nil;
    return hit;
}
- (CGRect)usableBounds { return UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets); }
- (void)place:(NSString *)name frame:(CGRect)frame baseSize:(CGSize)base safe:(CGRect)safe {
    UIView *item = _items[name];
    CGRect placed = [_preferences frameForItem:name defaultFrame:frame inBounds:safe];
    item.transform = CGAffineTransformIdentity; item.bounds = (CGRect){CGPointZero,base};
    item.center = CGPointMake(CGRectGetMidX(placed),CGRectGetMidY(placed));
    item.transform = CGAffineTransformMakeScale(placed.size.width/base.width,placed.size.height/base.height);
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGRect safe = [self usableBounds];
    if (_editing) [self layoutEditGridInBounds:safe];
    CGFloat side = MIN(216*_preferences.frontScale,MIN(safe.size.height-70,safe.size.width/2-12));
    side = MAX(44,side);
    CGFloat w = 56*_preferences.rearScale, h = 44*_preferences.rearScale;
    CGFloat left = CGRectGetMinX(safe)+6, right = CGRectGetMaxX(safe)-6;
    CGFloat bottom = CGRectGetMaxY(safe)-6, top = CGRectGetMinY(safe)+8;
    [self place:@"left" frame:CGRectMake(left,bottom-side,side,side) baseSize:CGSizeMake(216,216) safe:safe];
    [self place:@"right" frame:CGRectMake(right-side,bottom-side,side,side) baseSize:CGSizeMake(216,216) safe:safe];
    _leftStick.frame = _rightStick.frame = CGRectMake(56,56,104,104);
    NSArray *leftNames = @[@"dpad.up",@"dpad.right",@"dpad.down",@"dpad.left"];
    NSArray *rightNames = @[GCInputButtonY,GCInputButtonB,GCInputButtonA,GCInputButtonX];
    for (NSUInteger i=0; i<4; i++) {
        AKGamepadButton *a = _buttons[leftNames[i]], *b = _buttons[rightNames[i]];
        if (a.sector != (NSInteger)i) a.sector = i;
        if (b.sector != (NSInteger)i) b.sector = i;
        a.frame = b.frame = CGRectMake(0,0,216,216);
    }
    [self place:@"LT" frame:CGRectMake(left,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    [self place:@"LB" frame:CGRectMake(left+w+8,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    [self place:@"RT" frame:CGRectMake(right-w,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    [self place:@"RB" frame:CGRectMake(right-w*2-8,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    [self place:@"menu" frame:CGRectMake(CGRectGetMidX(self.bounds)-22,bottom-side+190*side/216-22,44,44)
        baseSize:CGSizeMake(44,44) safe:safe];
    _editDone.frame = CGRectMake(CGRectGetMidX(safe)-70,CGRectGetMinY(safe)+60,140,40);
    _hint.frame = CGRectMake(CGRectGetMidX(safe)-150,CGRectGetMinY(safe)+103,300,22);
    if (_settings) {
        // Reserve the fixed toolbar's top row; the panel body scrolls.
        CGFloat width = MIN(390,safe.size.width-24), height = MIN(390,safe.size.height-68);
        _settings.frame = CGRectMake(CGRectGetMidX(safe)-width/2,CGRectGetMaxY(safe)-height-8,width,height);
    }
}
- (void)layoutEditGridInBounds:(CGRect)safe {
    // Symmetric spacing about the safe-area center. Layers are visual guides
    // only: they cannot intercept drags or change a saved control position.
    UIBezierPath *grid = [UIBezierPath bezierPath], *axes = [UIBezierPath bezierPath];
    CGFloat x = CGRectGetMidX(safe), y = CGRectGetMidY(safe), step = 24;
    for (NSInteger column = -(NSInteger)floor(safe.size.width / (2*step)); column*step <= safe.size.width/2; column++) {
        CGFloat line = x + column*step;
        [grid moveToPoint:CGPointMake(line,CGRectGetMinY(safe))]; [grid addLineToPoint:CGPointMake(line,CGRectGetMaxY(safe))];
    }
    for (NSInteger row = -(NSInteger)floor(safe.size.height / (2*step)); row*step <= safe.size.height/2; row++) {
        CGFloat line = y + row*step;
        [grid moveToPoint:CGPointMake(CGRectGetMinX(safe),line)]; [grid addLineToPoint:CGPointMake(CGRectGetMaxX(safe),line)];
    }
    [axes moveToPoint:CGPointMake(x,CGRectGetMinY(safe))]; [axes addLineToPoint:CGPointMake(x,CGRectGetMaxY(safe))];
    [axes moveToPoint:CGPointMake(CGRectGetMinX(safe),y)]; [axes addLineToPoint:CGPointMake(CGRectGetMaxX(safe),y)];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _editGrid.frame = _editAxes.frame = self.bounds;
    _editGrid.path = grid.CGPath; _editAxes.path = axes.CGPath;
    [CATransaction commit];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    (void)gestureRecognizer; return _editing;
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    NSString *name = [_items allKeysForObject:pan.view].firstObject;
    if (!name || !_editing) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        [_dragOrigins setObject:[NSValue valueWithCGRect:pan.view.frame] forKey:name]; [self reset];
    }
    CGRect frame = [_dragOrigins[name] CGRectValue];
    if (pan.state == UIGestureRecognizerStateCancelled) {
        [_preferences moveItem:name toFrame:frame inBounds:[self usableBounds]];
    } else {
        CGPoint delta = [pan translationInView:self];
        frame.origin.x += delta.x; frame.origin.y += delta.y;
        [_preferences moveItem:name toFrame:frame inBounds:[self usableBounds]];
    }
    [self setNeedsLayout]; [self layoutIfNeeded];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [_preferences save]; [_dragOrigins removeObjectForKey:name];
    }
}
- (UILabel *)label:(NSString *)text {
    UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]; label.numberOfLines = 0;
    return label;
}
- (void)toggleSettings {
    if (_settings || _editing) { [self finishConfiguration]; return; }
    [self reset];
    _settings = [UIView new]; _settings.backgroundColor = [UIColor colorWithRed:.06 green:.08 blue:.11 alpha:1];
    _settings.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _settings.layer.cornerRadius = 20; _settings.layer.borderWidth = 1;
    _settings.layer.borderColor = [UIColor colorWithWhite:1 alpha:.2].CGColor;
    _settings.accessibilityIdentifier = @"wolkara.controls.settings";
    [self addSubview:_settings];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_settings addSubview:scroll];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:@"Touch controls"]]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    NSMutableArray *sliders = [NSMutableArray new], *values = [NSMutableArray new];
    NSArray *names = @[@"Transparency",@"Shoulder button size",@"Sticks and face button size"];
    CGFloat initial[] = {1-_preferences.opacity,_preferences.rearScale,_preferences.frontScale};
    CGFloat min[] = {0,0.8,0.65}, max[] = {0.8,1.5,1.4};
    for (NSUInteger i=0; i<3; i++) {
        UILabel *value = [self label:@""]; [values addObject:value]; [stack addArrangedSubview:value];
        UISlider *slider = [UISlider new]; slider.tag = i; slider.minimumValue = min[i]; slider.maximumValue = max[i]; slider.value = initial[i];
        slider.accessibilityLabel = names[i]; slider.accessibilityIdentifier = [@"wolkara.controls." stringByAppendingString:@[@"transparency",@"rearScale",@"frontScale"][i]];
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [sliders addObject:slider]; [stack addArrangedSubview:slider];
    }
    _sliders = sliders; _values = values; [self updateValues];
    _hapticsSwitch = [UISwitch new]; _hapticsSwitch.on = _preferences.hapticsEnabled;
    _hapticsSwitch.accessibilityLabel = @"Haptic feedback";
    _hapticsSwitch.accessibilityIdentifier = @"wolkara.controls.haptics";
    [_hapticsSwitch addTarget:self action:@selector(hapticsChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *hapticsRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:@"Haptic feedback"],_hapticsSwitch]];
    hapticsRow.axis = UILayoutConstraintAxisHorizontal; hapticsRow.alignment = UIStackViewAlignmentCenter;
    [stack addArrangedSubview:hapticsRow];
    _overlaySwitch = [UISwitch new]; _overlaySwitch.on = _preferences.performanceOverlayEnabled;
    _overlaySwitch.accessibilityLabel = @"Performance overlay";
    _overlaySwitch.accessibilityIdentifier = @"wolkara.controls.performanceOverlay";
    [_overlaySwitch addTarget:self action:@selector(overlayChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *overlayRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:@"Performance overlay (FPS & Thermals)"],_overlaySwitch]];
    overlayRow.axis = UILayoutConstraintAxisHorizontal; overlayRow.alignment = UIStackViewAlignmentCenter;
    [stack addArrangedSubview:overlayRow];
    _editSwitch = [UISwitch new]; _editSwitch.accessibilityLabel = @"Edit layout";
    _editSwitch.accessibilityIdentifier = @"wolkara.controls.edit";
    [_editSwitch addTarget:self action:@selector(beginEditing:) forControlEvents:UIControlEventValueChanged];
    UIStackView *editRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:@"Edit layout"],_editSwitch]];
    editRow.axis = UILayoutConstraintAxisHorizontal; editRow.alignment = UIStackViewAlignmentCenter;
    [stack addArrangedSubview:editRow];
    [stack addArrangedSubview:[self label:@"Move each shoulder button, +, or a stick with its ring. Changes are saved on this device."]];
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem]; [reset setTitle:@"Reset to defaults" forState:UIControlStateNormal];
    reset.accessibilityIdentifier = @"wolkara.controls.reset";
    [reset addTarget:self action:@selector(resetLayout) forControlEvents:UIControlEventTouchUpInside];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem]; [done setTitle:@"Done" forState:UIControlStateNormal];
    [done addTarget:self action:@selector(finishConfiguration) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *footer = [[UIStackView alloc] initWithArrangedSubviews:@[reset,done]];
    footer.axis = UILayoutConstraintAxisHorizontal; footer.distribution = UIStackViewDistributionFillEqually;
    footer.translatesAutoresizingMaskIntoConstraints = NO; [_settings addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [footer.bottomAnchor constraintEqualToAnchor:_settings.bottomAnchor constant:-8], [footer.heightAnchor constraintEqualToConstant:44],
        [footer.leadingAnchor constraintEqualToAnchor:_settings.leadingAnchor constant:18], [footer.trailingAnchor constraintEqualToAnchor:_settings.trailingAnchor constant:-18],
        [scroll.topAnchor constraintEqualToAnchor:_settings.topAnchor constant:16], [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-8],
        [scroll.leadingAnchor constraintEqualToAnchor:_settings.leadingAnchor constant:18], [scroll.trailingAnchor constraintEqualToAnchor:_settings.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
- (void)updateValues {
    _values[0].text = [NSString stringWithFormat:@"Transparency · %.0f%%",(1-_preferences.opacity)*100];
    _values[1].text = [NSString stringWithFormat:@"Shoulder button size · %.0f%%",_preferences.rearScale*100];
    _values[2].text = [NSString stringWithFormat:@"Sticks and face button size · %.0f%%",_preferences.frontScale*100];
    for (NSUInteger i=0; i<_sliders.count; i++) _sliders[i].accessibilityValue = _values[i].text;
}
- (void)sliderChanged:(UISlider *)slider {
    if (slider.tag == 0) _preferences.opacity = 1-slider.value;
    else if (slider.tag == 1) _preferences.rearScale = slider.value;
    else if (slider.tag == 2) _preferences.frontScale = slider.value;
    [_preferences save]; [self updateValues]; [self updateAppearance];
}
- (void)hapticsChanged:(UISwitch *)sender {
    _preferences.hapticsEnabled = sender.on; [_preferences save];
    if (self.configurationChanged) self.configurationChanged();
}
- (void)overlayChanged:(UISwitch *)sender {
    _preferences.performanceOverlayEnabled = sender.on; [_preferences save];
    if (self.configurationChanged) self.configurationChanged();
}
- (void)beginEditing:(UISwitch *)sender {
    if (!sender.on) return;
    [self reset]; _editing = YES; [_settings removeFromSuperview]; _settings = nil;
    _sliders = nil; _values = nil; _editSwitch = nil; _hapticsSwitch = nil; _overlaySwitch = nil;
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
- (void)resetLayout {
    [self reset]; [_preferences reset];
    _sliders[0].value = 1-_preferences.opacity; _sliders[1].value = _preferences.rearScale; _sliders[2].value = _preferences.frontScale;
    _hapticsSwitch.on = _preferences.hapticsEnabled;
    _overlaySwitch.on = _preferences.performanceOverlayEnabled;
    [self updateValues]; [self updateAppearance];
}
- (void)finishConfiguration {
    [self reset]; [_preferences save]; _editing = NO; [_dragOrigins removeAllObjects];
    [_settings removeFromSuperview]; _settings = nil; _sliders = nil; _values = nil; _editSwitch = nil; _hapticsSwitch = nil; _overlaySwitch = nil;
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
- (void)reset {
    for (AKGamepadButton *button in _buttons.allValues) [button releaseInput];
    [_leftStick reset]; [_rightStick reset];
}
@end

@implementation AKTouchGamepad {
    __weak UIView *_host;
    GCVirtualController *_virtualController;
    AKGamepadOverlay *_overlay;
    AKTouchHaptics *_haptics;
    BOOL _active, _connecting, _cancelConnect, _failed, _invalidated;
}
- (instancetype)initWithHostView:(UIView *)host {
    if ((self = [super init])) {
        _host = host; _enabled = YES;
        _haptics = [self makeHaptics];
        _overlay = [[AKGamepadOverlay alloc] initWithFrame:host.bounds];
        _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [host addSubview:_overlay];
        __weak AKTouchGamepad *weakSelf = self;
        _overlay.configurationChanged = ^{
            AKTouchGamepad *self = weakSelf;
            [self updateHaptics];
            if (self.visibilityChanged) self.visibilityChanged(self.visible);
        };
        for (AKGamepadButton *button in _overlay.buttons.allValues)
            [button addTarget:self action:@selector(buttonChanged:) forControlEvents:UIControlEventValueChanged];
        [_overlay.leftStick addTarget:self action:@selector(stickChanged:) forControlEvents:UIControlEventValueChanged];
        [_overlay.rightStick addTarget:self action:@selector(stickChanged:) forControlEvents:UIControlEventValueChanged];
        _active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification,
                                 UIWindowDidBecomeKeyNotification, UIWindowDidResignKeyNotification,
                                 UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeHiddenNotification])
            [center addObserver:self selector:@selector(environmentChanged:) name:name object:nil];
        [center addObserver:self selector:@selector(activate:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(deactivate:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}
- (NSArray<GCController *> *)connectedControllers { return GCController.controllers; }
- (AKTouchHaptics *)makeHaptics { return [AKTouchHaptics new]; }
- (void)updateHaptics { _haptics.enabled = _visible && !_overlay.configuring && _overlay.preferences.hapticsEnabled; }
- (GCVirtualController *)makeController {
    GCVirtualControllerConfiguration *configuration = [GCVirtualControllerConfiguration new];
    configuration.hidden = YES;
    // The configuration still applies the standard overlay's restrictions:
    // declaring D-pad plus left stick (or Menu/Options) throws even when hidden.
    // The connected extended profile provides D-pad and Menu nonetheless;
    // the public setters for both are covered by the real-controller fixture.
    configuration.elements = [NSSet setWithArray:@[GCInputLeftThumbstick,GCInputRightThumbstick,
        GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,
        GCInputLeftShoulder,GCInputRightShoulder,GCInputLeftTrigger,GCInputRightTrigger]];
    return [[GCVirtualController alloc] initWithConfiguration:configuration];
}
- (BOOL)hostIsActive {
    UIWindow *window = _host.window;
    return _active && window.isKeyWindow && !window.hidden && !_host.hidden;
}
- (BOOL)hasPhysicalController {
    GCController *own = _virtualController.controller;
    for (GCController *controller in [self connectedControllers]) {
        // Snapshots are app-created state, not connected hardware. Our own
        // connection notification must not cause us to disconnect ourselves.
        if (controller != own && !controller.isSnapshot &&
            (controller.extendedGamepad || controller.microGamepad)) return YES;
    }
    return NO;
}
- (BOOL)wantsController {
    return !_invalidated && _enabled && !_keyboardVisible && [self hostIsActive];
}
- (void)setVisible:(BOOL)visible {
    if (_visible == visible) return;
    _visible = visible; _overlay.controlsVisible = visible;
    [self updateHaptics];
    if (self.visibilityChanged) self.visibilityChanged(visible);
}
- (void)buttonChanged:(AKGamepadButton *)button {
    if (!_visible || _overlay.configuring) return;
    if (button.pressed) [_haptics buttonPressed];
    if ([button.element hasPrefix:@"dpad."]) {
        CGPoint value = CGPointMake(_overlay.buttons[@"dpad.right"].pressed - _overlay.buttons[@"dpad.left"].pressed,
                                    _overlay.buttons[@"dpad.up"].pressed - _overlay.buttons[@"dpad.down"].pressed);
        [_virtualController setPosition:value forDirectionPadElement:GCInputDirectionPad];
    } else [_virtualController setValue:button.pressed ? 1 : 0 forButtonElement:button.element];
}
- (void)stickChanged:(AKGamepadStick *)stick {
    if (_visible && !_overlay.configuring) {
        [_haptics stickMoved:stick.position left:stick == _overlay.leftStick];
        [_virtualController setPosition:stick.position forDirectionPadElement:stick.element];
    }
}
- (void)disconnectController {
    GCVirtualController *controller = _virtualController;
    // Explicitly release our held controls before removing the virtual device.
    // No value or handler on a physical controller is changed.
    [_overlay reset];
    _virtualController = nil;
    [controller disconnect];
    [self setVisible:NO];
}
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"Touch controller lifecycle belongs on the main thread");
    if (_connecting) {
        // Wait for this attempt's reply before starting another one. A late
        // successful connect must not bring controls back after suspension.
        if (![self wantsController]) { _cancelConnect = YES; [_virtualController disconnect]; }
        return;
    }
    if (![self wantsController] || [self hasPhysicalController]) {
        [self disconnectController]; return;
    }
    if (_virtualController || _failed) return;
    _virtualController = [self makeController];
    _connecting = YES; _cancelConnect = NO;
    GCVirtualController *connecting = _virtualController;
    __weak AKTouchGamepad *weakSelf = self;
    [connecting connectWithReplyHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AKTouchGamepad *self = weakSelf;
            if (!self) { [connecting disconnect]; return; }
            self->_connecting = NO;
            BOOL cancelled = self->_cancelConnect;
            self->_cancelConnect = NO;
            if (error || cancelled || ![self wantsController] || [self hasPhysicalController]) {
                if (error) NSLog(@"[TouchGamepad] Connection failed: %@ (%ld)",error.domain,(long)error.code);
                self->_failed = error != nil;
                [self disconnectController];
                if (cancelled && !error) [self refresh];
                return;
            }
            [self setVisible:YES];
        });
    }];
}
- (void)environmentChanged:(NSNotification *)note {
    (void)note;
    // GC notifications can precede connect's reply or arrive off-main. Defer
    // enumeration until the system finishes the connection transaction.
    __weak AKTouchGamepad *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}
- (void)activate:(NSNotification *)note {
    (void)note; _active = YES; _failed = NO; [self refresh];
}
- (void)deactivate:(NSNotification *)note {
    (void)note; [_overlay finishConfiguration]; _active = NO; [self refresh];
}
- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled; _failed = NO; [self refresh];
}
- (void)setKeyboardVisible:(BOOL)visible {
    _keyboardVisible = visible; [self refresh];
}
- (BOOL)configuring { return _overlay.configuring; }
- (void)toggleSettings { [_overlay toggleSettings]; }
- (void)invalidate {
    [_overlay finishConfiguration];
    _invalidated = YES;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self refresh];
    [_overlay removeFromSuperview];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_virtualController disconnect];
}
@end
