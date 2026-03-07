#import "BrowserTabOverviewController.h"

#import "BrowserTabViewModel.h"
#import "BrowserViewModel.h"

static CGFloat const kTopBarHorizontalInset = 40.0;
static CGFloat const kTopBarMaxWidth = 1760.0;
static CGFloat const kTopBarHeight = 86.0;
static CGFloat const kTabOverviewPanelTopInset = 120.0;
static CGFloat const kTabOverviewPanelBottomInset = 88.0;
static CGFloat const kTabOverviewPanelSideInset = 54.0;
static CGFloat const kTabOverviewHeaderTopInset = 34.0;
static CGFloat const kTabOverviewTitleHeight = 64.0;
static CGFloat const kTabOverviewSubtitleTop = 94.0;
static CGFloat const kTabOverviewSubtitleHeight = 36.0;
static CGFloat const kTabOverviewContentTopInset = 166.0;
static CGFloat const kTabOverviewFooterHeight = 28.0;
static CGFloat const kTabCardWidth = 584.0;
static CGFloat const kTabCardHeight = 535.0;
static CGFloat const kTabCardThumbnailHeight = 347.0;
static CGFloat const kTabCardSpacing = 50.4;
static CGFloat const kTabCardGlowInset = 18.0;
static CGFloat const kTabCardTitleTop = 369.0;
static CGFloat const kTabCardTitleHeight = 36.0;
static CGFloat const kTabCardURLTop = 409.0;
static CGFloat const kTabCardURLHeight = 64.0;

@class BrowserTabOverviewViewController;

@interface BrowserTopAlignedLabel : UILabel
@end

@implementation BrowserTopAlignedLabel

- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines {
    CGRect textRect = [super textRectForBounds:bounds limitedToNumberOfLines:numberOfLines];
    textRect.origin.y = bounds.origin.y;
    return textRect;
}

- (void)drawTextInRect:(CGRect)rect {
    CGRect textRect = [self textRectForBounds:rect limitedToNumberOfLines:self.numberOfLines];
    [super drawTextInRect:textRect];
}

@end

@interface BrowserTabOverviewController ()

@property (nonatomic, weak) id<BrowserTabOverviewControllerHost> host;
@property (nonatomic) BrowserViewModel *viewModel;
@property (nonatomic, readwrite, getter=isVisible) BOOL visible;
@property (nonatomic) BOOL cursorModeBeforeShowing;
@property (nonatomic, weak) BrowserTabOverviewViewController *presentedOverviewViewController;

- (NSInteger)numberOfDisplayItems;
- (NSInteger)activeTabDisplayItemIndex;
- (nullable BrowserTabViewModel *)tabForDisplayItemIndex:(NSInteger)displayItemIndex;
- (void)handleSelectionForDisplayItemIndex:(NSInteger)displayItemIndex;
- (void)handleCloseRequestForDisplayItemIndex:(NSInteger)displayItemIndex;
- (void)handleAlternateAction;
- (void)reloadPresentedOverviewIfNeeded;
- (void)overviewViewControllerDidDisappear:(BrowserTabOverviewViewController *)viewController;

@end

@interface BrowserTabOverviewCollectionViewCell : UICollectionViewCell

- (void)configureAsAddCard;
- (void)configureWithTab:(BrowserTabViewModel *)tab activeTab:(BOOL)activeTab;

@end

@interface BrowserTabOverviewCollectionViewCell ()

@property (nonatomic) UIView *cardBackgroundView;
@property (nonatomic) UIImageView *thumbnailView;
@property (nonatomic) UIView *addIconBackdropView;
@property (nonatomic) UIImageView *addIconView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *urlLabel;
@property (nonatomic) UILabel *hintLabel;
@property (nonatomic) BOOL addCard;
@property (nonatomic) BOOL activeTab;

@end

@implementation BrowserTabOverviewCollectionViewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;

        _cardBackgroundView = [[UIView alloc] initWithFrame:self.contentView.bounds];
        _cardBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _cardBackgroundView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
        _cardBackgroundView.layer.cornerRadius = 30.0;
        _cardBackgroundView.clipsToBounds = YES;
        [self.contentView addSubview:_cardBackgroundView];

        _thumbnailView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, kTabCardWidth, kTabCardThumbnailHeight)];
        _thumbnailView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        [_cardBackgroundView addSubview:_thumbnailView];

        _addIconBackdropView = [[UIView alloc] initWithFrame:CGRectMake((kTabCardWidth - 144.0) / 2.0, (kTabCardHeight - 144.0) / 2.0, 144.0, 144.0)];
        _addIconBackdropView.backgroundColor = UIColor.clearColor;
        _addIconBackdropView.hidden = YES;
        [_cardBackgroundView addSubview:_addIconBackdropView];

        _addIconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"plus"]];
        _addIconView.frame = CGRectMake(12.0, 12.0, 120.0, 120.0);
        _addIconView.contentMode = UIViewContentModeScaleAspectFit;
        [_addIconBackdropView addSubview:_addIconView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(30.0, kTabCardTitleTop, kTabCardWidth - 60.0, kTabCardTitleHeight)];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        [_cardBackgroundView addSubview:_titleLabel];

        _urlLabel = [[BrowserTopAlignedLabel alloc] initWithFrame:CGRectMake(30.0, kTabCardURLTop, kTabCardWidth - 60.0, kTabCardURLHeight)];
        _urlLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        _urlLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _urlLabel.numberOfLines = 2;
        [_cardBackgroundView addSubview:_urlLabel];

        _hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(30.0, kTabCardHeight - 44.0, kTabCardWidth - 60.0, 24.0)];
        _hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.58];
        _hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _hintLabel.textAlignment = NSTextAlignmentRight;
        _hintLabel.hidden = YES;
        [_cardBackgroundView addSubview:_hintLabel];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.transform = CGAffineTransformIdentity;
}

- (void)configureAsAddCard {
    self.addCard = YES;
    self.activeTab = NO;
    self.thumbnailView.hidden = YES;
    self.thumbnailView.image = nil;
    self.addIconBackdropView.hidden = NO;
    self.titleLabel.text = @"New Tab";
    self.urlLabel.text = @"Open the home page";
    self.hintLabel.hidden = YES;
    [self updateAppearance];
}

- (void)configureWithTab:(BrowserTabViewModel *)tab activeTab:(BOOL)activeTab {
    self.addCard = NO;
    self.activeTab = activeTab;
    self.thumbnailView.hidden = NO;
    self.thumbnailView.image = tab.snapshotImage;
    self.addIconBackdropView.hidden = YES;
    self.titleLabel.text = tab.title.length > 0 ? tab.title : @"New Tab";
    self.urlLabel.text = tab.URLString.length > 0 ? tab.URLString : @"Home page";
    self.hintLabel.text = @"Play/Pause to Close";
    self.hintLabel.hidden = !self.isFocused;
    [self updateAppearance];
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        [self updateAppearance];
    } completion:nil];
}

- (void)updateAppearance {
    BOOL focused = self.isFocused;
    self.cardBackgroundView.backgroundColor = self.addCard
        ? [UIColor colorWithWhite:focused ? 0.20 : 0.16 alpha:1.0]
        : [UIColor colorWithWhite:(self.activeTab ? 0.18 : 0.14) alpha:1.0];

    self.layer.shadowColor = [UIColor colorWithRed:0.23 green:0.57 blue:1.0 alpha:1.0].CGColor;
    self.layer.shadowOffset = CGSizeZero;
    self.layer.shadowOpacity = (focused || self.activeTab) ? 0.78 : 0.0;
    self.layer.shadowRadius = focused ? 18.0 : 12.0;
    self.transform = focused ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
    self.hintLabel.hidden = self.addCard || !focused;
}

@end

@interface BrowserTabOverviewViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

- (instancetype)initWithOverviewController:(BrowserTabOverviewController *)overviewController;
- (void)reload;
- (void)updateCardAtTabIndex:(NSInteger)tabIndex;
- (void)handleAlternateAction;

@end

@interface BrowserTabOverviewViewController ()

@property (nonatomic, weak) BrowserTabOverviewController *overviewController;
@property (nonatomic) UIView *dimView;
@property (nonatomic) UIVisualEffectView *panelView;
@property (nonatomic) UICollectionView *collectionView;
@property (nonatomic) UILabel *footerLabel;
@property (nonatomic) NSInteger preferredFocusItemIndex;

@end

