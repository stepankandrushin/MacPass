//
//  MPTestExpirationTimer.m
//  MacPassTests
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

#import <XCTest/XCTest.h>
#import <KeePassKit/KeePassKit.h>

/* A time info is marked expired at its expiration date, and one that is no longer used is freed before that date, by
 KPKTimeInfo+MPExpirationTimer.m */
@interface MPTestExpirationTimer : XCTestCase
@end

@implementation MPTestExpirationTimer

- (KPKTree *)_treeWithEntryExpiringAt:(NSDate *)date {
  KPKTree *tree = [[KPKTree alloc] init];
  tree.root = [[KPKGroup alloc] init];
  KPKEntry *entry = [[KPKEntry alloc] init];
  entry.title = @"expiring";
  [entry addToGroup:tree.root];
  entry.timeInfo.expirationDate = date;
  entry.timeInfo.expires = YES;
  [entry pushHistory]; // a history item keeps the expiration too, and is copied with the entry
  return tree;
}

/* Each merge copies the tree several times. KeePassKit's timer held each copy of an expiring time info until its
 expiration date, and every later copy went through all of them. */
- (void)testCopiesOfAnExpiringEntryAreFreed {
  KPKTree *tree = [self _treeWithEntryExpiringAt:[NSDate dateWithTimeIntervalSinceNow:3600]];
  NSPointerArray *copies = NSPointerArray.weakObjectsPointerArray;
  @autoreleasepool {
    for(NSUInteger index = 0; index < 5; index++) {
      KPKTree *copy = [tree copy];
      KPKEntry *entry = copy.allEntries.firstObject;
      XCTAssertTrue(entry.timeInfo.expires);
      [copies addPointer:(__bridge void *)entry.timeInfo];
      [copies addPointer:(__bridge void *)entry.history.firstObject.timeInfo];
    }
  }
  XCTAssertEqual(copies.count, 10);
  for(NSUInteger index = 0; index < copies.count; index++) {
    XCTAssertNil((__bridge id)[copies pointerAtIndex:index], @"copy %lu of a time info is still held", (unsigned long)index);
  }
}

- (void)testAnEntryIsMarkedExpiredAtItsExpirationDate {
  KPKTree *tree = [self _treeWithEntryExpiringAt:[NSDate dateWithTimeIntervalSinceNow:0.5]];
  KPKTimeInfo *timeInfo = tree.allEntries.firstObject.timeInfo;
  KPKTimeInfo *copied = [[tree copy] allEntries].firstObject.timeInfo;
  XCTAssertFalse(timeInfo.isExpired);
  XCTAssertFalse(copied.isExpired);
  [self keyValueObservingExpectationForObject:timeInfo keyPath:@"isExpired" expectedValue:@YES];
  [self keyValueObservingExpectationForObject:copied keyPath:@"isExpired" expectedValue:@YES];
  [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testAnEntryThatNoLongerExpiresIsNotMarkedExpired {
  KPKTree *tree = [self _treeWithEntryExpiringAt:[NSDate dateWithTimeIntervalSinceNow:0.3]];
  KPKTimeInfo *timeInfo = tree.allEntries.firstObject.timeInfo;
  timeInfo.expires = NO;
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
  XCTAssertFalse(timeInfo.isExpired);
}

- (void)testAPastDateMarksAnEntryExpiredAtOnceAndALaterOneUnmarksIt {
  KPKTree *tree = [self _treeWithEntryExpiringAt:[NSDate dateWithTimeIntervalSinceNow:-60]];
  KPKTimeInfo *timeInfo = tree.allEntries.firstObject.timeInfo;
  XCTAssertTrue(timeInfo.isExpired);
  timeInfo.expirationDate = [NSDate dateWithTimeIntervalSinceNow:3600];
  XCTAssertFalse(timeInfo.isExpired);
}

@end
