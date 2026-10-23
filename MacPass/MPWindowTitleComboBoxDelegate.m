//
//  MPWindowTitleMenuDelegate.m
//  MacPass
//
//  Created by Michael Starke on 04/12/14.
//  Copyright (c) 2014 HicknHack Software GmbH. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "MPWindowTitleComboBoxDelegate.h"

#import <ApplicationServices/ApplicationServices.h>

@implementation MPWindowTitleComboBoxDelegate

- (void)comboBoxWillPopUp:(NSNotification *)notification {
  NSComboBox *comboBox = notification.object;
  if(!comboBox) {
    return;
  }
  [comboBox removeAllItems];
  [comboBox addItemsWithObjectValues:[self _currentWindowTitles]];
  comboBox.numberOfVisibleItems = MIN(5, comboBox.numberOfItems);
}

- (NSArray *)_currentWindowTitles {
  /* Window titles of other apps come from Accessibility: the window server only hands them
   to apps with the Screen Recording permission, which MacPass does not ask for */
  NSMutableArray *windowTitles = [[NSMutableArray alloc] init];
  if(!AXIsProcessTrusted()) {
    return windowTitles;
  }
  for(NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
    if(application.activationPolicy != NSApplicationActivationPolicyRegular) {
      continue; // We do not want to insert some system windows (Dock, Menubars)
    }
    AXUIElementRef applicationElement = AXUIElementCreateApplication(application.processIdentifier);
    // An unresponsive app must not stall the popup
    AXUIElementSetMessagingTimeout(applicationElement, 0.2);
    CFTypeRef windows = NULL;
    if(AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute, &windows) == kAXErrorSuccess) {
      for(id window in (__bridge NSArray *)windows) {
        CFTypeRef title = NULL;
        if(AXUIElementCopyAttributeValue((__bridge AXUIElementRef)window, kAXTitleAttribute, &title) == kAXErrorSuccess) {
          NSString *windowTitle = CFBridgingRelease(title);
          if([windowTitle isKindOfClass:NSString.class] && windowTitle.length > 0) {
            [windowTitles addObject:windowTitle];
          }
        }
      }
      CFRelease(windows);
    }
    CFRelease(applicationElement);
  }
  return windowTitles;
}

@end
