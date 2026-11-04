//
//  MPDatabaseCreation.m
//  MacPass
//
//  Created by Michael Starke on 10.07.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <KeePassKit/KeePassKit.h>

#import "MPDocument.h"
#import "MPConstants.h"
#import "MPSettingsHelper.h"

@interface MPTestDocument : XCTestCase

@property (strong) NSURL *folder;
@property (strong) KPKCompositeKey *key;

@end

/* What a change on disk and an unlock lead to once on the main queue, which a test does not drain. */
@interface MPDocument (MPTestMerging)
- (void)_mergeChangesOnDisk;
@end

@implementation MPTestDocument

- (void)setUp {
  [super setUp];
  self.folder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:self.folder withIntermediateDirectories:YES attributes:nil error:nil];
  self.key = [[KPKCompositeKey alloc] init];
  [self.key addKey:[KPKKey keyWithPassword:@"test"]];
  [NSUserDefaults.standardUserDefaults registerDefaults:@{ kMPSettingsKeyFileChangeStrategy: @(MPFileChangeStrategyMerge) }];
}

- (void)tearDown {
  [NSFileManager.defaultManager removeItemAtURL:self.folder error:nil];
  [super tearDown];
}

- (NSURL *)_url:(NSString *)name {
  return [self.folder URLByAppendingPathComponent:name];
}

/* As a sync tool puts another device's version in place: a new file renamed over the old one, a second later. */
- (void)_write:(KPKTree *)tree to:(NSURL *)url {
  NSError *error;
  NSData *data = [tree encryptWithKey:self.key format:KPKDatabaseFormatKdbx error:&error];
  XCTAssertNotNil(data, @"%@", error);
  NSDate *previous = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil].fileModificationDate;
  XCTAssertTrue([data writeToURL:url options:NSDataWritingAtomic error:&error], @"%@", error);
  NSDate *date = [(previous ?: NSDate.date) dateByAddingTimeInterval:1];
  [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: date } ofItemAtPath:url.path error:nil];
}

- (void)_sync:(NSURL *)from to:(NSURL *)to {
  NSURL *temporary = [to URLByAppendingPathExtension:@"arriving"];
  XCTAssertTrue([NSFileManager.defaultManager copyItemAtURL:from toURL:temporary error:nil]);
  XCTAssertTrue([NSFileManager.defaultManager replaceItemAtURL:to withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:nil]);
}

- (KPKTree *)_read:(NSURL *)url {
  NSError *error;
  KPKTree *tree = [[KPKTree alloc] initWithContentsOfUrl:url key:self.key error:&error];
  XCTAssertNotNil(tree, @"%@", error);
  return tree;
}

- (KPKEntry *)_add:(NSString *)title to:(KPKTree *)tree {
  return [self _add:title toGroup:tree.root];
}

- (KPKEntry *)_add:(NSString *)title toGroup:(KPKGroup *)group {
  KPKEntry *entry = [[KPKEntry alloc] init];
  entry.title = title;
  [entry addToGroup:group];
  return entry;
}

/* A group below the root group, where a database keeps most of its entries. */
- (KPKGroup *)_addGroup:(NSString *)title to:(KPKTree *)tree {
  KPKGroup *group = [[KPKGroup alloc] init];
  group.title = title;
  [group addToGroup:tree.root];
  return group;
}

- (BOOL)_tree:(KPKTree *)tree has:(NSString *)title {
  for(KPKEntry *entry in tree.allEntries) {
    if([entry.title isEqualToString:title]) {
      return YES;
    }
  }
  return NO;
}

- (MPDocument *)_open:(NSURL *)url {
  NSError *error;
  MPDocument *document = [[MPDocument alloc] initWithContentsOfURL:url ofType:MPKdbxDocumentUTI error:&error];
  XCTAssertNotNil(document, @"%@", error);
  XCTAssertTrue([document unlockWithPassword:self.key keyFileURL:nil error:&error], @"%@", error);
  return document;
}

- (void)_save:(MPDocument *)document {
  XCTestExpectation *saved = [self expectationWithDescription:@"saved"];
  [document saveToURL:document.fileURL ofType:document.fileType forSaveOperation:NSSaveOperation completionHandler:^(NSError *error) {
    XCTAssertNil(error);
    [saved fulfill];
  }];
  [self waitForExpectationsWithTimeout:10 handler:nil];
}

