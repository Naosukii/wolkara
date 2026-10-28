#import "AddonViewController.h"
#import "AddonManager.h"
#import "BackupManager.h"
#import "Manifest.h"

static UIColor *Gold(void) { return [UIColor colorWithRed:0.88 green:0.73 blue:0.43 alpha:1]; }
static UIColor *Muted(void) { return [UIColor colorWithRed:0.66 green:0.72 blue:0.78 alpha:1]; }
static UIColor *CardBg(void) { return [UIColor colorWithRed:0.07 green:0.105 blue:0.15 alpha:1]; }
static UIColor *DarkBg(void) { return [UIColor colorWithRed:0.025 green:0.045 blue:0.075 alpha:1]; }

@interface TKWoWAddonCell : UITableViewCell
@property(nonatomic, strong) UIImageView *iconImageView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@property(nonatomic, strong) UILabel *summaryLabel;
@property(nonatomic, strong) UIButton *actionButton;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation TKWoWAddonCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = CardBg();
    card.layer.cornerRadius = 12;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [Gold() colorWithAlphaComponent:0.18].CGColor;
    [self.contentView addSubview:card];

    _iconImageView = [UIImageView new];
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    _iconImageView.layer.cornerRadius = 8;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.tintColor = Gold();
    [card addSubview:_iconImageView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    _titleLabel.textColor = Gold();
    _titleLabel.numberOfLines = 1;
    [card addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = Muted();
    _subtitleLabel.numberOfLines = 1;
    [card addSubview:_subtitleLabel];

    _summaryLabel = [UILabel new];
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _summaryLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _summaryLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    _summaryLabel.numberOfLines = 2;
    [card addSubview:_summaryLabel];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_actionButton];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.color = Gold();
    _spinner.hidesWhenStopped = YES;
    [card addSubview:_spinner];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        [card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
        [card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [_iconImageView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [_iconImageView.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [_iconImageView.widthAnchor constraintEqualToConstant:44],
        [_iconImageView.heightAnchor constraintEqualToConstant:44],

        [_actionButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [_actionButton.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [_actionButton.widthAnchor constraintGreaterThanOrEqualToConstant:88],
        [_actionButton.heightAnchor constraintEqualToConstant:36],

        [_spinner.centerXAnchor constraintEqualToAnchor:_actionButton.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_actionButton.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:12],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-8],
        [_titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-8],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],

        [_summaryLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_summaryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-8],
        [_summaryLabel.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:4],
        [_summaryLabel.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-10]
    ]];

    return self;
}
@end

@interface TKWoWAddonViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@end

@implementation TKWoWAddonViewController {
    TKAppLibrary *_library;
    NSDictionary *_product;
    TKWoWAddonManager *_manager;

    UIButton *_editionButton;
    UISegmentedControl *_tabSegment;
    UISearchBar *_searchBar;
    UIView *_apiKeyBanner;
    UITableView *_tableView;
    UIActivityIndicatorView *_loadingIndicator;
    UILabel *_emptyLabel;

    NSArray<NSDictionary *> *_installedAddons;
    NSArray<NSDictionary *> *_searchResults;
    NSMutableSet<NSNumber *> *_installingModIds;
    NSMutableDictionary<NSNumber *, NSDictionary *> *_availableUpdatesByModId;
    NSCache<NSString *, UIImage *> *_imageCache;
    BOOL _isSearching;
}

- (instancetype)initWithLibrary:(nullable TKAppLibrary *)library selectedProduct:(NSDictionary *)product {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _library = library;
    _product = product ?: TKWoWProducts()[0];
    _manager = [TKWoWAddonManager new];
    _installingModIds = [NSMutableSet new];
    _availableUpdatesByModId = [NSMutableDictionary new];
    _imageCache = [NSCache new];
    self.title = @"ADD-ON MANAGER";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = DarkBg();

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                             style:UIBarButtonItemStyleDone
                                                                            target:self
                                                                            action:@selector(dismissAction)];
    self.navigationItem.leftBarButtonItem.tintColor = Gold();

    UIBarButtonItem *keyItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"key.fill"]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(promptForAPIKey)];
    keyItem.tintColor = Gold();
    keyItem.accessibilityLabel = @"CurseForge API Key";

    UIBarButtonItem *backupItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.doc"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(backupMenu:)];
    backupItem.tintColor = Gold();
    backupItem.accessibilityLabel = @"Backup and Restore";
    self.navigationItem.rightBarButtonItems = @[keyItem, backupItem];

    [self buildHeaderView];
    [self buildTableView];
    [self reloadInstalledAddons];
}