@implementation BrowserTabOverviewViewController

- (instancetype)initWithOverviewController:(BrowserTabOverviewController *)overviewController {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _overviewController = overviewController;
        _preferredFocusItemIndex = NSNotFound;
        self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (CGFloat)panelWidth {
    CGFloat width = MIN(CGRectGetWidth(self.view.bounds) - (kTopBarHorizontalInset * 2.0), kTopBarMaxWidth);
    return MAX(width, 860.0);
}

- (CGFloat)panelHeight {
    CGFloat maxHeight = CGRectGetHeight(self.view.bounds) - kTabOverviewPanelTopInset - kTabOverviewPanelBottomInset;
    return MAX(maxHeight, 760.0);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    UIView *dimView = [UIView new];
    dimView.translatesAutoresizingMaskIntoConstraints = NO;
    dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    [self.view addSubview:dimView];
    self.dimView = dimView;

    UIVisualEffectView *panelView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    panelView.translatesAutoresizingMaskIntoConstraints = NO;
    panelView.alpha = 0.98;
    panelView.layer.cornerRadius = kTopBarHeight / 2.0;
    panelView.layer.masksToBounds = YES;
    [self.view addSubview:panelView];
    self.panelView = panelView;

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Tabs";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    [panelView.contentView addSubview:titleLabel];

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"Switch tabs, open a new one, or close the focused tab.";
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [panelView.contentView addSubview:subtitleLabel];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = kTabCardSpacing;
    layout.minimumInteritemSpacing = kTabCardSpacing;
    layout.sectionInset = UIEdgeInsetsMake(kTabCardGlowInset, kTabCardGlowInset, kTabCardGlowInset, kTabCardGlowInset);
    layout.itemSize = CGSizeMake(kTabCardWidth, kTabCardHeight);

    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    collectionView.backgroundColor = UIColor.clearColor;
    collectionView.clipsToBounds = NO;
    collectionView.showsHorizontalScrollIndicator = NO;
    collectionView.showsVerticalScrollIndicator = NO;
    collectionView.remembersLastFocusedIndexPath = YES;
    collectionView.dataSource = self;
    collectionView.delegate = self;
    [collectionView registerClass:[BrowserTabOverviewCollectionViewCell class] forCellWithReuseIdentifier:@"TabCard"];
    [panelView.contentView addSubview:collectionView];
    self.collectionView = collectionView;

    UILabel *footerLabel = [UILabel new];
    footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    footerLabel.text = @"Select: Open   Play/Pause: Close Focused Tab   Menu: Dismiss";
    footerLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
    footerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    [panelView.contentView addSubview:footerLabel];
    self.footerLabel = footerLabel;

    CGFloat panelWidth = [self panelWidth];
    CGFloat panelHeight = [self panelHeight];
    [NSLayoutConstraint activateConstraints:@[
        [dimView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dimView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [dimView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [dimView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [panelView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [panelView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:kTabOverviewPanelTopInset],
        [panelView.widthAnchor constraintEqualToConstant:panelWidth],
        [panelView.heightAnchor constraintEqualToConstant:panelHeight],

        [titleLabel.leadingAnchor constraintEqualToAnchor:panelView.contentView.leadingAnchor constant:kTabOverviewPanelSideInset],
        [titleLabel.topAnchor constraintEqualToAnchor:panelView.contentView.topAnchor constant:kTabOverviewHeaderTopInset],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:panelView.contentView.trailingAnchor constant:-kTabOverviewPanelSideInset],
        [titleLabel.heightAnchor constraintEqualToConstant:kTabOverviewTitleHeight],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:panelView.contentView.leadingAnchor constant:kTabOverviewPanelSideInset],
        [subtitleLabel.topAnchor constraintEqualToAnchor:panelView.contentView.topAnchor constant:kTabOverviewSubtitleTop],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:panelView.contentView.trailingAnchor constant:-kTabOverviewPanelSideInset],
        [subtitleLabel.heightAnchor constraintEqualToConstant:kTabOverviewSubtitleHeight],

        [collectionView.leadingAnchor constraintEqualToAnchor:panelView.contentView.leadingAnchor constant:kTabOverviewPanelSideInset],
        [collectionView.trailingAnchor constraintEqualToAnchor:panelView.contentView.trailingAnchor constant:-kTabOverviewPanelSideInset],
        [collectionView.topAnchor constraintEqualToAnchor:panelView.contentView.topAnchor constant:kTabOverviewContentTopInset],
        [collectionView.bottomAnchor constraintEqualToAnchor:footerLabel.topAnchor constant:-18.0],

        [footerLabel.leadingAnchor constraintEqualToAnchor:panelView.contentView.leadingAnchor constant:kTabOverviewPanelSideInset],
        [footerLabel.trailingAnchor constraintEqualToAnchor:panelView.contentView.trailingAnchor constant:-kTabOverviewPanelSideInset],
        [footerLabel.bottomAnchor constraintEqualToAnchor:panelView.contentView.bottomAnchor constant:-24.0],
        [footerLabel.heightAnchor constraintEqualToConstant:kTabOverviewFooterHeight],
    ]];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.overviewController overviewViewControllerDidDisappear:self];
}

- (void)reload {
    NSInteger itemCount = [self.overviewController numberOfDisplayItems];
    if (self.preferredFocusItemIndex == NSNotFound) {
        self.preferredFocusItemIndex = [self currentFocusedItemIndex];
    }
    if (self.preferredFocusItemIndex == NSNotFound) {
        self.preferredFocusItemIndex = [self.overviewController activeTabDisplayItemIndex];
    }
    if (itemCount > 0) {
        self.preferredFocusItemIndex = MIN(MAX(self.preferredFocusItemIndex, 0), itemCount - 1);
    }
    [self.collectionView reloadData];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsFocusUpdate];
        [self updateFocusIfNeeded];
    });
}

