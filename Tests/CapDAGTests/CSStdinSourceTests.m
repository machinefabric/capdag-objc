//
//  CSStdinSourceTests.m
//  Tests for CSStdinSource
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSStdinSourceTests : XCTestCase
@end

@implementation CSStdinSourceTests

// TEST6445: Source with data
- (void)test6445_SourceWithData {
    NSData *testData = [@"test data content" dataUsingEncoding:NSUTF8StringEncoding];
    CSStdinSource *source = [CSStdinSource sourceWithData:testData];

    XCTAssertNotNil(source);
    XCTAssertEqual(source.kind, CSStdinSourceKindData);
    XCTAssertTrue([source isData]);
    XCTAssertFalse([source isFileReference]);
    XCTAssertEqualObjects(source.data, testData);
    XCTAssertNil(source.trackedFileID);
    XCTAssertNil(source.originalPath);
    XCTAssertNil(source.securityBookmark);
    XCTAssertNil(source.mediaUrn);
}

// TEST6447: Source with file reference
- (void)test6447_SourceWithFileReference {
    NSString *trackedFileID = @"tracked-file-123";
    NSString *originalPath = @"/path/to/original.pdf";
    NSData *securityBookmark = [@"security-bookmark-data" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *mediaUrn = @"media:ext=pdf";

    CSStdinSource *source = [CSStdinSource sourceWithFileReference:trackedFileID
                                                      originalPath:originalPath
                                                   securityBookmark:securityBookmark
                                                           mediaUrn:mediaUrn];

    XCTAssertNotNil(source);
    XCTAssertEqual(source.kind, CSStdinSourceKindFileReference);
    XCTAssertFalse([source isData]);
    XCTAssertTrue([source isFileReference]);
    XCTAssertNil(source.data);
    XCTAssertEqualObjects(source.trackedFileID, trackedFileID);
    XCTAssertEqualObjects(source.originalPath, originalPath);
    XCTAssertEqualObjects(source.securityBookmark, securityBookmark);
    XCTAssertEqualObjects(source.mediaUrn, mediaUrn);
}

// TEST6461: Data source with empty data
- (void)test6461_DataSourceWithEmptyData {
    NSData *emptyData = [NSData data];
    CSStdinSource *source = [CSStdinSource sourceWithData:emptyData];

    XCTAssertNotNil(source);
    XCTAssertEqual(source.kind, CSStdinSourceKindData);
    XCTAssertTrue([source isData]);
    XCTAssertEqual(source.data.length, 0);
}

// TEST6477: Data source with binary content
- (void)test6477_DataSourceWithBinaryContent {
    // Test with PNG header bytes
    uint8_t pngHeader[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
    NSData *binaryData = [NSData dataWithBytes:pngHeader length:sizeof(pngHeader)];

    CSStdinSource *source = [CSStdinSource sourceWithData:binaryData];

    XCTAssertNotNil(source);
    XCTAssertTrue([source isData]);
    XCTAssertEqualObjects(source.data, binaryData);
    XCTAssertEqual(source.data.length, 8);
}

// TEST6485: File reference with all fields
- (void)test6485_FileReferenceWithAllFields {
    // Verify all fields are properly stored and retrievable
    NSString *trackedFileID = @"uuid-12345-67890";
    NSString *originalPath = @"/Users/test/Documents/large-file.pdf";

    // Create realistic security bookmark data
    uint8_t bookmarkBytes[] = {0x62, 0x6F, 0x6F, 0x6B, 0x00, 0x00, 0x00, 0x00};
    NSData *securityBookmark = [NSData dataWithBytes:bookmarkBytes length:sizeof(bookmarkBytes)];

    NSString *mediaUrn = @"media:ext=pdf";

    CSStdinSource *source = [CSStdinSource sourceWithFileReference:trackedFileID
                                                      originalPath:originalPath
                                                   securityBookmark:securityBookmark
                                                           mediaUrn:mediaUrn];

    // Verify each field independently
    XCTAssertEqualObjects(source.trackedFileID, trackedFileID);
    XCTAssertEqualObjects(source.originalPath, originalPath);
    XCTAssertEqualObjects(source.securityBookmark, securityBookmark);
    XCTAssertEqualObjects(source.mediaUrn, mediaUrn);
}

@end