- (void)backupMenu:(UIBarButtonItem *)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"WTF & Add-ons Backup"
                                                                   message:@"Export or restore your keybindings, macros, and interface configurations."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Export Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [TKWoWBackupManager presentExportForProduct:self->_product library:self->_library fromViewController:self anchorItem:sender];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Import / Restore Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        __weak typeof(self) weakSelf = self;
        [TKWoWBackupManager presentImportForProduct:self->_product library:self->_library fromViewController:self completion:^(BOOL success) {
            if (success) {
                [weakSelf reloadInstalledAddons];
                if (weakSelf.onAddonsChanged) weakSelf.onAddonsChanged();
            }
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.barButtonItem = sender;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)dismissAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)buildHeaderView {
    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = DarkBg();
    [self.view addSubview:header];

    _editionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _editionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_editionButton addTarget:self action:@selector(chooseEdition) forControlEvents:UIControlEventTouchUpInside];
    _editionButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    _editionButton.layer.cornerRadius = 10;
    _editionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [self updateEditionButtonTitle];
    [header addSubview:_editionButton];

    _tabSegment = [[UISegmentedControl alloc] initWithItems:@[@"Installed (0)", @"Search CurseForge"]];
    _tabSegment.translatesAutoresizingMaskIntoConstraints = NO;
    _tabSegment.selectedSegmentIndex = 0;
    _tabSegment.selectedSegmentTintColor = Gold();
    [_tabSegment setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.08 green:0.065 blue:0.035 alpha:1],
                                          NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightBold]}
                               forState:UIControlStateSelected];
    [_tabSegment setTitleTextAttributes:@{NSForegroundColorAttributeName: Muted(),
                                          NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]}
                               forState:UIControlStateNormal];
    [_tabSegment addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:_tabSegment];

    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.placeholder = @"Search CurseForge add-ons (e.g. Details, Bagnon)…";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.barStyle = UIBarStyleBlack;
    _searchBar.tintColor = Gold();
    _searchBar.delegate = self;
    _searchBar.hidden = YES;
    [header addSubview:_searchBar];

    // API Key Prompt Banner
    _apiKeyBanner = [UIView new];
    _apiKeyBanner.translatesAutoresizingMaskIntoConstraints = NO;
    _apiKeyBanner.backgroundColor = CardBg();
    _apiKeyBanner.layer.cornerRadius = 10;
    _apiKeyBanner.layer.borderWidth = 1;
    _apiKeyBanner.layer.borderColor = [Gold() colorWithAlphaComponent:0.4].CGColor;
    _apiKeyBanner.hidden = YES;

    UILabel *bannerTitle = [UILabel new];
    bannerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    bannerTitle.text = @"🔑 CurseForge API Key Required";
    bannerTitle.textColor = Gold();
    bannerTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [_apiKeyBanner addSubview:bannerTitle];

    UILabel *bannerSubtitle = [UILabel new];
    bannerSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    bannerSubtitle.text = @"Tap here to enter your CurseForge Core API key for searching and downloading.";
    bannerSubtitle.textColor = Muted();
    bannerSubtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    bannerSubtitle.numberOfLines = 0;
    [_apiKeyBanner addSubview:bannerSubtitle];

    UITapGestureRecognizer *bannerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(promptForAPIKey)];
    [_apiKeyBanner addGestureRecognizer:bannerTap];
    [header addSubview:_apiKeyBanner];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_editionButton.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
        [_editionButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [_editionButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [_editionButton.heightAnchor constraintEqualToConstant:40],

        [_tabSegment.topAnchor constraintEqualToAnchor:_editionButton.bottomAnchor constant:10],
        [_tabSegment.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [_tabSegment.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [_tabSegment.heightAnchor constraintEqualToConstant:34],

        [_searchBar.topAnchor constraintEqualToAnchor:_tabSegment.bottomAnchor constant:6],
        [_searchBar.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10],
        [_searchBar.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [_searchBar.heightAnchor constraintEqualToConstant:44],

        [_apiKeyBanner.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:4],
        [_apiKeyBanner.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [_apiKeyBanner.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [_apiKeyBanner.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-6],

        [bannerTitle.topAnchor constraintEqualToAnchor:_apiKeyBanner.topAnchor constant:8],
        [bannerTitle.leadingAnchor constraintEqualToAnchor:_apiKeyBanner.leadingAnchor constant:12],
        [bannerTitle.trailingAnchor constraintEqualToAnchor:_apiKeyBanner.trailingAnchor constant:-12],

        [bannerSubtitle.topAnchor constraintEqualToAnchor:bannerTitle.bottomAnchor constant:2],
        [bannerSubtitle.leadingAnchor constraintEqualToAnchor:_apiKeyBanner.leadingAnchor constant:12],
        [bannerSubtitle.trailingAnchor constraintEqualToAnchor:_apiKeyBanner.trailingAnchor constant:-12],
        [bannerSubtitle.bottomAnchor constraintEqualToAnchor:_apiKeyBanner.bottomAnchor constant:-8]
    ]];
}

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:TKWoWAddonCell.class forCellReuseIdentifier:@"AddonCell"];
    [self.view addSubview:_tableView];

    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingIndicator.color = Gold();
    _loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:_loadingIndicator];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.textColor = Muted();
    _emptyLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    UIView *header = self.view.subviews[0];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_loadingIndicator.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_loadingIndicator.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32]
    ]];
}

