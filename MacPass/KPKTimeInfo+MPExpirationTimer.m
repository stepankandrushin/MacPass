//
//  KPKTimeInfo+MPExpirationTimer.m
//  MacPass
//
//  MacPass is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  MacPass is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import <objc/runtime.h>
#import <KeePassKit/KeePassKit.h>

/* In KeePassKit 3.3.2 -[KPKTimeInfo _updateExpireState] marks a time info expired at its expiration date with
 performSelector:afterDelay: and the run loop holds the time info until that date, which may be years away. On every
 change of the expiration it also calls cancelPreviousPerformRequestsWithTarget:selector:object: which goes through
 every delayed perform of the run loop. A copy of the tree, as each merge of another device's save makes several of
 and each save one, thus left a time info per expiring entry and history item behind, and made every later copy
 slower. After ten days with the database open on several Macs MacPass held 14672 timers and a merge kept the main
 thread busy for 20 seconds and more, so clicks and Auto-Type went unanswered. Here each time info has at most one
 timer, which holds it weakly and stops when it is freed. */

/* The private methods of KPKTimeInfo this file relies on. */
@interface KPKTimeInfo (MPExpirationTimerPrivate)
- (void)_updateExpireState;
- (void)setIsExpired:(BOOL)isExpired;
@end

/* Calls -_updateExpireState of a time info at its expiration date, on the main run loop and in every mode, while the
 time info lives. */
@interface MPExpirationTimer : NSObject
- (instancetype)initWithTimeInfo:(KPKTimeInfo *)timeInfo date:(NSDate *)date;
@end

@implementation MPExpirationTimer {
  CFRunLoopTimerRef _timer;
}

- (instancetype)initWithTimeInfo:(KPKTimeInfo *)timeInfo date:(NSDate *)date {
  self = [super init];
  if(self) {
    __weak KPKTimeInfo *weakTimeInfo = timeInfo;
    _timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, date.timeIntervalSinceReferenceDate, 0, 0, 0, ^(CFRunLoopTimerRef timer) {
      [weakTimeInfo _updateExpireState];
    });
    /* CFRunLoopAddTimer and CFRunLoopTimerInvalidate may be called from any thread, as a copy is often made off the
     main thread to be saved */
    CFRunLoopAddTimer(CFRunLoopGetMain(), _timer, kCFRunLoopCommonModes);
  }
  return self;
}

- (void)dealloc {
  CFRunLoopTimerInvalidate(_timer);
  CFRelease(_timer);
}

@end

static const void *MPExpirationTimerKey = &MPExpirationTimerKey;

@implementation KPKTimeInfo (MPExpirationTimer)

+ (void)load {
  Method original = class_getInstanceMethod(self, @selector(_updateExpireState));
  Method replacement = class_getInstanceMethod(self, @selector(mp_updateExpireState));
  if(nil == original || nil == replacement) {
    NSLog(@"KPKTimeInfo lacks -_updateExpireState so expiring entries keep the timers of KeePassKit");
    return;
  }
  method_setImplementation(original, method_getImplementation(replacement));
}

/* What -_updateExpireState of KeePassKit does but with an MPExpirationTimer for the timer. Setting the new timer, or
 none, frees the one set before, which stops it. */
- (void)mp_updateExpireState {
  MPExpirationTimer *timer = nil;
  BOOL expired = NO;
  NSDate *expirationDate = self.expirationDate;
  if(self.expires && nil != expirationDate) {
    if(expirationDate.timeIntervalSinceNow > 0) {
      timer = [[MPExpirationTimer alloc] initWithTimeInfo:self date:expirationDate];
    }
    else {
      expired = YES;
    }
  }
  objc_setAssociatedObject(self, MPExpirationTimerKey, timer, OBJC_ASSOCIATION_RETAIN);
  if(self.isExpired != expired) {
    self.isExpired = expired;
  }
}

@end
