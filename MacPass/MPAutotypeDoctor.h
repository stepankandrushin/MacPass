//
//  MPAutotypeDoctor.h
//  MacPass
//
//  Created by Michael Starke on 03.07.19.
//  Copyright © 2019 HicknHack Software GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPAutotypeDoctor : NSObject


@property (class, readonly, strong) MPAutotypeDoctor *defaultDoctor;
@property (nonatomic, readonly) BOOL hasNecessaryAutotypePermissions; // MacPass has all the permissions it needs to run autotype on the current system

- (BOOL)hasAccessibiltyPermissions:(NSError *__autoreleasing*)error;

- (void)runChecksAndPresentResults;
- (void)openAccessibiltyPreferences;
- (void)openAutomationPreferences;

@end

NS_ASSUME_NONNULL_END
