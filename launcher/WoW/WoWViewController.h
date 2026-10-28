#import <UIKit/UIKit.h>
#import "../App/AppLibrary.h"
#import "../App/ExecutionMode.h"

NS_ASSUME_NONNULL_BEGIN
@class TKLaunchProgressView;
@interface TKWoWViewController : UIViewController
- (instancetype)initWithLibrary:(TKAppLibrary *)library;
@property(nonatomic, copy, nullable) void (^startApp)(TKApp *app);
@property(nonatomic, copy, nullable) void (^showDiagnostics)(void);
@property(nonatomic) TKExecutionMode executionMode;
@property(nonatomic) BOOL sessionUsed;
// Reuse this home screen throughout startup; the runtime retains its execution path.
@property(nonatomic, readonly) UILabel *startupStatusLabel;
@property(nonatomic, readonly) TKLaunchProgressView *launchProgress;
@property(nonatomic, readonly) UIButton *diagnosticsButton;
- (void)beginStartup;
- (void)finishStartupWithMessage:(NSString *)message failed:(BOOL)failed;
- (void)openAddons;
- (void)promptForAPIKey;
- (void)checkAddonUpdatesPromptUser:(BOOL)promptUser;
- (void)exportBackup;
- (void)importBackup;
@end
NS_ASSUME_NONNULL_END