/* Renames an entry as the inspector does, keeping the version before the change in its history. */
- (void)_rename:(KPKEntry *)entry to:(NSString *)title {
  [entry pushHistory];
  entry.title = title;
}

/* As autosave writes a document in place. */
- (void)_autosave:(MPDocument *)document {
  XCTestExpectation *saved = [self expectationWithDescription:@"autosaved"];
  [document saveToURL:document.fileURL ofType:document.fileType forSaveOperation:NSAutosaveInPlaceOperation completionHandler:^(NSError *error) {
    XCTAssertNil(error);
    [saved fulfill];
  }];
  [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)_edit:(MPDocument *)document adding:(NSString *)title {
  [self _add:title to:document.tree];
  [document updateChangeCount:NSChangeDone];
}

/* Two devices with the database open, each saving in turn: each merges the other's save and is clean afterwards,
 so neither saves it again and sends it back. */
- (void)testTwoDevicesTakeEachOthersChangesWithoutSendingThemBack {
  NSURL *here = [self _url:@"here.kdbx"];
  NSURL *there = [self _url:@"there.kdbx"];
  KPKTree *start = [[KPKTree alloc] initWithTemplateContents];
  [self _write:start to:here];
  [self _sync:here to:there];
  MPDocument *mine = [self _open:here];
  MPDocument *theirs = [self _open:there];

  [self _edit:mine adding:@"Made here"];
  [self _save:mine];
  [self _sync:here to:there];
  [theirs mergeWithContentsFromURL:there key:theirs.compositeKey];
  XCTAssertTrue([self _tree:theirs.tree has:@"Made here"]);
  XCTAssertFalse(theirs.documentEdited, @"A merge that brings only the other device's change leaves nothing to save");

  [self _edit:theirs adding:@"Made there"];
  [self _save:theirs];
  [self _sync:there to:here];
  [mine mergeWithContentsFromURL:here key:mine.compositeKey];
  XCTAssertTrue([self _tree:mine.tree has:@"Made there"]);
  XCTAssertTrue([self _tree:mine.tree has:@"Made here"]);
  XCTAssertFalse(mine.documentEdited);
  for(KPKEntry *entry in mine.tree.allEntries) {
    XCTAssertEqual(entry.history.count, 0, @"%@ was changed nowhere, so it has no older version", entry.title);
  }
}

/* Another device with an old copy in memory writes it over the file: the entries it lacks are still in this
 document, which is then edited, and its save puts them back. */
- (void)testAFileWrittenOverWithAnOlderVersionGetsBackWhatItLost {
  NSURL *url = [self _url:@"test.kdbx"];
  KPKTree *old = [[KPKTree alloc] initWithTemplateContents];
  KPKTree *current = [old copy];
  [self _add:@"Added later" to:current];
  [self _write:current to:url];
  MPDocument *document = [self _open:url];

  [self _write:old to:url];
  [document mergeWithContentsFromURL:url key:document.compositeKey];
  XCTAssertTrue([self _tree:document.tree has:@"Added later"]);
  XCTAssertTrue(document.documentEdited, @"What the file lost has to be saved again");
  [self _save:document];
  XCTAssertTrue([self _tree:[self _read:url] has:@"Added later"]);
}

/* A save after a change elsewhere it was not told of merges that change in rather than writing over it. */
- (void)testASaveMergesAChangeMadeElsewhereFirst {
  NSURL *url = [self _url:@"test.kdbx"];
  [self _write:[[KPKTree alloc] initWithTemplateContents] to:url];
  MPDocument *document = [self _open:url];
  [self _edit:document adding:@"Not saved yet"];

  KPKTree *elsewhere = [self _read:url];
  [self _add:@"Saved elsewhere" to:elsewhere];
  [self _write:elsewhere to:url];
  [self _save:document];

  KPKTree *saved = [self _read:url];
  XCTAssertTrue([self _tree:saved has:@"Not saved yet"]);
  XCTAssertTrue([self _tree:saved has:@"Saved elsewhere"]);
}

/* A sync tool's conflict copy beside the database is merged once it is unlocked and goes to the Trash once that is
 saved; a file that is no conflict copy of it is left alone, though it opens with the same key. */
- (void)testAConflictCopyIsMergedAndTrashedOnceSaved {
  NSURL *url = [self _url:@"test.kdbx"];
  NSURL *copy = [self _url:@"test (conflict other 2026-11-03).kdbx"];
  NSURL *other = [self _url:@"testing (conflict other 2026-11-03).kdbx"];
  KPKTree *start = [[KPKTree alloc] initWithTemplateContents];
  [self _write:start to:url];
  KPKTree *competing = [start copy];
  [self _add:@"Only in the copy" to:competing];
  [self _write:competing to:copy];
  KPKTree *unrelated = [start copy];
  [self _add:@"Only in another database" to:unrelated];
  [self _write:unrelated to:other];

  MPDocument *document = [self _open:url];
  [document _mergeChangesOnDisk];
  XCTAssertTrue([self _tree:document.tree has:@"Only in the copy"]);
  XCTAssertFalse([self _tree:document.tree has:@"Only in another database"]);
  XCTAssertTrue(document.documentEdited);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:copy.path], @"Kept until the database holds it");

  [self _save:document];
  XCTAssertTrue([self _tree:[self _read:url] has:@"Only in the copy"]);
  XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:copy.path]);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:other.path]);
}

