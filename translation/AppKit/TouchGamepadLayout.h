#import <UIKit/UIKit.h>

// Posted after saving; the object is the defaults store that changed.
FOUNDATION_EXPORT NSNotificationName const AKGamepadLayoutDidChangeNotification;

// Preferences contain only UI appearance/feedback; never controller or game state.
@interface AKGamepadLayout : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property(nonatomic) CGFloat opacity;
@property(nonatomic) CGFloat rearScale;
@property(nonatomic) CGFloat frontScale;
@property(nonatomic) BOOL hapticsEnabled;
@property(nonatomic) BOOL performanceOverlayEnabled;
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)save;
- (void)reset;
@end
