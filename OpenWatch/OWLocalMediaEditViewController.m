//
//  OWLocalMediaEditViewController.m
//  OpenWatch
//
//  Created by Christopher Ballinger on 12/17/12.
//  Copyright (c) 2012 OpenWatch FPC. All rights reserved.
//

#import "OWLocalMediaEditViewController.h"
#import "OWStrings.h"
#import "OWCaptureAPIClient.h"
#import "OWAccountAPIClient.h"
#import "OWMapAnnotation.h"
#import "OWRecordingController.h"
#import "OWUtilities.h"
#import "OWAppDelegate.h"
#import "OWTag.h"
#import "MBProgressHUD.h"
#import "OWSettingsController.h"
#import "OWLocalMediaController.h"
#import "OWPhoto.h"
#import "OWShareViewController.h"

#define TAGS_ROW 0
#define PADDING 10.0f

@interface OWLocalMediaEditViewController ()

@end

@implementation OWLocalMediaEditViewController
@synthesize titleTextField, whatHappenedLabel, saveButton, uploadProgressView, objectID, scrollView, showingAfterCapture, previewView, characterCountdown, uploadStatusLabel, previewGestureRecognizer, primaryTag, keyboardControls;

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id) init {
    if (self = [super init]) {
        self.title = EDIT_STRING;
        self.view.backgroundColor = [OWUtilities stoneBackgroundPattern];
        [self setupScrollView];
        [self setupFields];
        [self setupWhatHappenedLabel];
        [self setupProgressView];
        [self setupPreviewView];
        
        self.keyboardControls = [[BSKeyboardControls alloc] initWithFields:@[titleTextField]];
        self.keyboardControls.delegate = self;
        
        self.uploadStatusLabel = [[UILabel alloc] init];
        self.uploadStatusLabel.text = ITS_ONLINE_STRING;
        [OWUtilities styleLabel:uploadStatusLabel];
        [self.scrollView addSubview:uploadStatusLabel];
        
        self.characterCountdown = [[OWCharacterCountdownView alloc] initWithFrame:CGRectZero];
        self.showingAfterCapture = NO;
        [self registerForUploadProgressNotifications];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SAVE_STRING style:UIBarButtonItemStyleDone target:self action:@selector(saveButtonPressed:)];
        self.navigationItem.rightBarButtonItem.tintColor = [OWUtilities doneButtonColor];
        
        // Listen for keyboard appearances and disappearances
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillShow:)
                                                     name:UIKeyboardWillShowNotification
                                                   object:self.view.window];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillHide:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:self.view.window];
    }
    return self;
}

- (void) setupPreviewView {
    self.previewView = [[OWPreviewView alloc] init];
    self.previewView.moviePlayer.shouldAutoplay = YES;
}

- (void) setupScrollView {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.delaysContentTouches = NO;
}

- (void) setupWhatHappenedLabel {
    self.whatHappenedLabel = [[UILabel alloc] init];
    self.whatHappenedLabel.text = CAPTION_STRING;
    self.whatHappenedLabel.backgroundColor = [UIColor clearColor];
    self.whatHappenedLabel.font = [UIFont boldSystemFontOfSize:20.0f];
    self.whatHappenedLabel.textColor = [OWUtilities greyTextColor];
    self.whatHappenedLabel.shadowColor = [UIColor lightGrayColor];
    self.whatHappenedLabel.shadowOffset = CGSizeMake(0, 1);
    [self.scrollView addSubview:whatHappenedLabel];
}

- (void) setupProgressView {
    if (uploadProgressView) {
        [uploadProgressView removeFromSuperview];
    }
    self.uploadProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [self.scrollView addSubview:uploadProgressView];
}


- (void) refreshProgressView {
    OWLocalMediaObject *mediaObject = [OWLocalMediaController localMediaObjectForObjectID:self.objectID];
    if ([mediaObject isKindOfClass:[OWLocalRecording class]]) {
        OWLocalRecording *localRecording = (OWLocalRecording*)mediaObject;
        float progress = ((float)[localRecording completedFileCount]) / [localRecording totalFileCount];
        [self.uploadProgressView setProgress:progress animated:YES];
    } else if ([mediaObject isKindOfClass:[OWPhoto class]]){
        OWPhoto *photo = (OWPhoto*)mediaObject;
        if (photo.uploadedValue) {
            [self.uploadProgressView setProgress:1.0f animated:YES];
        } else {
            [self.uploadProgressView setProgress:0.0f animated:YES];
        }
    }
}

