#import "WoWViewController.h"
#import "Client.h"
#import "Installation.h"
#import "Updater.h"
#import "AddonManager.h"
#import "AddonViewController.h"
#import "CASC.h"
#import "../App/LaunchProgressView.h"

static UIColor *Gold(void) { return [UIColor colorWithRed:0.88 green:0.73 blue:0.43 alpha:1]; }
static UIColor *Muted(void) { return [UIColor colorWithRed:0.66 green:0.72 blue:0.78 alpha:1]; }
static UILabel *Label(CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label=[UILabel new]; label.numberOfLines=0; label.textColor=color;
    label.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
    label.adjustsFontForContentSizeCategory=YES;
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    return label;
}
static UIStackView *Stack(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=spacing; return stack;
}

@implementation TKWoWViewController {
    TKAppLibrary *_library;
    TKWoWClient *_client;
    NSDictionary *_product, *_plan;
    TKWoWInstallation *_installation;
    NSString *_region, *_locale;
    NSError *_error;
    NSDate *_checkedAt;
    NSUInteger _generation;
    BOOL _busy, _updating, _updateError, _starting;
    NSString *_startupFailure;
    UILabel *_updatesLabel;
    NSString *_updatePhase;
    uint64_t _updateDone, _updateTotal;
    UIProgressView *_progressBar;
    CAGradientLayer *_background;
    UIStackView *_columns;
    NSLayoutConstraint *_leftWidth;
    UILabel *_stateLabel, *_detailLabel, *_versionLabel, *_startupLabel, *_compatibilityLabel;
    UIButton *_editionButton, *_preferencesButton, *_addonsButton, *_primaryButton;
    UIBarButtonItem *_refreshItem;
    UIActivityIndicatorView *_activity;
}
- (instancetype)initWithLibrary:(TKAppLibrary *)library {
    if (!(self=[super initWithNibName:nil bundle:nil])) return nil;
    _library=library; self.title=@"";
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    _product=TKWoWProducts()[0];
    for (NSDictionary *p in TKWoWProducts()) if ([p[@"id"] isEqual:[defaults stringForKey:@"WoWProduct"]]) _product=p;
    _region=[defaults stringForKey:@"WoWRegion"]?:@"eu";
    if (![@[@"eu",@"us",@"kr",@"tw"] containsObject:_region]) _region=@"eu";
    _locale=[defaults stringForKey:@"WoWLocale"]?:@"enUS";
    if (![@[@"enUS",@"esES",@"deDE"] containsObject:_locale]) _locale=@"enUS";
    return self;
}
- (UIButton *)button:(NSString *)identifier action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityIdentifier=identifier;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=[UIColor colorWithRed:0.025 green:0.045 blue:0.075 alpha:1];
    _background=[CAGradientLayer layer];
    _background.colors=@[(id)[UIColor colorWithRed:0.035 green:0.085 blue:0.13 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.03 blue:0.055 alpha:1].CGColor];
    _background.startPoint=CGPointMake(0,0); _background.endPoint=CGPointMake(1,1);
    [self.view.layer insertSublayer:_background atIndex:0];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
        style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Settings";
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier=@"wow.settings";
    self.navigationItem.backButtonTitle=@"Back";
    _refreshItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
        style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    _refreshItem.accessibilityLabel=@"Check for updates";
    _refreshItem.accessibilityIdentifier=@"wow.refresh";
    self.navigationItem.leftBarButtonItem=_refreshItem;

    UILabel *title=Label(37,UIFontWeightBold,Gold()); title.text=@"WOLKARA";
    UIFontDescriptor *serif=[[UIFont systemFontOfSize:37 weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
    if (serif) title.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:[UIFont fontWithDescriptor:serif size:37]];
    title.accessibilityIdentifier=@"wow.title";
    UILabel *editionLabel=Label(11,UIFontWeightSemibold,Muted()); editionLabel.text=@"GAME EDITION";
    _editionButton=[self button:@"wow.edition" action:@selector(chooseEdition)];
    _preferencesButton=[self button:@"wow.preferences" action:@selector(preferences)];
    UILabel *addonsLabel=Label(11,UIFontWeightSemibold,Muted()); addonsLabel.text=@"ADD-ONS";
    _addonsButton=[self button:@"wow.addons" action:@selector(openAddons)];
    _compatibilityLabel=Label(12,UIFontWeightRegular,Muted());
    UIStackView *left=Stack(@[title,editionLabel,_editionButton,_preferencesButton,addonsLabel,_addonsButton,_compatibilityLabel],12);
    [left setCustomSpacing:24 afterView:title];
    [left setCustomSpacing:20 afterView:_preferencesButton];

    _activity=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _activity.color=Gold(); _activity.hidesWhenStopped=YES;
    _stateLabel=Label(23,UIFontWeightSemibold,UIColor.whiteColor); _stateLabel.accessibilityIdentifier=@"wow.status";
    UIStackView *stateRow=[[UIStackView alloc] initWithArrangedSubviews:@[_activity,_stateLabel]];
    stateRow.axis=UILayoutConstraintAxisHorizontal; stateRow.spacing=10;
    // A hidden activity indicator retains its 20pt intrinsic height. Center
    // it rather than stretching/compressing both views to that same height.
    stateRow.alignment=UIStackViewAlignmentCenter;
    [_activity setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _detailLabel=Label(15,UIFontWeightRegular,Muted()); _detailLabel.accessibilityIdentifier=@"wow.detail";
    _versionLabel=Label(12,UIFontWeightRegular,Muted()); _versionLabel.accessibilityIdentifier=@"wow.version";
    _progressBar=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressBar.progressTintColor=Gold(); _progressBar.accessibilityIdentifier=@"wow.progress";
    _launchProgress=[TKLaunchProgressView new];
    _launchProgress.accessibilityIdentifier=@"wow.elapsed";
    _diagnosticsButton=[self button:@"wow.diagnostics" action:@selector(diagnostics)];
    [_diagnosticsButton setTitle:@"Diagnostics and logs" forState:UIControlStateNormal];
    _diagnosticsButton.tintColor=Gold(); _diagnosticsButton.hidden=YES;
    UIStackView *status=Stack(@[stateRow,_detailLabel,_progressBar,_launchProgress,_versionLabel,_diagnosticsButton],10);
    status.layoutMargins=UIEdgeInsetsMake(20,20,20,20); status.layoutMarginsRelativeArrangement=YES;
    status.backgroundColor=[UIColor colorWithRed:0.07 green:0.105 blue:0.15 alpha:1];
    status.layer.cornerRadius=16; status.layer.borderWidth=1;
    status.layer.borderColor=[Gold() colorWithAlphaComponent:0.24].CGColor;
    _primaryButton=[self button:@"wow.primary" action:@selector(primaryAction)];
    [_primaryButton.heightAnchor constraintGreaterThanOrEqualToConstant:52].active=YES;
    _updatesLabel=Label(12,UIFontWeightRegular,Muted()); _updatesLabel.accessibilityIdentifier=@"wow.updates";
    _updatesLabel.text=@"Updates automatically. Keep this app open while downloading.";
    _startupLabel=Label(12,UIFontWeightRegular,Muted()); _startupLabel.accessibilityIdentifier=@"wow.startup";
    UIStackView *right=Stack(@[status,_primaryButton,_updatesLabel,_startupLabel],12);
    _columns=Stack(@[left,right],32); _columns.accessibilityIdentifier=@"wow.columns";
    _columns.alignment=UIStackViewAlignmentTop;
    _leftWidth=[left.widthAnchor constraintEqualToAnchor:_columns.widthAnchor multiplier:0.38];

    UIScrollView *scroll=[UIScrollView new]; scroll.accessibilityIdentifier=@"wow.scroll";
    scroll.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:scroll];
    _columns.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:_columns];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [_columns.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [_columns.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [_columns.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
        [_columns.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
        [_columns.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48]
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [self render];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new]; [appearance configureWithOpaqueBackground];
    appearance.backgroundColor=[UIColor colorWithRed:0.025 green:0.045 blue:0.075 alpha:1];
    appearance.titleTextAttributes=@{NSForegroundColorAttributeName:Gold()};
    self.navigationItem.standardAppearance=appearance; self.navigationItem.scrollEdgeAppearance=appearance;
    self.navigationItem.compactAppearance=appearance;
    self.navigationController.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.navigationController.navigationBar.prefersLargeTitles=NO;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationController.navigationBar.tintColor=Gold();
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _background.frame=self.view.bounds;
    BOOL horizontal=self.view.bounds.size.width>=700 && !UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    _leftWidth.active=horizontal;
    _columns.axis=horizontal?UILayoutConstraintAxisHorizontal:UILayoutConstraintAxisVertical;
    _columns.alignment=horizontal?UIStackViewAlignmentTop:UIStackViewAlignmentFill;
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (!_busy && !_sessionUsed && !_starting) [self refresh]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self cancel]; }
- (void)foreground:(NSNotification *)note {
    (void)note;
    if (self.isViewLoaded && self.view.window && self.navigationController.topViewController==self && !_busy && !_sessionUsed && !_starting) [self refresh];
}
- (void)background:(NSNotification *)note { (void)note; [self cancel]; }
- (void)cancel { [_client cancel]; _client=nil; _generation++; _busy=NO; }
- (void)setExecutionMode:(TKExecutionMode)mode { _executionMode=mode; if (self.isViewLoaded) [self render]; }
- (void)setSessionUsed:(BOOL)used { _sessionUsed=used; if (used) [self cancel]; if (self.isViewLoaded) [self render]; }
- (void)selectProduct:(NSDictionary *)product {
    if (_starting || _sessionUsed) return;
    if (![TKWoWProducts() containsObject:product]) return;
    _product=product;
    [NSUserDefaults.standardUserDefaults setObject:product[@"id"] forKey:@"WoWProduct"];
    [self refresh];
}
- (void)refresh { [self checkForUpdatesAndLaunch:NO]; }
- (void)checkForUpdatesAndLaunch:(BOOL)launch { [self checkForUpdatesAndLaunch:launch install:NO]; }
- (void)checkForUpdatesAndLaunch:(BOOL)launch install:(BOOL)install {
    if (_starting || _sessionUsed) return;
    NSString *installKey=[@"WoWInstallRequested." stringByAppendingString:_product[@"id"]];
    NSString *repairKey=[@"WoWRepairRequested." stringByAppendingString:_product[@"id"]];
    if(install && _installation.state==TKWoWInstallationNeedsRepair)
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:repairKey];
    if(install)[NSUserDefaults.standardUserDefaults setBool:YES forKey:installKey];
    install=install || [NSUserDefaults.standardUserDefaults boolForKey:installKey];
    BOOL repair=[NSUserDefaults.standardUserDefaults boolForKey:repairKey];
    [self cancel]; _plan=nil; _installation=nil; _error=nil; _checkedAt=nil; _startupFailure=nil;
    _updating=NO; _updateError=NO; _updatePhase=nil; _updateDone=0; _updateTotal=0;
    _client=[TKWoWClient new]; _busy=YES; [self render];
    TKWoWClient *client=_client; NSUInteger generation=_generation;
    NSDictionary *product=_product; NSString *region=_region, *locale=_locale;
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once,^{ queue=dispatch_queue_create("org.tolkara.wow-updates",DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue,^{
        [self->_library discover];
        NSError *error=nil;
        NSDictionary *plan=[client planForProduct:product[@"id"] region:region locale:locale error:&error];
        TKWoWInstallation *installation=plan?TKWoWInspectInstallation(self->_library,product,plan):nil;
        BOOL performInstall=install;
        if(installation.state==TKWoWInstallationReady && plan[@"config"]) {
            NSString *directory=installation.app?[self->_library workingDirectoryForApp:installation.app error:nil]:nil;
            NSString *cascDir=directory?[directory.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Data/data"]:nil;
            if(cascDir) {
                NSFileManager *fm=NSFileManager.defaultManager;
                for(NSString *name in [fm contentsOfDirectoryAtPath:cascDir error:NULL]) {
                    if([name hasPrefix:@"index.lock"] || [name isEqualToString:@"shmem"]) {
                        [fm removeItemAtPath:[cascDir stringByAppendingPathComponent:name] error:NULL];
                    }
                }
            }
            TKWoWCASCStore *store=cascDir?[[TKWoWCASCStore alloc] initWithDirectory:cascDir error:nil]:nil;
            if(store) {
                for(NSString *bootstrap in @[@"encoding",@"install",@"download",@"patch-index"]) {
                    NSString *val=plan[@"config"][bootstrap];
                    if(!val)continue;
                    NSArray *keys=[[val componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
                    if(keys.count>=2 && ![store verifyKey:keys[1] size:0]) {
                        NSLog(@"[wow-update] Bootstrap manifest '%@' (%@) is missing from CASC store; triggering update.",bootstrap,keys[1]);
                        performInstall=YES;break;
                    }
                }
            }
        }
        BOOL updateAttempted=plan && (performInstall || installation.state==TKWoWInstallationOutdated) && !client.cancelled;
        if(updateAttempted) {
            __block NSString *lastPhase=nil;
            void (^progress)(NSString *,uint64_t,uint64_t)=^(NSString *phase,uint64_t done,uint64_t total) {
                if(![lastPhase isEqual:phase]) {
                    lastPhase=phase;NSLog(@"[wow-update] Phase: %@",phase);
                }
                dispatch_async(dispatch_get_main_queue(),^{
                    if(generation!=self->_generation)return;
                    self->_plan=plan;self->_installation=installation;self->_updating=YES;
                    self->_updatePhase=phase;self->_updateDone=done;self->_updateTotal=total;[self render];
                });
            };
            progress(@"snapshot",0,0);
            NSString *directory=installation.app?[self->_library workingDirectoryForApp:installation.app error:&error]:nil;
            NSString *root=directory?directory.stringByDeletingLastPathComponent:
                [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"World of Warcraft"];
            TKWoWUpdater *updater=[[TKWoWUpdater alloc] initWithClient:client];
            updater.fullVerification=repair;
            if([updater updatePlan:plan root:root progress:progress error:&error]) {
                [self->_library discover];installation=TKWoWInspectInstallation(self->_library,product,plan);error=nil;
                // Editions without a bundled compatibility profile still need a
                // library entry after their first download. Register only the
                // original executable already verified by the install manifest.
                if(installation.state==TKWoWInstallationMissing) {
                    NSMutableArray *executables=[NSMutableArray new];
                    for(NSDictionary *file in plan[@"files"])if([file[@"path"] hasSuffix:@".app/Contents/MacOS/World of Warcraft"])
                        [executables addObject:[[root stringByAppendingPathComponent:product[@"folder"]] stringByAppendingPathComponent:file[@"path"]]];
                    if(executables.count==1 && [self->_library importExecutable:executables[0] copy:NO error:&error])
                        installation=TKWoWInspectInstallation(self->_library,product,plan);
                }
                if(installation.state==TKWoWInstallationReady) {
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:installKey];
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:repairKey];
                }
                else error=error?:installation.error?:TKWoWError(@"The downloaded installation could not be registered in the library.");
            }
            if(error)NSLog(@"[wow-update] Interrupted during %@: %@ (%@:%ld)",lastPhase?:@"preparation",
                error.localizedDescription,error.domain,(long)error.code);
            NSLog(@"[wow-update] Verification bytes read=%llu reused=%llu",updater.verificationBytesRead,updater.verificationBytesReused);
        }

        dispatch_async(dispatch_get_main_queue(),^{
            if (generation!=self->_generation) return;
            self->_plan=plan; self->_installation=installation; self->_error=error;
            self->_checkedAt=plan?NSDate.date:nil; self->_busy=NO; self->_updating=NO; self->_updateError=updateAttempted && error; [self render];
            // Returning from the background or changing edition invalidates this request.
            if (launch && !error && !client.cancelled && installation.state==TKWoWInstallationReady && installation.app && !self->_sessionUsed &&
                self.view.window && self.navigationController.topViewController==self && self.startApp) self.startApp(installation.app);
        });
    });
}
- (void)primaryAction {
    if (_busy || _sessionUsed || _starting) return;
    if (_startupFailure) { _startupFailure=nil; [self render]; }
    if (_error || !_plan) { [self refresh]; return; }
    if (_installation.state==TKWoWInstallationMissing || _installation.state==TKWoWInstallationNeedsRepair) {
        [self checkForUpdatesAndLaunch:NO install:YES];return;
    }
    if (_installation.state!=TKWoWInstallationReady) return;
    if (_executionMode==TKExecutionModeNone) return;
    [self checkForUpdatesAndLaunch:YES];
}
- (void)repairInstallation {
    if(_busy || _starting || _sessionUsed || !_installation.app)return;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"WoWRepairRequested." stringByAppendingString:_product[@"id"]]];
    [self checkForUpdatesAndLaunch:NO install:YES];
}
- (void)configureButton:(UIButton *)button title:(NSString *)title filled:(BOOL)filled {
    UIButtonConfiguration *configuration=filled?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.plainButtonConfiguration;
    configuration.title=title; configuration.cornerStyle=UIButtonConfigurationCornerStyleMedium;
    configuration.baseBackgroundColor=Gold(); configuration.baseForegroundColor=filled?[UIColor colorWithRed:0.08 green:0.065 blue:0.035 alpha:1]:Gold();
    configuration.contentInsets=NSDirectionalEdgeInsetsMake(filled?14:6,12,filled?14:6,12);
    button.configuration=configuration;
}
- (void)render {
    if (!self.isViewLoaded) return;
    [self configureButton:_editionButton title:[_product[@"name"] stringByAppendingString:@"  ▾"] filled:NO];
    _editionButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    _editionButton.backgroundColor=[UIColor colorWithWhite:1 alpha:0.055]; _editionButton.layer.cornerRadius=10;
    NSDictionary *languageNames=@{@"enUS":@"English",@"esES":@"Spanish",@"deDE":@"German"};
    [self configureButton:_preferencesButton title:[NSString stringWithFormat:@"%@  ·  %@  ▾",_region.uppercaseString,languageNames[_locale]?:@"English"] filled:NO];
    _preferencesButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    NSArray<NSDictionary *> *installedAddons=[TKWoWAddonManager installedAddonsForProduct:_product library:_library];
    NSString *addonsTitle=installedAddons.count>0?
        [NSString stringWithFormat:@"Manage (%lu installed)  ›",(unsigned long)installedAddons.count]:
        @"Manage Add-ons  ›";
    [self configureButton:_addonsButton title:addonsTitle filled:NO];
    _addonsButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    _addonsButton.backgroundColor=[UIColor colorWithWhite:1 alpha:0.055]; _addonsButton.layer.cornerRadius=10;
    _addonsButton.enabled=!_busy && !_starting && !_sessionUsed;
    _compatibilityLabel.text=([_product[@"id"] isEqual:@"wow"] || [_product[@"id"] isEqual:@"wow_beta"] || [_product[@"id"] isEqual:@"wow_classic"])?
        @"Compatibility with this edition is not yet verified.":
        @"";
    _compatibilityLabel.hidden=!_compatibilityLabel.text.length;
    _editionButton.enabled=!_busy && !_starting && !_sessionUsed;
    _preferencesButton.enabled=_editionButton.enabled;
    self.navigationItem.rightBarButtonItem.enabled=!_updating && !_starting;
    _primaryButton.hidden=_starting || _sessionUsed;
    _updatesLabel.hidden=_starting || _sessionUsed;
    _startupLabel.hidden=_starting || _sessionUsed;
    _progressBar.hidden=!_updating || !_updateTotal;
    _progressBar.progress=_updateTotal?(float)((double)_updateDone/_updateTotal):0;
    NSString *title=nil, *detail=nil, *action=nil;
    BOOL enabled=NO;
    if (_starting) {
        title=@"Starting…";
        detail=_detailLabel.text.length?_detailLabel.text:@"Preparing to launch. Keep this app open.";
        action=@"Starting…";
    } else if (_startupFailure) {
        title=@"Could not start";
        detail=_sessionUsed?@"Close this app from the app switcher, then reopen it to try again. Details are available in Diagnostics and logs.":@"Try again. Details are available in Diagnostics and logs.";
        action=_sessionUsed?@"Reopen to retry":@"Try again"; enabled=!_sessionUsed;
    } else if (_sessionUsed) {
        title=@"Reopen to start again";
        detail=@"Close the app from the app switcher before starting another session.";
        action=@"Session ended";
    } else if (_busy && _updating) {
        title=@"Updating your game…";
        NSDictionary *phases=@{@"snapshot":@"Preparing the installation",
            @"manifests":@"Reading the update",
            @"verify":@"Checking existing data",
            @"reuse":@"Comparing installed content",
            @"indices":@"Locating download files",
            @"download":@"Downloading new data",
            @"files":@"Installing game files",
            @"activate":@"Finishing the update",
            @"complete":@"Update complete"};
        detail=phases[_updatePhase]?:@"Preparing…";
        if(_updateTotal) {
            BOOL bytes=[_updatePhase isEqual:@"verify"] || [_updatePhase isEqual:@"download"];
            NSString *done=bytes?[NSByteCountFormatter stringFromByteCount:(int64_t)_updateDone countStyle:NSByteCountFormatterCountStyleFile]:@(_updateDone).stringValue;
            NSString *total=bytes?[NSByteCountFormatter stringFromByteCount:(int64_t)_updateTotal countStyle:NSByteCountFormatterCountStyleFile]:@(_updateTotal).stringValue;
            detail=[detail stringByAppendingFormat:@" · %@ / %@",done,total];
        }
        action=@"Updating…";
    } else if (_busy) {
        title=@"Checking for updates…";
        detail=@"Checking the latest version and your installed copy.";
        action=@"Checking…";
    } else if (_error || !_plan) {
        title=_updateError?@"Update interrupted":@"Could not check this edition";
        detail=_updateError?@"Your installed copy is preserved. Try again to resume the update; see Settings for details.":@"We cannot confirm that your game is up to date. Check your connection and try again.";
        action=@"Try again"; enabled=YES;
    } else {
        switch (_installation.state) {
        case TKWoWInstallationMissing:
            title=@"Not installed";
            detail=@"Install this edition on your device. The download may require several gigabytes.";
            action=@"Install"; enabled=YES; break;
        case TKWoWInstallationOutdated:
            title=@"Update required";
            detail=@"A newer build is available. The update starts automatically.";
            action=@"Update needed to play"; break;
        case TKWoWInstallationNeedsRepair:
            title=@"Your copy needs attention";
            detail=@"We could not verify all game files. Repair downloads the original files and keeps your settings and addons.";
            action=@"Repair installation"; enabled=YES; break;
        case TKWoWInstallationReady:
            title=@"Ready to play";
            detail=@"Your game is up to date.";
            action=_executionMode==TKExecutionModeNone?@"Startup unavailable":@"Play"; enabled=_executionMode!=TKExecutionModeNone; break;
        }
    }
    _stateLabel.text=title; _detailLabel.text=detail;
    [self configureButton:_primaryButton title:action filled:YES]; _primaryButton.enabled=enabled;
    _refreshItem.enabled=!_busy && !_sessionUsed && !_starting;
    if (_busy) [_activity startAnimating]; else [_activity stopAnimating];
    if (_checkedAt) {
        NSString *time=[NSDateFormatter localizedStringFromDate:_checkedAt dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
        NSString *available=_plan[@"version"][@"VersionsName"];
        _versionLabel.text=[_installation.installedVersion isEqual:available]?
            [NSString stringWithFormat:@"Version %@ · Checked %@",available,time]:
            [NSString stringWithFormat:@"Installed %@ · Available %@",_installation.installedVersion?:@"—",available];
    } else _versionLabel.text=nil;
    _versionLabel.hidden=!_versionLabel.text.length;
    switch (_executionMode) {
    case TKExecutionModeDeveloperService:
        _startupLabel.text=@"Starting can take a few minutes each time."; break;
    case TKExecutionModeLocalSigning:
        _startupLabel.text=@"Startup requires a signed container matching this version."; break;
    case TKExecutionModeExternalJIT:
        _startupLabel.text=@"Enable JIT before starting a new session."; break;
    case TKExecutionModeNone:
        _startupLabel.text=@"This build cannot start the game. See Diagnostics and logs."; break;
    }
}
- (void)presentSheet:(UIAlertController *)sheet anchor:(UIView *)anchor {
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (anchor) { sheet.popoverPresentationController.sourceView=anchor; sheet.popoverPresentationController.sourceRect=anchor.bounds; }
    else sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)chooseEdition {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Choose your edition" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *product in TKWoWProducts()) [sheet addAction:[UIAlertAction actionWithTitle:product[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; [self selectProduct:product];
    }]];
    [self presentSheet:sheet anchor:_editionButton];
}
- (void)choosePreference:(BOOL)region {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:region?@"Region":@"Download language" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *values=region?@[@"eu",@"us",@"kr",@"tw"]:@[@"enUS",@"esES",@"deDE"];
    NSDictionary *names=@{@"eu":@"Europe",@"us":@"Americas",@"kr":@"Korea",@"tw":@"Taiwan",@"enUS":@"English",@"esES":@"Spanish",@"deDE":@"German"};
    for (NSString *value in values) [sheet addAction:[UIAlertAction actionWithTitle:names[value] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; if (region) self->_region=value; else self->_locale=value;
        [NSUserDefaults.standardUserDefaults setObject:value forKey:region?@"WoWRegion":@"WoWLocale"]; [self refresh];
    }]];
    [self presentSheet:sheet anchor:_preferencesButton];
}
- (void)preferences {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Download preferences"
        message:@"These settings do not change your game's login region." preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Region" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self choosePreference:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Language" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self choosePreference:NO]; }]];
    [self presentSheet:sheet anchor:_preferencesButton];
}
- (void)settings {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Settings"
        message:@"Updates install automatically while this app is open. Settings and addons are preserved. Startup preparation is separate from downloading updates." preferredStyle:UIAlertControllerStyleActionSheet];
    if(!_busy && !_starting && !_sessionUsed && _installation.app) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Verify and repair game files" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a; [self repairInstallation];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Add-on Manager" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self openAddons];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"CurseForge API Key" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self promptForAPIKey];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Diagnostics and logs" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self diagnostics];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"About and open-source licenses" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self about];
    }]];
    if (_startupFailure || _error || _installation.error) [sheet addAction:[UIAlertAction actionWithTitle:@"Technical details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        UIAlertController *details=[UIAlertController alertControllerWithTitle:@"Details" message:self->_startupFailure?:(self->_error?:self->_installation.error).localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [details addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:details animated:YES completion:nil];
    }]];
    [self presentSheet:sheet anchor:nil];
}
- (void)openAddons {
    TKWoWAddonViewController *addonVC=[[TKWoWAddonViewController alloc] initWithLibrary:_library selectedProduct:_product];
    __weak typeof(self) weakSelf=self;
    addonVC.onProductChanged=^(NSDictionary *newProduct) {
        [weakSelf selectProduct:newProduct];
    };
    addonVC.onAddonsChanged=^{
        [weakSelf render];
    };
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:addonVC];
    nav.modalPresentationStyle=UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)promptForAPIKey {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"CurseForge API Key"
        message:@"Enter your CurseForge Core API key for searching and downloading add-ons. You can also specify CURSEFORGE_API_KEY in local.env."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder=@"Paste API Key here";
        field.text=[TKWoWAddonManager apiKey];
        field.autocapitalizationType=UITextAutocapitalizationTypeNone;
        field.autocorrectionType=UITextAutocorrectionTypeNo;
        field.clearButtonMode=UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        UITextField *field=alert.textFields.firstObject;
        [TKWoWAddonManager setApiKey:field.text];
        [self render];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (UILabel *)startupStatusLabel { [self loadViewIfNeeded]; return _detailLabel; }
- (void)beginStartup {
    [self loadViewIfNeeded];
    [self cancel]; _starting=YES; _startupFailure=nil;
    _detailLabel.text=@"Preparing to launch. Keep this app open.";
    _diagnosticsButton.hidden=YES;
    [self render]; [_launchProgress start];
    [self.view layoutIfNeeded];
}
- (void)finishStartupWithMessage:(NSString *)message failed:(BOOL)failed {
    _starting=NO; _startupFailure=failed?message:nil;
    [_launchProgress stop]; _diagnosticsButton.hidden=!failed;
    [self render];
}
- (void)diagnostics { if (self.showDiagnostics) self.showDiagnostics(); }
- (void)about {
    UIViewController *controller=[UIViewController new]; controller.title=@"About";
    controller.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UITextView *text=[UITextView new]; text.editable=NO;
    text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; text.adjustsFontForContentSizeCategory=YES;
    text.textContainerInset=UIEdgeInsetsMake(20,20,20,20);
    NSMutableString *credits=[@"Wolkara — an independent World of Warcraft launcher built on Tolkara. Not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft belongs to Blizzard Entertainment.\n\n" mutableCopy];
    for (NSString *name in @[@"LICENSE",@"NOTICE.md"]) {
        NSString *path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name];
        NSString *notice=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (notice) [credits appendFormat:@"%@\n%@\n\n",name,notice];
    }
    text.text=credits; controller.view=text;
    [self.navigationController pushViewController:controller animated:YES];
}
@end
