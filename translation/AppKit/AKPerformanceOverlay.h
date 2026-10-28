#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AKPerformanceOverlayDidChangeNotification;

@interface AKPerformanceOverlay : UIView

@property (nonatomic, assign, getter=isExpanded) BOOL expanded;

// Updates metrics immediately from system sensors and Metal presentation.
- (void)updateMetrics;

@end

NS_ASSUME_NONNULL_END