- (void) refreshFrames {
    CGFloat padding = PADDING;
    CGFloat contentHeight = 0.0f;
    
    CGFloat titleYOrigin;
    CGFloat itemHeight = 30.0f;
    CGFloat itemWidth = self.view.frame.size.width - padding*2;
    
    CGFloat previewHeight = [OWPreviewView heightForWidth:itemWidth];
    
    self.uploadStatusLabel.frame = CGRectMake(padding, padding, itemWidth, 20.0f);
    
    self.previewView.frame = CGRectMake(padding, [OWUtilities bottomOfView:uploadStatusLabel] + padding, itemWidth, previewHeight);
    
    self.uploadProgressView.frame = CGRectMake(padding, [OWUtilities bottomOfView:previewView] + 5, itemWidth, itemHeight);
    
    CGFloat whatHappenedYOrigin = [OWUtilities bottomOfView:uploadProgressView] + padding;
    self.whatHappenedLabel.frame = CGRectMake(padding,whatHappenedYOrigin, itemWidth, itemHeight);
    titleYOrigin = [OWUtilities bottomOfView:whatHappenedLabel] + padding;
    self.titleTextField.frame = CGRectMake(padding, titleYOrigin, itemWidth, itemHeight);
    self.characterCountdown.frame = CGRectMake(padding, [OWUtilities bottomOfView:titleTextField] + 10, itemWidth, 35);
    contentHeight = [OWUtilities bottomOfView:self.titleTextField] + padding*3;
    self.scrollView.contentSize = CGSizeMake(self.view.frame.size.width, contentHeight);
    self.scrollView.frame = self.view.bounds;
}

- (void) setObjectID:(NSManagedObjectID *)newObjectID {
    objectID = newObjectID;
    
    self.previewView.objectID = objectID;
    
    if (previewView.gestureRecognizer) {
        self.previewGestureRecognizer = [[UIGestureRecognizer alloc] initWithTarget:self action:@selector(togglePreviewFullscreen)];
        previewGestureRecognizer.delegate = self;
        [self.view addGestureRecognizer:previewGestureRecognizer];
    }
    
    [self refreshFields];
    [self refreshFrames];
    [self refreshProgressView];
    [self registerForUploadProgressNotifications];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshFrames];
    [self registerForUploadProgressNotifications];
    [TestFlight passCheckpoint:EDIT_METADATA_CHECKPOINT];
    [self checkRecording];
    if (showingAfterCapture) {
        [self.navigationItem setHidesBackButton:YES];
    }
}


- (void) registerForUploadProgressNotifications {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kOWCaptureAPIClientBandwidthNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedUploadProgressNotification:) name:kOWCaptureAPIClientBandwidthNotification object:nil];
}

- (void) refreshFields {
    OWLocalMediaObject *mediaObject = [OWLocalMediaController localMediaObjectForObjectID:objectID];
    NSString *title = mediaObject.title;
    if (title) {
        self.titleTextField.text = title;
    } else {
        self.titleTextField.text = @"";
    }
    [self.characterCountdown updateText:titleTextField.text];
}

- (void) setPrimaryTag:(NSString *)newPrimaryTag {
    primaryTag = newPrimaryTag;
    self.characterCountdown.maxCharacters = 250-primaryTag.length;
}

- (UITextField*)textFieldWithDefaults {
    UITextField *textField = [[UITextField alloc] init];
    textField.delegate = self;
    textField.autocorrectionType = UITextAutocorrectionTypeDefault;
    textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    textField.returnKeyType = UIReturnKeyDone;
    textField.textColor = [OWUtilities textFieldTextColor];
    textField.borderStyle = UITextBorderStyleRoundedRect;
    return textField;
}