- (void)updateCardAtTabIndex:(NSInteger)tabIndex {
    NSInteger itemIndex = tabIndex;
    if (itemIndex < 0 || itemIndex >= self.overviewController.viewModel.tabs.count) {
        [self reload];
        return;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:itemIndex inSection:0];
    if ([[self.collectionView indexPathsForVisibleItems] containsObject:indexPath]) {
        [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
    } else {
        [self.collectionView reloadData];
    }
}

- (void)handleAlternateAction {
    NSInteger focusedItemIndex = [self currentFocusedItemIndex];
    if (focusedItemIndex == NSNotFound || focusedItemIndex >= self.overviewController.viewModel.tabs.count) {
        return;
    }
    self.preferredFocusItemIndex = focusedItemIndex;
    [self.overviewController handleCloseRequestForDisplayItemIndex:focusedItemIndex];
}

- (NSInteger)currentFocusedItemIndex {
    for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        if (cell.isFocused) {
            return indexPath.item;
        }
    }
    return NSNotFound;
}

- (NSInteger)collectionView:(__unused UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return section == 0 ? [self.overviewController numberOfDisplayItems] : 0;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    BrowserTabOverviewCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"TabCard" forIndexPath:indexPath];
    if (indexPath.item == self.overviewController.viewModel.tabs.count) {
        [cell configureAsAddCard];
        return cell;
    }

    BrowserTabViewModel *tab = [self.overviewController tabForDisplayItemIndex:indexPath.item];
    BOOL activeTab = indexPath.item == [self.overviewController activeTabDisplayItemIndex];
    [cell configureWithTab:tab activeTab:activeTab];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    (void)collectionView;
    [self.overviewController handleSelectionForDisplayItemIndex:indexPath.item];
}

- (NSIndexPath *)indexPathForPreferredFocusedViewInCollectionView:(UICollectionView *)collectionView {
    NSInteger itemCount = [self.overviewController numberOfDisplayItems];
    if (itemCount == 0) {
        return nil;
    }
    NSInteger preferredItemIndex = self.preferredFocusItemIndex;
    if (preferredItemIndex == NSNotFound) {
        preferredItemIndex = [self.overviewController activeTabDisplayItemIndex];
    }
    preferredItemIndex = MIN(MAX(preferredItemIndex, 0), itemCount - 1);
    return [NSIndexPath indexPathForItem:preferredItemIndex inSection:0];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return @[self.collectionView];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    UIPress *press = presses.anyObject;
    if (press != nil && press.type == UIPressTypeMenu) {
        [self.overviewController dismiss];
        return;
    }
    if (press != nil && press.type == UIPressTypePlayPause) {
        [self handleAlternateAction];
        return;
    }
    [super pressesEnded:presses withEvent:event];
}