- (void)updateEditionButtonTitle {
    NSString *title = [NSString stringWithFormat:@"Edition: %@  ▾", _product[@"name"] ?: @"World of Warcraft"];
    UIButtonConfiguration *config = UIButtonConfiguration.plainButtonConfiguration;
    config.title = title;
    config.baseForegroundColor = Gold();
    config.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
    _editionButton.configuration = config;
}

- (void)chooseEdition {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Select WoW Edition"
                                                                   message:@"Add-ons will be managed for the selected client."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *prod in TKWoWProducts()) {
        [sheet addAction:[UIAlertAction actionWithTitle:prod[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            self->_product = prod;
            [self updateEditionButtonTitle];
            [self reloadInstalledAddons];
            if (self->_tabSegment.selectedSegmentIndex == 1 && self->_searchBar.text.length > 0) {
                [self executeSearch:self->_searchBar.text];
            }
            if (self.onProductChanged) self.onProductChanged(prod);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _editionButton;
    sheet.popoverPresentationController.sourceRect = _editionButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tabChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0) {
        _searchBar.hidden = YES;
        _apiKeyBanner.hidden = YES;
        [_searchBar resignFirstResponder];
        [self reloadInstalledAddons];
    } else {
        _searchBar.hidden = NO;
        _apiKeyBanner.hidden = [TKWoWAddonManager hasApiKey];
        if (![TKWoWAddonManager hasApiKey]) {
            _searchResults = @[];
            [_tableView reloadData];
            _emptyLabel.text = @"CurseForge API Key is required to search add-ons.\nTap the banner above or key icon in the navigation bar.";
            _emptyLabel.hidden = NO;
        } else if (_searchResults.count == 0) {
            // Automatically perform an initial popular search
            [self executeSearch:_searchBar.text];
        } else {
            [_tableView reloadData];
            _emptyLabel.hidden = YES;
        }
    }
}

- (void)reloadInstalledAddons {
    _installedAddons = [TKWoWAddonManager installedAddonsForProduct:_product library:_library];
    [_tabSegment setTitle:[NSString stringWithFormat:@"Installed (%lu)", (unsigned long)_installedAddons.count] forSegmentAtIndex:0];
    if (_tabSegment.selectedSegmentIndex == 0) {
        [_tableView reloadData];
        if (_installedAddons.count == 0) {
            _emptyLabel.text = [NSString stringWithFormat:@"No add-ons installed for %@.\nSwitch to 'Search CurseForge' to browse and install.", _product[@"name"]];
            _emptyLabel.hidden = NO;
        } else {
            _emptyLabel.hidden = YES;
        }
    }
    [self checkForUpdates];
}

- (void)checkForUpdates {
    if (![TKWoWAddonManager hasApiKey]) return;
    NSDictionary *currentProd = _product;
    [_manager checkForUpdatesForProduct:currentProd library:_library completion:^(NSArray<NSDictionary *> *updates, NSError *error) {
        (void)error;
        if (![self->_product[@"id"] isEqual:currentProd[@"id"]]) return;
        [self->_availableUpdatesByModId removeAllObjects];
        for (NSDictionary *u in updates ?: @[]) {
            NSNumber *mId = u[@"modId"];
            if (mId) self->_availableUpdatesByModId[mId] = u;
        }
        if (self->_tabSegment.selectedSegmentIndex == 0) {
            [self->_tableView reloadData];
        }
    }];
}

- (void)executeSearch:(NSString *)query {
    if (![TKWoWAddonManager hasApiKey]) {
        _apiKeyBanner.hidden = NO;
        return;
    }
    _apiKeyBanner.hidden = YES;
    _emptyLabel.hidden = YES;
    [_loadingIndicator startAnimating];

    [_manager searchAddonsWithQuery:query product:_product completion:^(NSArray<NSDictionary *> *results, NSError *error) {
        [self->_loadingIndicator stopAnimating];
        if (error) {
            self->_emptyLabel.text = [NSString stringWithFormat:@"Error loading add-ons:\n%@", error.localizedDescription];
            self->_emptyLabel.hidden = NO;
            self->_searchResults = @[];
        } else {
            self->_searchResults = results ?: @[];
            if (self->_searchResults.count == 0) {
                self->_emptyLabel.text = @"No add-ons found matching your search.";
                self->_emptyLabel.hidden = NO;
            } else {
                self->_emptyLabel.hidden = YES;
            }
        }
        [self->_tableView reloadData];
    }];
}

- (void)promptForAPIKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CurseForge API Key"
                                                                   message:@"Enter your CurseForge Core API key for searching and installing add-ons. You can also define CURSEFORGE_API_KEY in local.env."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Paste API Key here";
        field.text = [TKWoWAddonManager apiKey];
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        UITextField *field = alert.textFields.firstObject;
        [TKWoWAddonManager setApiKey:field.text];
        self->_apiKeyBanner.hidden = [TKWoWAddonManager hasApiKey];
        if (self->_tabSegment.selectedSegmentIndex == 1) {
            [self executeSearch:self->_searchBar.text];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self executeSearch:searchBar.text];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        [self executeSearch:@""];
    }
}

