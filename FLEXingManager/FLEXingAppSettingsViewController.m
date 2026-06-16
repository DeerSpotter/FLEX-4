//
//  FLEXingAppSettingsViewController.m
//  FLEXingManager
//

#import "FLEXingAppSettingsViewController.h"
#import "../Shared/FLEXingConfig.h"

static NSString * const FLEXingAppNameKey = @"name";
static NSString * const FLEXingAppBundleIDKey = @"bundleIdentifier";
static NSString * const FLEXingAppPathKey = @"path";

@interface FLEXingAppSettingsViewController ()
@property (nonatomic, copy) NSDictionary *applicationInfo;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *autoShowSwitch;
@property (nonatomic, strong) UITextView *adjustmentsTextView;
@end

@implementation FLEXingAppSettingsViewController

- (instancetype)initWithApplicationInfo:(NSDictionary *)applicationInfo running:(BOOL)running {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _applicationInfo = [applicationInfo copy];
        _running = running;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.applicationInfo[FLEXingAppNameKey] ?: @"App";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveSettings)];

    NSString *bundleIdentifier = self.applicationInfo[FLEXingAppBundleIDKey];

    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.on = FLEXingIsBundleEnabled(bundleIdentifier);

    self.autoShowSwitch = [[UISwitch alloc] init];
    self.autoShowSwitch.on = FLEXingShouldAutoShowBundle(bundleIdentifier);

    self.adjustmentsTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.adjustmentsTextView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.adjustmentsTextView.text = FLEXingAdjustmentsForBundle(bundleIdentifier);
    self.adjustmentsTextView.backgroundColor = UIColor.clearColor;
    self.adjustmentsTextView.scrollEnabled = YES;
}

- (void)saveSettings {
    NSString *bundleIdentifier = self.applicationInfo[FLEXingAppBundleIDKey];
    BOOL saved = FLEXingSaveSettingsForBundle(bundleIdentifier, self.enabledSwitch.isOn, self.autoShowSwitch.isOn, self.adjustmentsTextView.text ?: @"");

    NSString *title = saved ? @"Saved" : @"Could Not Save";
    NSString *message = saved ? @"Restart the target app to load this FLEXing profile." : @"The preferences file could not be written.";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (saved) {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : (section == 1 ? 2 : 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Application";
    }
    if (section == 1) {
        return @"FLEX launch";
    }
    return @"Saved adjustments";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"Enabled apps load FLEX on next launch. Auto Show opens the FLEX browser automatically instead of only installing gestures.";
    }
    if (section == 2) {
        return @"Use this field to store notes, selectors, class names, offsets, or adjustment details you want available next time this app starts.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = indexPath.section == 2 ? @"TextViewCell" : @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        UITableViewCellStyle style = indexPath.section == 0 ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1;
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 2;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = self.applicationInfo[FLEXingAppNameKey] ?: @"Unknown";
            cell.detailTextLabel.text = self.applicationInfo[FLEXingAppBundleIDKey] ?: @"";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = self.running ? @"Running" : @"Not running";
            cell.detailTextLabel.text = self.running ? @"Detected in process list" : @"Enable then restart app";
        } else {
            cell.textLabel.text = @"Path";
            cell.detailTextLabel.text = self.applicationInfo[FLEXingAppPathKey] ?: @"";
        }
        return cell;
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Enable FLEX";
            cell.detailTextLabel.text = @"";
            cell.accessoryView = self.enabledSwitch;
        } else {
            cell.textLabel.text = @"Auto Show FLEX";
            cell.detailTextLabel.text = @"";
            cell.accessoryView = self.autoShowSwitch;
        }
        return cell;
    }

    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }

    self.adjustmentsTextView.frame = CGRectInset(cell.contentView.bounds, 12.0, 8.0);
    self.adjustmentsTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cell.contentView addSubview:self.adjustmentsTextView];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        return 180.0;
    }
    if (indexPath.section == 0 && indexPath.row == 2) {
        return 74.0;
    }
    return 52.0;
}

@end
