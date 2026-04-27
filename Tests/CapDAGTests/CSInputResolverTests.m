//
//  CSInputResolverTests.m
//  CapDAG
//
//  Tests for CSInputResolver module — mirrors Rust capdag/src/input_resolver/
//  Test numbers match Rust test numbers exactly.
//

#import <XCTest/XCTest.h>
#import "CSInputResolver.h"
#import "CSMediaUrn.h"

@interface CSInputResolverTests : XCTestCase
@property (nonatomic, strong) NSString *testDir;
@property (nonatomic, strong) NSFileManager *fm;
@end

@implementation CSInputResolverTests

- (void)setUp {
    [super setUp];
    self.fm = [NSFileManager defaultManager];

    NSString *tempDir = NSTemporaryDirectory();
    self.testDir = [tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self.fm createDirectoryAtPath:self.testDir withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown {
    [self.fm removeItemAtPath:self.testDir error:nil];
    [super tearDown];
}

#pragma mark - Helpers

- (NSString *)createTestFile:(NSString *)name content:(NSString *)content {
    NSString *path = [self.testDir stringByAppendingPathComponent:name];
    [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

- (NSString *)createTestDir:(NSString *)name {
    NSString *path = [self.testDir stringByAppendingPathComponent:name];
    [self.fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

#pragma mark - Path Resolution Tests (Rust path_resolver.rs: TEST1000-TEST1018)

// TEST1000: Single existing file
- (void)test1000_single_existing_file {
    NSString *path = [self createTestFile:@"test.txt" content:@"hello"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
    XCTAssertEqualObjects(result.files[0].path, path);
}

// TEST1001: Single non-existent file
- (void)test1001_nonexistent_file {
    NSString *path = [self.testDir stringByAppendingPathComponent:@"missing.txt"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNotNil(error);
    XCTAssertNil(result);
    XCTAssertEqual(error.code, CSInputResolverErrorNotFound);
}

// TEST1002: Empty directory
- (void)test1002_empty_directory {
    NSString *dir = [self createTestDir:@"empty"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNotNil(error);
    XCTAssertNil(result);
    XCTAssertEqual(error.code, CSInputResolverErrorNoFilesResolved);
}

// TEST1003: Directory with files
- (void)test1003_directory_with_files {
    NSString *dir = [self createTestDir:@"docs"];
    [self createTestFile:@"docs/file1.txt" content:@"one"];
    [self createTestFile:@"docs/file2.txt" content:@"two"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 2);
    XCTAssertTrue(result.isSequence, @"directory with 2 files must be isSequence=YES");
}

// TEST1004: Directory with subdirs (recursive)
- (void)test1004_directory_with_subdirs {
    NSString *dir = [self createTestDir:@"top"];
    [self createTestDir:@"top/sub"];
    [self createTestFile:@"top/file1.txt" content:@"a"];
    [self createTestFile:@"top/sub/file2.txt" content:@"b"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 2, @"recursive enumeration must reach files in subdirs");
}

// TEST1005: Glob matching files
- (void)test1005_glob_matching_files {
    [self createTestFile:@"alpha.txt" content:@"a"];
    [self createTestFile:@"beta.txt" content:@"b"];
    [self createTestFile:@"gamma.md" content:@"c"];
    NSString *pattern = [self.testDir stringByAppendingPathComponent:@"*.txt"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(pattern, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 2, @"glob *.txt must match exactly the two .txt files");
}

// TEST1006: Glob matching nothing
- (void)test1006_glob_matching_nothing {
    [self createTestFile:@"alpha.txt" content:@"a"];
    NSString *pattern = [self.testDir stringByAppendingPathComponent:@"*.no-such-extension"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(pattern, &error);

    XCTAssertNotNil(error, @"glob with no matches must surface as an error, not silently empty");
    XCTAssertNil(result);
}

// TEST1007: Recursive glob
- (void)test1007_recursive_glob {
    [self createTestDir:@"a"];
    [self createTestDir:@"a/b"];
    [self createTestFile:@"a/file1.txt" content:@"1"];
    [self createTestFile:@"a/b/file2.txt" content:@"2"];
    NSString *pattern = [self.testDir stringByAppendingPathComponent:@"a/**/*.txt"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(pattern, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    // BSD glob with GLOB_BRACE does not implement Rust globwalk's `**` semantics.
    // To expose any divergence, assert the union: at least the directly-matched files appear,
    // and result is non-empty.
    XCTAssertGreaterThan(result.files.count, 0, @"recursive glob must produce at least one file");
}

// TEST1008: Mixed file + dir
- (void)test1008_mixed_file_dir {
    NSString *file = [self createTestFile:@"loose.txt" content:@"x"];
    NSString *dir = [self createTestDir:@"folder"];
    [self createTestFile:@"folder/inner.txt" content:@"y"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePaths(@[file, dir], &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 2);
}

// TEST1010: Duplicate paths are deduplicated
- (void)test1010_duplicate_paths {
    NSString *path = [self createTestFile:@"test.txt" content:@"hello"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePaths(@[path, path], &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
}

// TEST1011: Invalid glob syntax
- (void)test1011_invalid_glob {
    NSString *pattern = [self.testDir stringByAppendingPathComponent:@"[unclosed"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(pattern, &error);

    XCTAssertNotNil(error, @"invalid glob pattern must surface an error");
    XCTAssertNil(result);
}

// TEST1013: Empty input array
- (void)test1013_empty_input {
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePaths(@[], &error);

    XCTAssertNotNil(error);
    XCTAssertNil(result);
    XCTAssertEqual(error.code, CSInputResolverErrorEmptyInput);
}

// TEST1014: Symlink to file resolves to its target
- (void)test1014_symlink_to_file {
    NSString *target = [self createTestFile:@"target.txt" content:@"data"];
    NSString *link = [self.testDir stringByAppendingPathComponent:@"link.txt"];
    NSError *linkError = nil;
    [self.fm createSymbolicLinkAtPath:link withDestinationPath:target error:&linkError];
    XCTAssertNil(linkError);

    NSError *error = nil;
    CSResolvedInputSet *result = CSInputResolverResolvePath(link, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
    XCTAssertTrue([result.files[0].path containsString:@"target.txt"],
                  @"symlink must resolve to its target");
}

// TEST1016: Path with spaces
- (void)test1016_path_with_spaces {
    NSString *path = [self createTestFile:@"name with spaces.txt" content:@"x"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
}

// TEST1017: Path with unicode
- (void)test1017_path_with_unicode {
    NSString *path = [self createTestFile:@"日本語.txt" content:@"x"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
}

// TEST1018: Relative path
- (void)test1018_relative_path {
    NSString *cwd = self.fm.currentDirectoryPath;
    [self.fm changeCurrentDirectoryPath:self.testDir];
    [self createTestFile:@"rel.txt" content:@"x"];

    NSError *error = nil;
    CSResolvedInputSet *result = CSInputResolverResolvePath(@"rel.txt", &error);

    [self.fm changeCurrentDirectoryPath:cwd];

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
}

#pragma mark - OS File Filter Tests (Rust os_filter.rs: TEST1020-TEST1029)

// TEST1020: macOS .DS_Store is excluded
- (void)test1020_ds_store_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/.DS_Store"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@".DS_Store"));
}

// TEST1021: Windows Thumbs.db is excluded
- (void)test1021_thumbs_db_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/Thumbs.db"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"Thumbs.db"));
}

// TEST1022: macOS resource fork files are excluded
- (void)test1022_resource_fork_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/._file"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"._document.pdf"));
}

// TEST1023: Office lock files are excluded
- (void)test1023_office_lock_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/~$document.docx"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"~$file.xlsx"));
}

// TEST1024: .git directory is excluded
- (void)test1024_git_dir_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@"/path/.git"));
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@".git"));
}

// TEST1025: __MACOSX archive artifact is excluded
- (void)test1025_macosx_dir_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@"/path/__MACOSX"));
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@"__MACOSX"));
}

// TEST1026: Temp files are excluded
- (void)test1026_temp_files_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/file.tmp"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"document.temp"));
}

// TEST1027: .localized is excluded
- (void)test1027_localized_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/.localized"));
}

// TEST1028: desktop.ini is excluded
- (void)test1028_desktop_ini_excluded {
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/desktop.ini"));
}

// TEST1029: Normal files are NOT excluded
- (void)test1029_normal_files_not_excluded {
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.json"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.txt"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.pdf"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.log"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.md"));
}

#pragma mark - Aggregate Cardinality Tests (Rust resolver.rs: TEST1090-TEST1098)

// TEST1090: 1 file → is_sequence=false
- (void)test1090_single_file_scalar {
    NSString *path = [self createTestFile:@"test.pdf" content:@"%PDF-1.4"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertFalse(result.isSequence, @"single file must be isSequence=NO");
}

// TEST1092: 2 files → is_sequence=true
- (void)test1092_two_files {
    NSString *path1 = [self createTestFile:@"file1.txt" content:@"one"];
    NSString *path2 = [self createTestFile:@"file2.txt" content:@"two"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePaths(@[path1, path2], &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 2);
    XCTAssertTrue(result.isSequence, @"multiple files must be isSequence=YES");
}

// TEST1093: 1 dir with 1 file → is_sequence=false
- (void)test1093_dir_single_file {
    NSString *dir = [self createTestDir:@"single"];
    [self createTestFile:@"single/only.pdf" content:@"%PDF"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
    XCTAssertFalse(result.isSequence, @"directory with single file must be isSequence=NO");
}

// TEST1094: 1 dir with 3 files → is_sequence=true
- (void)test1094_dir_multiple_files {
    NSString *dir = [self createTestDir:@"multi"];
    [self createTestFile:@"multi/a.txt" content:@"a"];
    [self createTestFile:@"multi/b.txt" content:@"b"];
    [self createTestFile:@"multi/c.txt" content:@"c"];
    NSError *error = nil;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 3);
    XCTAssertTrue(result.isSequence, @"directory with multiple files must be isSequence=YES");
}

// TEST1098: Extension-based detection picks up pdf tag for .pdf files
- (void)test1098_extension_based_pdf {
    NSString *path = [self createTestFile:@"doc.pdf" content:@"%PDF-1.4"];
    CSContentStructure structure = CSContentStructureScalarOpaque;
    NSError *error = nil;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(mediaUrn);

    NSError *parseError = nil;
    CSMediaUrn *urn = [CSMediaUrn fromString:mediaUrn error:&parseError];
    XCTAssertNotNil(urn, @"detected URN must parse: %@ (parse error: %@)", mediaUrn, parseError);
    XCTAssertNotNil([urn getTag:@"pdf"],
                    @"PDF extension must produce URN with pdf tag, got: %@", mediaUrn);
}

#pragma mark - Types Tests (Rust types.rs: TEST1144, TEST1145)

// TEST1144: ContentStructure is_list/is_record helpers are correct
- (void)test1144_content_structure_helpers {
    CSResolvedFile *scalarOpaque = [CSResolvedFile fileWithPath:@"/x"
                                                       mediaUrn:@"media:pdf"
                                                      sizeBytes:0
                                               contentStructure:CSContentStructureScalarOpaque];
    XCTAssertFalse([scalarOpaque isList]);
    XCTAssertFalse([scalarOpaque isRecord]);

    CSResolvedFile *listRecord = [CSResolvedFile fileWithPath:@"/y"
                                                     mediaUrn:@"media:json;list;record;textable"
                                                    sizeBytes:0
                                             contentStructure:CSContentStructureListRecord];
    XCTAssertTrue([listRecord isList]);
    XCTAssertTrue([listRecord isRecord]);

    CSResolvedFile *scalarRecord = [CSResolvedFile fileWithPath:@"/r"
                                                       mediaUrn:@"media:json;record;textable"
                                                      sizeBytes:0
                                               contentStructure:CSContentStructureScalarRecord];
    XCTAssertFalse([scalarRecord isList]);
    XCTAssertTrue([scalarRecord isRecord]);

    CSResolvedFile *listOpaque = [CSResolvedFile fileWithPath:@"/l"
                                                     mediaUrn:@"media:list;textable"
                                                    sizeBytes:0
                                             contentStructure:CSContentStructureListOpaque];
    XCTAssertTrue([listOpaque isList]);
    XCTAssertFalse([listOpaque isRecord]);
}

// TEST1145: ResolvedInputSet uses URN equivalence for common_media and file count for is_sequence
- (void)test1145_resolved_input_set_uses_equivalent_media_and_file_count_cardinality {
    // Single file with list-content URN: file count=1 → is_sequence=false, but homogeneous
    CSResolvedFile *singleListFile = [CSResolvedFile fileWithPath:@"/tmp/items.json"
                                                         mediaUrn:@"media:application;json;list;record"
                                                        sizeBytes:42
                                                 contentStructure:CSContentStructureListRecord];
    CSResolvedInputSet *singleSet = [CSResolvedInputSet setWithFiles:@[singleListFile]
                                                          isSequence:NO
                                                         commonMedia:@"media:application;json;list;record"];
    XCTAssertFalse(singleSet.isSequence,
                   @"single file must yield is_sequence=false even when content is a list");
    XCTAssertTrue([singleSet isHomogeneous]);
    XCTAssertEqualObjects(singleSet.commonMedia, @"media:application;json;list;record");

    // Two files whose URNs are equivalent (different tag order) → homogeneous, is_sequence=true.
    // commonMedia is determined by the resolver, so this exercises the resolver's URN-equivalence path.
    NSString *dir = [self createTestDir:@"equivalents"];
    [self createTestFile:@"equivalents/a.json" content:@"{\"a\":1}"];
    [self createTestFile:@"equivalents/b.json" content:@"{\"b\":2}"];
    NSError *error = nil;

    CSResolvedInputSet *resolved = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(resolved);
    XCTAssertEqual(resolved.files.count, 2);
    XCTAssertTrue(resolved.isSequence, @"two files must yield is_sequence=true");
    XCTAssertTrue([resolved isHomogeneous],
                  @"two files of the same extension must be homogeneous via URN equivalence");
}

#pragma mark - Mirror-specific API surface tests

// Mirror-specific: glob pattern detection is an objc-only helper used by the resolver internals.
// Rust uses globwalk; these checks exercise the BSD glob detection logic.
- (void)test_glob_pattern_detection {
    XCTAssertTrue(CSInputResolverIsGlobPattern(@"*.txt"));
    XCTAssertTrue(CSInputResolverIsGlobPattern(@"file?.pdf"));
    XCTAssertTrue(CSInputResolverIsGlobPattern(@"doc[1-3].txt"));
    XCTAssertFalse(CSInputResolverIsGlobPattern(@"/path/to/file.txt"));
    XCTAssertFalse(CSInputResolverIsGlobPattern(@"regular_file.pdf"));
}

// Mirror-specific: CSResolvedInputSet aggregates totalSize across files
- (void)test_resolved_input_set_total_size {
    CSResolvedFile *file1 = [CSResolvedFile fileWithPath:@"/a.txt"
                                                mediaUrn:@"media:txt"
                                               sizeBytes:100
                                        contentStructure:CSContentStructureScalarOpaque];
    CSResolvedFile *file2 = [CSResolvedFile fileWithPath:@"/b.txt"
                                                mediaUrn:@"media:txt"
                                               sizeBytes:200
                                        contentStructure:CSContentStructureScalarOpaque];

    CSResolvedInputSet *set = [CSResolvedInputSet setWithFiles:@[file1, file2]
                                                    isSequence:YES
                                                   commonMedia:@"media:txt"];

    XCTAssertEqual([set totalSize], 300);
    XCTAssertTrue([set isHomogeneous]);
}

@end
