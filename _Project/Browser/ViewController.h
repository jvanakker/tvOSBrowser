//
//  ViewController.h
//  Browser
//
//  Created by Steven Troughton-Smith on 20/09/2015.
//  Improved by Jip van Akker on 14/10/2015 through 10/01/2019
//

#import <UIKit/UIKit.h>
#import <GameKit/GameKit.h>

@interface ViewController : GCEventViewController <UIScrollViewDelegate>

@property (nonatomic, retain) IBOutlet UIVisualEffectView *topMenuView;
@property (nonatomic, retain) IBOutlet UIView *browserContainerView;

@property (nonatomic, retain) IBOutlet UIImageView *btnImageBack;
@property (nonatomic, retain) IBOutlet UIImageView *btnImageForward;
@property (nonatomic, retain) IBOutlet UIImageView *btnImageRefresh;
@property (nonatomic, retain) IBOutlet UIImageView *btnImageHome;
@property (nonatomic, retain) IBOutlet UIImageView *btnImageTabs;
@property (nonatomic, retain) IBOutlet UIImageView *btnImageFullScreen;
@property (nonatomic, retain) IBOutlet UIImageView *btnImgMenu;
@property (nonatomic, retain) IBOutlet UILabel     *lblUrlBar;

@property (nonatomic, retain) IBOutlet UIActivityIndicatorView *loadingSpinner;


@end