@end

@implementation BrowserTabOverviewController

- (instancetype)initWithHost:(id<BrowserTabOverviewControllerHost>)host
                   viewModel:(BrowserViewModel *)viewModel
                    rootView:(UIView *)rootView
                  topMenuView:(BrowserTopBarView *)topMenuView
                  cursorView:(UIImageView *)cursorView {
    (void)rootView;
    (void)topMenuView;
    (void)cursorView;
    self = [super init];
    if (self) {
        _host = host;
        _viewModel = viewModel;
    }
    return self;
}

- (NSInteger)numberOfDisplayItems {
    return self.viewModel.tabs.count + 1;
}

- (NSInteger)activeTabDisplayItemIndex {
    return self.viewModel.activeTabIndex == NSNotFound ? 0 : self.viewModel.activeTabIndex;
}

- (BrowserTabViewModel *)tabForDisplayItemIndex:(NSInteger)displayItemIndex {
    if (displayItemIndex < 0 || displayItemIndex >= self.viewModel.tabs.count) {
        return nil;
    }
    return self.viewModel.tabs[displayItemIndex];
}

- (void)show {
    if (self.visible) {
        [self reload];
        return;
    }

    self.cursorModeBeforeShowing = [self.host browserTabOverviewControllerCursorModeEnabled];
    self.visible = YES;
    [self.host browserTabOverviewControllerSetCursorModeEnabled:NO];

    BrowserTabOverviewViewController *viewController = [[BrowserTabOverviewViewController alloc] initWithOverviewController:self];
    self.presentedOverviewViewController = viewController;
    [self.host browserTabOverviewControllerPresentViewController:viewController];
}

- (void)dismiss {
    if (!self.visible) {
        return;
    }

    BrowserTabOverviewViewController *viewController = self.presentedOverviewViewController;
    if (viewController == nil) {
        [self overviewViewControllerDidDisappear:nil];
        return;
    }
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)reload {
    [self reloadPresentedOverviewIfNeeded];
}

- (void)updateCardAtIndex:(NSInteger)tabIndex {
    [self.presentedOverviewViewController updateCardAtTabIndex:tabIndex];
}

- (BOOL)containsPoint:(CGPoint)viewPoint {
    (void)viewPoint;
    return NO;
}

- (BOOL)handleSelectionAtPoint:(CGPoint)viewPoint {
    (void)viewPoint;
    return NO;
}

- (void)handleSelectionForDisplayItemIndex:(NSInteger)displayItemIndex {
    if (displayItemIndex >= self.viewModel.tabs.count) {
        BrowserTabOverviewViewController *viewController = self.presentedOverviewViewController;
        if (viewController == nil) {
            [self.host browserTabOverviewControllerCreateNewTabLoadingHomePage:YES];
            return;
        }

        [viewController dismissViewControllerAnimated:YES completion:^{
            [self.host browserTabOverviewControllerCreateNewTabLoadingHomePage:YES];
        }];
        return;
    }

    [self.host browserTabOverviewControllerSwitchToTabAtIndex:displayItemIndex];
    [self dismiss];
}

- (void)handleCloseRequestForDisplayItemIndex:(NSInteger)displayItemIndex {
    NSInteger tabIndex = displayItemIndex;
    if (tabIndex < 0 || tabIndex >= self.viewModel.tabs.count || self.viewModel.tabs.count <= 1) {
        return;
    }

    [self.host browserTabOverviewControllerCloseTabAtIndex:tabIndex];
    [self reloadPresentedOverviewIfNeeded];
}

- (void)handleAlternateAction {
    [self.presentedOverviewViewController handleAlternateAction];
}

- (void)reloadPresentedOverviewIfNeeded {
    [self.presentedOverviewViewController reload];
}

- (void)overviewViewControllerDidDisappear:(BrowserTabOverviewViewController *)viewController {
    if (viewController != nil && viewController != self.presentedOverviewViewController) {
        return;
    }

    self.presentedOverviewViewController = nil;
    if (!self.visible) {
        return;
    }

    self.visible = NO;
    [self.host browserTabOverviewControllerSetCursorModeEnabled:self.cursorModeBeforeShowing];
}

@end