#pragma mark - UITableViewDataSource & UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return (_tabSegment.selectedSegmentIndex == 0) ? _installedAddons.count : _searchResults.count;
}

- (NSDictionary *)installedRecordForModId:(NSNumber *)modId name:(NSString *)name {
    for (NSDictionary *item in _installedAddons) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSNumber *itemId = TKSafeNumber(item[@"id"], nil);
        NSString *itemName = TKSafeString(item[@"name"], nil);
        if (modId && [modId isKindOfClass:NSNumber.class] && modId.integerValue != 0 && [itemId isEqual:modId]) return item;
        if (name && [name isKindOfClass:NSString.class] && name.length > 0 && [itemName isEqual:name]) return item;
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TKWoWAddonCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AddonCell" forIndexPath:indexPath];
    BOOL isInstalledTab = (_tabSegment.selectedSegmentIndex == 0);
    NSDictionary *addon = isInstalledTab ? _installedAddons[indexPath.row] : _searchResults[indexPath.row];

    NSNumber *modId = TKSafeNumber(addon[@"id"], @(0));
    NSString *name = TKSafeString(addon[@"displayName"], TKSafeString(addon[@"name"], @""));
    NSString *summary = TKSafeString(addon[@"summary"], @"");
    NSString *version = TKSafeString(addon[@"version"], @"");
    NSString *author = TKSafeString(addon[@"author"], @"");
    if (author.length == 0) {
        NSArray *authors = addon[@"authors"];
        if ([authors isKindOfClass:NSArray.class] && authors.count > 0) {
            NSDictionary *firstAuth = authors[0];
            if ([firstAuth isKindOfClass:NSDictionary.class]) {
                author = TKSafeString(firstAuth[@"name"], @"");
            }
        }
    }

    cell.titleLabel.text = name.length ? name : @"Untitled Add-on";
    cell.summaryLabel.text = summary.length ? summary : @"No description available.";
    if (version.length && author.length) {
        cell.subtitleLabel.text = [NSString stringWithFormat:@"%@ · by %@", version, author];
    } else if (version.length) {
        cell.subtitleLabel.text = version;
    } else if (author.length) {
        cell.subtitleLabel.text = [NSString stringWithFormat:@"by %@", author];
    } else {
        cell.subtitleLabel.text = @"";
    }

    // Default icon
    cell.iconImageView.image = [UIImage systemImageNamed:@"puzzlepiece.extension.fill"];

    // Asynchronously load thumbnail if available
    NSString *iconUrl = nil;
    if ([addon[@"iconUrl"] isKindOfClass:NSString.class]) {
        iconUrl = addon[@"iconUrl"];
    } else {
        NSDictionary *logo = addon[@"logo"];
        if ([logo isKindOfClass:NSDictionary.class]) {
            id thumb = logo[@"thumbnailUrl"];
            id full = logo[@"url"];
            if ([thumb isKindOfClass:NSString.class]) iconUrl = thumb;
            else if ([full isKindOfClass:NSString.class]) iconUrl = full;
        }
    }
    if (iconUrl.length > 0) {
        UIImage *cached = [_imageCache objectForKey:iconUrl];
        if (cached) {
            cell.iconImageView.image = cached;
        } else {
            NSURL *url = [NSURL URLWithString:iconUrl];
            if (url) {
                __weak typeof(cell) weakCell = cell;
                NSURLSessionDataTask *imgTask = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                    (void)resp; (void)err;
                    if (data) {
                        UIImage *img = [UIImage imageWithData:data];
                        if (img) {
                            [self->_imageCache setObject:img forKey:iconUrl];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if ([weakCell.titleLabel.text isEqual:name]) {
                                    weakCell.iconImageView.image = img;
                                }
                            });
                        }
                    }
                }];
                [imgTask resume];
            }
        }
    }

    BOOL isInstalling = modId && modId.integerValue != 0 && [_installingModIds containsObject:modId];
    if (isInstalling) {
        cell.actionButton.hidden = YES;
        [cell.spinner startAnimating];
    } else {
        [cell.spinner stopAnimating];
        cell.actionButton.hidden = NO;

        NSDictionary *installedRecord = [self installedRecordForModId:modId name:name];
        BOOL installed = isInstalledTab || (installedRecord != nil);
        NSDictionary *updateInfo = (modId && modId.integerValue != 0) ? _availableUpdatesByModId[modId] : nil;

        UIButtonConfiguration *btnConfig;
        if (updateInfo) {
            btnConfig = UIButtonConfiguration.filledButtonConfiguration;
            btnConfig.title = @"Update";
            btnConfig.baseBackgroundColor = Gold();
            btnConfig.baseForegroundColor = [UIColor colorWithRed:0.08 green:0.065 blue:0.035 alpha:1];
        } else if (installed) {
            btnConfig = UIButtonConfiguration.tintedButtonConfiguration;
            btnConfig.title = @"Uninstall";
            btnConfig.baseBackgroundColor = [UIColor colorWithRed:0.95 green:0.3 blue:0.3 alpha:0.18];
            btnConfig.baseForegroundColor = [UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1];
        } else {
            btnConfig = UIButtonConfiguration.filledButtonConfiguration;
            btnConfig.title = @"Install";
            btnConfig.baseBackgroundColor = Gold();
            btnConfig.baseForegroundColor = [UIColor colorWithRed:0.08 green:0.065 blue:0.035 alpha:1];
        }
        btnConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        cell.actionButton.configuration = btnConfig;

        [cell.actionButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        cell.actionButton.tag = indexPath.row;
        if (updateInfo) {
            [cell.actionButton addTarget:self action:@selector(updateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        } else if (installed) {
            [cell.actionButton addTarget:self action:@selector(uninstallButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        } else {
            [cell.actionButton addTarget:self action:@selector(installButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL isInstalledTab = (_tabSegment.selectedSegmentIndex == 0);
    NSArray *list = isInstalledTab ? _installedAddons : _searchResults;
    if (indexPath.row >= (NSInteger)list.count) return;
    NSDictionary *addon = list[indexPath.row];
    [self showAddonDetails:addon];
}

- (void)showAddonDetails:(NSDictionary *)addon {
    NSString *name = TKSafeString(addon[@"displayName"], TKSafeString(addon[@"name"], @"Add-on"));
    NSString *summary = TKSafeString(addon[@"summary"], @"");
    NSNumber *modId = TKSafeNumber(addon[@"id"], @(0));

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name
                                                                   message:summary
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSDictionary *updateInfo = (modId && modId.integerValue != 0) ? _availableUpdatesByModId[modId] : nil;
    if (updateInfo) {
        NSString *updateTitle = [NSString stringWithFormat:@"Update to %@", updateInfo[@"updateVersion"] ?: @"latest"];
        [sheet addAction:[UIAlertAction actionWithTitle:updateTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            [self performInstall:updateInfo[@"addon"] file:updateInfo[@"updateFile"]];
        }]];
    }

    NSDictionary *installed = [self installedRecordForModId:modId name:name];
    if (installed) {
        NSArray *folders = installed[@"folders"];
        NSString *folderList = [folders isKindOfClass:NSArray.class] ? [folders componentsJoinedByString:@", "] : @"";
        if (folderList.length > 0) {
            sheet.message = [NSString stringWithFormat:@"%@\n\nFolders: %@", summary, folderList];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Uninstall" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            (void)action;
            [self confirmUninstall:installed];
        }]];
    }

    if (modId && modId.integerValue != 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Choose Version to Install…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            [self chooseVersionAndInstall:addon];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)updateButtonTapped:(UIButton *)sender {
    BOOL isInstalledTab = (_tabSegment.selectedSegmentIndex == 0);
    NSArray *list = isInstalledTab ? _installedAddons : _searchResults;
    if (sender.tag < 0 || sender.tag >= (NSInteger)list.count) return;
    NSDictionary *addon = list[sender.tag];
    NSNumber *modId = TKSafeNumber(addon[@"id"], nil);
    NSDictionary *updateInfo = (modId && modId.integerValue != 0) ? _availableUpdatesByModId[modId] : nil;
    if (updateInfo) {
        [self performInstall:updateInfo[@"addon"] file:updateInfo[@"updateFile"]];
    }
}

- (void)installButtonTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)_searchResults.count) return;
    NSDictionary *addon = _searchResults[sender.tag];
    [self performInstall:addon file:nil];
}

- (void)uninstallButtonTapped:(UIButton *)sender {
    BOOL isInstalledTab = (_tabSegment.selectedSegmentIndex == 0);
    NSArray *list = isInstalledTab ? _installedAddons : _searchResults;
    if (sender.tag < 0 || sender.tag >= (NSInteger)list.count) return;
    NSDictionary *target = list[sender.tag];
    NSDictionary *addon = isInstalledTab ? target : [self installedRecordForModId:target[@"id"] name:target[@"name"]];
    if (addon) [self confirmUninstall:addon];
}

- (void)confirmUninstall:(NSDictionary *)addon {
    NSString *name = TKSafeString(addon[@"displayName"], TKSafeString(addon[@"name"], @"this add-on"));
    NSString *prodName = TKSafeString(_product[@"name"], @"this game edition");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Uninstall %@", name]
                                                                   message:[NSString stringWithFormat:@"Are you sure you want to remove %@ from %@?", name, prodName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Uninstall" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action;
        NSError *err = nil;
        if ([TKWoWAddonManager uninstallAddon:addon forProduct:self->_product library:self->_library error:&err]) {
            [self reloadInstalledAddons];
            if (self.onAddonsChanged) self.onAddonsChanged();
        } else {
            UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Uninstall Failed"
                                                                               message:err.localizedDescription
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:errAlert animated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseVersionAndInstall:(NSDictionary *)addon {
    NSNumber *modId = TKSafeNumber(addon[@"id"], @(0));
    if (!modId || modId.integerValue == 0) return;
    [_loadingIndicator startAnimating];

    [_manager fetchFilesForModId:modId completion:^(NSArray<NSDictionary *> *files, NSError *error) {
        [self->_loadingIndicator stopAnimating];
        if (error || files.count == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Files Available"
                                                                           message:error.localizedDescription ?: @"Could not retrieve file list from CurseForge."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }

        NSString *prodName = TKSafeString(self->_product[@"name"], @"this edition");
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Select Version to Install"
                                                                        message:[NSString stringWithFormat:@"Choose a file compatible with %@", prodName]
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSDictionary *file in files) {
            if (![file isKindOfClass:NSDictionary.class]) continue;
            BOOL matches = [TKWoWAddonManager file:file matchesProduct:self->_product[@"id"]];
            NSString *fileDisp = TKSafeString(file[@"displayName"], TKSafeString(file[@"fileName"], @"Version"));
            NSArray *gv = [file[@"gameVersions"] isKindOfClass:NSArray.class] ? file[@"gameVersions"] : @[];
            NSString *verList = [gv componentsJoinedByString:@", "];
            NSString *title = [NSString stringWithFormat:@"%@%@ (%@)",
                               matches ? @"★ " : @"",
                               fileDisp,
                               verList.length ? verList : @"Any"];
            [picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                (void)a;
                [self performInstall:addon file:file];
            }]];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        picker.popoverPresentationController.sourceView = self.view;
        picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
        [self presentViewController:picker animated:YES completion:nil];
    }];
}

- (void)performInstall:(NSDictionary *)addon file:(nullable NSDictionary *)file {
    NSNumber *modId = TKSafeNumber(addon[@"id"], nil);
    if (modId && modId.integerValue != 0) {
        [_installingModIds addObject:modId];
        [_availableUpdatesByModId removeObjectForKey:modId];
    }
    [_tableView reloadData];

    [_manager installAddon:addon file:file product:_product library:_library progress:nil completion:^(BOOL success, NSError *error) {
        if (modId) [self->_installingModIds removeObject:modId];
        [self reloadInstalledAddons];
        if (self.onAddonsChanged) self.onAddonsChanged();

        if (!success && error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Installation Failed"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

@end
