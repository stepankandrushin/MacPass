//
//  MPAutotypeDoctor.m
//  MacPass
//
//  Created by Michael Starke on 03.07.19.
//  Copyright © 2019 HicknHack Software GmbH. All rights reserved.
//

#import "MPAutotypeDoctor.h"
#import "MPSettingsHelper.h"
#import "NSApplication+MPAdditions.h"
#import "MPAutotypeDoctorReportViewController.h"
#import "NSError+Messages.h"


@interface MPReportItem : NSObject

@property (copy) NSString *statusDescription;
@property (copy) NSString *label;
@property (copy) NSString *actionLabel;
@property BOOL isOK;
@property (weak) id target;

@end

@implementation MPReportItem

- (instancetype)init {
  self = [super init];
  if(self) {
    _isOK = NO;
  }
  return self;
}

@end


@interface MPAutotypeDoctor () <NSWindowDelegate>
@property (strong) NSWindow *reportWindow;
@end

@implementation MPAutotypeDoctor

+ (MPAutotypeDoctor *)defaultDoctor {
  static MPAutotypeDoctor *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[MPAutotypeDoctor alloc] init];
  });
  return instance;
}

- (BOOL)hasNecessaryAutotypePermissions {
  /* Window titles and URLs are read through Accessibility, which also sends the keys */
  return [self hasAccessibiltyPermissions:NULL];
}

- (BOOL)hasAccessibiltyPermissions:(NSError *__autoreleasing*)error {
  BOOL isTrusted = YES;
  /* macOS 10.13 and lower allows us to send key events regardless of accessibilty trust */
  if(@available(macOS 10.14, *)) {
    isTrusted = AXIsProcessTrusted();
    if(!isTrusted && error) {
      *error = [NSError errorInDomain:MPAutotypeErrorDomain withCode:MPErrorAutotypeIsMissingAccessibiltyPermissions description:NSLocalizedString(@"ERROR_NO_ACCESSIBILITY_PERMISSIONS", "Error description for missing accessibility permissions")];
    }
  }
  return isTrusted;
}

- (void)openAccessibiltyPreferences {
  [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (void)openAutomationPreferences {
  [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"]];
}

- (void)runChecksAndPresentResults {
  if(!self.reportWindow) {
    self.reportWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    self.reportWindow.releasedWhenClosed = NO;
    self.reportWindow.title = NSLocalizedString(@"AUTOTYPE_DOCTOR_RESULTS_WINDOW_TITLE", @"Window title for the stand-alone password creator window");
    self.reportWindow.delegate = self;
  }
  MPAutotypeDoctorReportViewController *vc = [[MPAutotypeDoctorReportViewController alloc] init];
  self.reportWindow.contentViewController = vc;
  
  [self.reportWindow center];
  [self.reportWindow makeKeyAndOrderFront:vc];
}

- (void)windowWillClose:(NSNotification *)notification {
  if(notification.object == self.reportWindow) {
    self.reportWindow = nil;
  }
}

@end