/* The same entry changed on two devices within seconds, as on 2026-11-03: this device saves its change, and a sync tool
 then keeps that save beside the file as a conflict copy and puts the other device's earlier change of the entry in its
 place. The merge keeps the later change, with the other in the entry's history. The file lacks that, so the document is
 left for autosave to write, and the copy stays until a save has written what it held. The entry is in a group, as a
 database keeps them: a change below the root group was taken for none, the document was left clean and the copy
 trashed, so a close or a quit before the next save lost the change. */
- (void)testAChangeToTheSameEntryElsewhereIsMergedAndSaved {
  NSURL *url = [self _url:@"test.kdbx"];
  NSURL *copy = [self _url:@"test (conflicted copy 2026-11-03 225911).kdbx"];
  KPKTree *start = [[KPKTree alloc] initWithTemplateContents];
  KPKEntry *seed = [self _add:@"seed" toGroup:[self _addGroup:@"Test" to:start]];
  seed.timeInfo.modificationDate = [NSDate dateWithTimeIntervalSinceNow:-60];
  [self _write:start to:url];
  KPKTree *elsewhere = [self _read:url];
  MPDocument *document = [self _open:url];

  KPKEntry *theirs = [elsewhere.root entryForUUID:seed.uuid];
  [self _rename:theirs to:@"same-pro"];
  theirs.timeInfo.modificationDate = [NSDate dateWithTimeIntervalSinceNow:-3];
  [self _rename:[document.tree.root entryForUUID:seed.uuid] to:@"same-a1"];
  [document updateChangeCount:NSChangeDone];
  [self _autosave:document];

  XCTAssertTrue([NSFileManager.defaultManager moveItemAtURL:url toURL:copy error:nil]);
  [self _write:elsewhere to:url];
  [document mergeWithContentsFromURL:url key:document.compositeKey];
  XCTAssertEqualObjects([document.tree.root entryForUUID:seed.uuid].title, @"same-a1", @"The later change is kept");
  XCTAssertTrue(document.hasUnautosavedChanges, @"The file lacks the later change, so autosave has to write it");
  XCTAssertTrue(document.documentEdited);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:copy.path], @"Kept until a save has written what it held");

  [self _autosave:document];
  KPKEntry *saved = [[self _read:url].root entryForUUID:seed.uuid];
  XCTAssertEqualObjects(saved.title, @"same-a1");
  XCTAssertTrue([[saved.history valueForKey:@"title"] containsObject:@"same-pro"], @"The earlier change is in the history");
  XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:copy.path]);
  XCTAssertFalse(document.documentEdited);
}

/* Another device with an old copy in memory writes it over the file, and what it lacks is in a group: the document is
 edited, and its save puts it back. */
