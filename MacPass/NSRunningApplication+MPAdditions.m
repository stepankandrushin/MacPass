//
//  NSRunningApplication+MPAdditions.m
//  MacPass
//
//  Created by Michael Starke on 15.01.20.
//  Copyright © 2020 HicknHack Software GmbH. All rights reserved.
//

#import "NSRunningApplication+MPAdditions.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

NSString *const MPWindowIDKey = @"MPWindowIDKey";
NSString *const MPWindowTitleKey = @"MPWindowTitleKey";
NSString *const MPWindowURLKey = @"MPWindowURLKey";
NSString *const MPProcessIdentifierKey = @"MPProcessIdentifierKey";

BOOL skipWindowTitle(NSString *windowTitle) {
  if(windowTitle.length <= 0) {
    return YES;
  }
  
  static NSSet *titlesToSkip;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    titlesToSkip = [NSSet setWithArray:@[@"Item-0", @"Focus Proxy"]];
  });
  
  return [titlesToSkip containsObject:windowTitle];
}

static id copyAccessibilityValue(AXUIElementRef element, CFStringRef attribute) {
  CFTypeRef value = NULL;
  AXError error = AXUIElementCopyAttributeValue(element, attribute, &value);
  id result = CFBridgingRelease(value);
  return error == kAXErrorSuccess ? result : nil;
}

/* Title and document URL of the focused window, keyed by MPWindowTitleKey and MPWindowURLKey */
static NSDictionary *focusedAccessibilityWindowInfo(pid_t pid) {
  if(!AXIsProcessTrusted()) {
    return nil;
  }

  AXUIElementRef application = AXUIElementCreateApplication(pid);
  // An unresponsive target must not stall the global shortcut indefinitely.
  AXUIElementSetMessagingTimeout(application, 0.5);
  id window = copyAccessibilityValue(application, kAXFocusedWindowAttribute);
  CFRelease(application);
  if(!window || CFGetTypeID((__bridge CFTypeRef)window) != AXUIElementGetTypeID()) {
    return nil;
  }

  AXUIElementRef windowElement = (__bridge AXUIElementRef)window;
  AXUIElementSetMessagingTimeout(windowElement, 0.5);
  NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
  id title = copyAccessibilityValue(windowElement, kAXTitleAttribute);
  if([title isKindOfClass:NSString.class]) {
    info[MPWindowTitleKey] = title;
  }
  /* Chrome publishes the URL of the active tab as the window's document. A document without
   a host, like the file of a text editor window, is of no use for matching. */
  id document = copyAccessibilityValue(windowElement, kAXDocumentAttribute);
  NSURL *url = [document isKindOfClass:NSURL.class] ? document : nil;
  if([document isKindOfClass:NSString.class]) {
    url = [NSURL URLWithString:document];
  }
  if(url.host.length > 0) {
    info[MPWindowURLKey] = url.absoluteString;
  }
  return info;
}

@implementation NSRunningApplication (MPAdditions)

- (NSDictionary *)mp_infoDictionary {
  NSArray *currentWindows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListExcludeDesktopElements, kCGNullWindowID));
  NSArray *windowNumbers = [NSWindow windowNumbersWithOptions:NSWindowNumberListAllApplications];
  /* Owner, layer and number of a window are available without Screen Recording permission,
   its name (kCGWindowName) is not. So pick the topmost normal window by z-order and keep the
   topmost named window only as a fallback for the title. */
  NSUInteger topZIndex = NSNotFound;
  NSUInteger namedZIndex = NSNotFound;
  NSNumber *topWindowId;
  NSNumber *namedWindowId;
  NSString *namedWindowTitle;
  for(NSDictionary *windowDict in currentWindows) {
    NSNumber *processId = windowDict[(NSString *)kCGWindowOwnerPID];
    if(!processId || ![processId isEqualToNumber:@(self.processIdentifier)]) {
      continue;
    }
    NSNumber *windowId = (NSNumber *)windowDict[(NSString *)kCGWindowNumber];
    NSUInteger zIndex = [windowNumbers indexOfObject:windowId];
    if(zIndex == NSNotFound) {
      continue;
    }
    if([windowDict[(NSString *)kCGWindowLayer] integerValue] == 0 && zIndex < topZIndex) {
      topZIndex = zIndex;
      topWindowId = windowId;
    }
    NSString *windowTitle = windowDict[(NSString *)kCGWindowName];
    /* skip a list of well know useless window-titles */
    if(!skipWindowTitle(windowTitle) && zIndex < namedZIndex) {
      namedZIndex = zIndex;
      namedWindowId = windowId;
      namedWindowTitle = windowTitle;
    }
  }

  // Chrome hands an ellipsized copy of long titles to the window server, which can
  // cut out the hostname used for Auto-Type matching. Accessibility exposes the full
  // focused window title and the URL of the page it shows, and needs no Screen Recording.
  // Fall back to the window server's title when the target exposes no usable one.
  NSDictionary *accessibilityInfo = focusedAccessibilityWindowInfo(self.processIdentifier);
  NSString *title = accessibilityInfo[MPWindowTitleKey];
  NSNumber *windowId = topWindowId ?: namedWindowId;
  if(skipWindowTitle(title)) {
    title = namedWindowTitle;
    windowId = namedWindowId;
  }
  if(!title) {
    if(currentWindows.count > 0) {
      NSLog(@"Unable to retrieve a window title. MacPass needs the Accessibility permission, or the Screen Recording permission for apps that do not expose their window titles through Accessibility.");
    }
    return @{};
  }

  NSMutableDictionary *infoDict = [[NSMutableDictionary alloc] init];
  infoDict[MPWindowTitleKey] = title;
  infoDict[MPProcessIdentifierKey] = @(self.processIdentifier);
  infoDict[MPWindowIDKey] = windowId;
  infoDict[MPWindowURLKey] = accessibilityInfo[MPWindowURLKey];
  return infoDict;
}

@end
