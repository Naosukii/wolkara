#import <UIKit/UIKit.h>
#import "../App/AppLibrary.h"

NS_ASSUME_NONNULL_BEGIN

@interface TKWoWAddonViewController : UIViewController

- (instancetype)initWithLibrary:(nullable TKAppLibrary *)library selectedProduct:(NSDictionary *)product;

@property(nonatomic, copy, nullable) void (^onProductChanged)(NSDictionary *product);
@property(nonatomic, copy, nullable) void (^onAddonsChanged)(void);

@end

NS_ASSUME_NONNULL_END