- (void)testAFileWrittenOverWithAnOlderVersionGetsBackWhatItLostInAGroup {
  NSURL *url = [self _url:@"test.kdbx"];
  KPKTree *old = [[KPKTree alloc] initWithTemplateContents];
  KPKGroup *group = [self _addGroup:@"Test" to:old];
  KPKEntry *changed = [self _add:@"Changed later" toGroup:group];
  changed.timeInfo.modificationDate = [NSDate dateWithTimeIntervalSinceNow:-60];
  KPKTree *current = [old copy];
  [self _add:@"Added later" toGroup:[current.root groupForUUID:group.uuid]];
  KPKEntry *change = [current.root entryForUUID:changed.uuid];
  [self _rename:change to:@"Changed"];
  change.timeInfo.modificationDate = NSDate.date;
  [self _write:current to:url];
  MPDocument *document = [self _open:url];

  [self _write:old to:url];
  [document mergeWithContentsFromURL:url key:document.compositeKey];
  XCTAssertTrue([self _tree:document.tree has:@"Added later"]);
  XCTAssertEqualObjects([document.tree.root entryForUUID:changed.uuid].title, @"Changed");
  XCTAssertTrue(document.hasUnautosavedChanges, @"What the file lost has to be saved again");
  [self _autosave:document];
  KPKTree *saved = [self _read:url];
  XCTAssertTrue([self _tree:saved has:@"Added later"]);
  XCTAssertEqualObjects([saved.root entryForUUID:changed.uuid].title, @"Changed");
}

/* Two devices changing entries in a group in turn, one of them the same entry: each is clean after merging the other's
 save, so neither saves it again and sends it back. */
- (void)testTwoDevicesTakeEachOthersChangesInAGroupWithoutSendingThemBack {
  NSURL *here = [self _url:@"here.kdbx"];
  NSURL *there = [self _url:@"there.kdbx"];
  KPKTree *start = [[KPKTree alloc] initWithTemplateContents];
  KPKGroup *group = [self _addGroup:@"Test" to:start];
  KPKEntry *seed = [self _add:@"seed" toGroup:group];
  seed.timeInfo.modificationDate = [NSDate dateWithTimeIntervalSinceNow:-60];
  [self _write:start to:here];
  [self _sync:here to:there];
  MPDocument *mine = [self _open:here];
  MPDocument *theirs = [self _open:there];

  [self _add:@"Made here" toGroup:[mine.tree.root groupForUUID:group.uuid]];
  [self _rename:[mine.tree.root entryForUUID:seed.uuid] to:@"Renamed here"];
  [mine updateChangeCount:NSChangeDone];
  [self _save:mine];
  [self _sync:here to:there];
  [theirs mergeWithContentsFromURL:there key:theirs.compositeKey];
  XCTAssertTrue([self _tree:theirs.tree has:@"Made here"]);
  XCTAssertEqualObjects([theirs.tree.root entryForUUID:seed.uuid].title, @"Renamed here");
  XCTAssertFalse(theirs.documentEdited, @"A merge that brings only the other device's changes leaves nothing to save");

  [NSThread sleepForTimeInterval:1.1]; // a later change than the last, in the whole seconds a file holds
  [self _add:@"Made there" toGroup:[theirs.tree.root groupForUUID:group.uuid]];
  [self _rename:[theirs.tree.root entryForUUID:seed.uuid] to:@"Renamed there"];
  [theirs updateChangeCount:NSChangeDone];
  [self _save:theirs];
  [self _sync:there to:here];
  [mine mergeWithContentsFromURL:here key:mine.compositeKey];
  XCTAssertTrue([self _tree:mine.tree has:@"Made there"]);
  XCTAssertEqualObjects([mine.tree.root entryForUUID:seed.uuid].title, @"Renamed there");
  XCTAssertFalse(mine.documentEdited);
}

- (void)testCreateEmptyDocument {
  MPDocument *document = [[MPDocument alloc] init];
  XCTAssertNotNil(document, @"Document should be created");
  XCTAssertNil(document.tree, @"Allocated document should not have a tree");
  XCTAssertFalse(document.encrypted, @"Document cannot be encrypted without a tree");
  XCTAssertNil(document.compositeKey, @"Document shoudl have not key at all");
}

- (void)testCreateUntitledDocument {
  MPDocument *document = [[MPDocument alloc] initWithType:@"" error:nil];
  XCTAssertNotNil(document, @"Document should be created");
  KPKFileVersion kdb = { KPKDatabaseFormatKdb, kKPKKdbFileVersion };
  XCTAssertEqual(NSOrderedSame, KPKFileVersionCompare(kdb, document.tree.minimumVersion), @"Tree should be Legacy Version in default case");
  XCTAssertFalse(document.encrypted, @"Document cannot be encrypted at creation");
  XCTAssertFalse(document.compositeKey.hasKeys, @"Document has no Password/Keyfile and thus is not secured");

}

@end