-(void)setupFields {
    if (titleTextField) {
        [titleTextField removeFromSuperview];
    }
    self.titleTextField = [self textFieldWithDefaults];
    self.titleTextField.keyboardType = UIKeyboardTypeTwitter;
    self.titleTextField.placeholder = WHAT_HAPPENED_LABEL_STRING;
    
    [self.scrollView addSubview:titleTextField];
}


- (void) receivedUploadProgressNotification:(NSNotification*)notification {
    [self refreshProgressView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	[self.view addSubview:scrollView];
    [self.scrollView addSubview:characterCountdown];
    [self.scrollView addSubview:previewView];
}

- (BOOL) checkFields {
    if (self.titleTextField.text.length > 2) {
        return YES;
    }
    return NO;
}

- (void) saveButtonPressed:(id)sender {
    OWLocalMediaObject *mediaObject = [OWLocalMediaController localMediaObjectForObjectID:self.objectID];
    NSManagedObjectContext *context = [NSManagedObjectContext MR_contextForCurrentThread];
    
    NSMutableString *finalTitleString = [[NSMutableString alloc] init];
    NSString *initialTitleString = self.titleTextField.text;
    int tagLength = primaryTag.length;
    
    // define the range you're interested in
    NSRange stringRange = {0, MIN([initialTitleString length], self.characterCountdown.maxCharacters-tagLength)};
    
    // adjust the range to include dependent chars
    stringRange = [initialTitleString rangeOfComposedCharacterSequencesForRange:stringRange];
    
    // Now you can create the short string
    NSString *shortString = [initialTitleString substringWithRange:stringRange];
    [finalTitleString appendString:shortString];
    if (primaryTag) {
        [finalTitleString appendFormat:@" #%@", primaryTag];
    }
    
    NSString *trimmedText = [finalTitleString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    mediaObject.title = trimmedText;
    [context MR_saveToPersistentStoreAndWait];    
    
    [[OWAccountAPIClient sharedClient] postObjectWithUUID:mediaObject.uuid objectClass:[mediaObject class] success:nil failure:nil retryCount:kOWAccountAPIClientDefaultRetryCount];
    
    [self.view endEditing:YES];
    
    if (showingAfterCapture) {
        OWShareViewController *shareView = [[OWShareViewController alloc] init];
        shareView.mediaObject = mediaObject;
        [self.navigationController pushViewController:shareView animated:YES];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void) checkRecording {
    if (showingAfterCapture) {
        [self refreshFields];
        return;
    }
    OWLocalMediaObject *mediaObject = [OWLocalMediaController localMediaObjectForObjectID:self.objectID];

    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    [[OWAccountAPIClient sharedClient] getObjectWithUUID:mediaObject.uuid objectClass:mediaObject.class success:^(NSManagedObjectID *objectID) {
        [self refreshFields];
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    } failure:^(NSString *reason) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    } retryCount:kOWAccountAPIClientDefaultRetryCount];
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

- (void) textFieldDidBeginEditing:(UITextField *)textField {
    [self.scrollView setContentOffset:CGPointMake(0, titleTextField.frame.origin.y - PADDING) animated:YES];
    [self.keyboardControls setActiveField:textField];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *newText = [NSString stringWithFormat:@"%@%@", textField.text, string];
    BOOL shouldChangeCharacters = [self.characterCountdown updateText:newText];
    if (!shouldChangeCharacters && string.length == 0) {
        return YES;
    }
    return shouldChangeCharacters;
}


- (void)keyboardWillShow: (NSNotification *) notif{}

- (void)keyboardWillHide: (NSNotification *) notif {
    [self.scrollView setContentOffset:CGPointZero animated:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(NSUInteger) supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (void) togglePreviewFullscreen {
    // moved to delegate method because this isn't firing for some reason
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)newGestureRecognizer shouldReceiveTouch:(UITouch *)touch;
{
    BOOL shouldReceiveTouch = YES;
    
    if (newGestureRecognizer == previewGestureRecognizer) {
        shouldReceiveTouch = (touch.view == self.previewView);
    }
    
    if (shouldReceiveTouch) {
        [self.previewView toggleFullscreen];
    }
    
    return shouldReceiveTouch;
}

- (void)keyboardControlsDonePressed:(BSKeyboardControls *)keyControls
{
    [keyControls.activeField resignFirstResponder];
}

@end
