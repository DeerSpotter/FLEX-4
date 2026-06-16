//
//  FLEXingAppDelegate.m
//  FLEXingManager
//

#import "FLEXingAppDelegate.h"
#import "FLEXingRootViewController.h"

@implementation FLEXingAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    FLEXingRootViewController *rootViewController = [[FLEXingRootViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:rootViewController];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
