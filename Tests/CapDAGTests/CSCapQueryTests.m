//
//  CSCapQueryTests.m
//  Questions about caps: a side left unknown, and the tags a cap has.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSCapQueryTests : XCTestCase
@end

@implementation CSCapQueryTests

- (CSCapUrn *)cap:(NSString *)text {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:text error:&error];
    XCTAssertNotNil(cap, @"%@: %@", text, error);
    return cap;
}

- (CSMediaUrn *)media:(NSString *)text {
    NSError *error = nil;
    CSMediaUrn *media = [CSMediaUrn fromString:text error:&error];
    XCTAssertNotNil(media, @"%@: %@", text, error);
    return media;
}

// TEST12368: "what gives me this, whatever it takes?" and "what can this
// become?" are questions with a side unknown, and each cap answers with a grade.
//
// No cap URN can ask them: `media:` on a side is the type "anything", so a
// request spelled that way asked for a cap that takes everything, and found
// none. The unknown side asks nothing; the stated side is held to.
- (void)test12368_aQuestionMayLeaveASideUnknown {
    CSCapUrn *pages = [self cap:@"cap:disbind;in=\"media:ext=pdf\";out=\"media:enc=utf-8;ext=txt;page\""];
    CSCapUrn *toJpeg = [self cap:@"cap:convert-image;in=\"media:ext=png;image\";out=\"media:ext=jpeg;image\""];
    CSCapUrn *someImage = [self cap:@"cap:render;in=\"media:ext=pdf\";out=\"media:image\""];
    CSCapUrn *passesThrough = [self cap:@"cap:decimate-sequence;effect=none"];

    CSCapQuery *wantsJpeg = [CSCapQuery producing:[self media:@"media:ext=jpeg;image"] tags:nil];
    XCTAssertEqual([wantsJpeg grade:toJpeg], CSMatchGradeExact);
    XCTAssertTrue([wantsJpeg admits:toJpeg], @"whatever it takes: a png here");
    // "Some image" is not a jpeg, and not excluded: possible, never routed on.
    XCTAssertEqual([wantsJpeg grade:someImage], CSMatchGradePossible);
    XCTAssertFalse([wantsJpeg admits:someImage]);
    XCTAssertTrue([wantsJpeg mayAdmit:someImage]);
    XCTAssertEqual([wantsJpeg grade:pages], CSMatchGradeNone);

    // Asked for any image, a jpeg is guaranteed to be one, not exactly it.
    CSCapQuery *wantsImage = [CSCapQuery producing:[self media:@"media:image"] tags:nil];
    XCTAssertEqual([wantsImage grade:toJpeg], CSMatchGradeGuaranteed);
    XCTAssertEqual([wantsImage grade:someImage], CSMatchGradeExact);
    XCTAssertFalse([wantsImage admits:passesThrough], @"media: out promises no image");

    // What can a pdf become? Whatever takes a pdf — or takes anything.
    CSCapQuery *hasPdf = [CSCapQuery consuming:[self media:@"media:ext=pdf"] tags:nil];
    XCTAssertTrue([hasPdf admits:pages]);
    XCTAssertTrue([hasPdf admits:someImage]);
    XCTAssertTrue([hasPdf admits:passesThrough], @"it takes anything, a pdf included");
    XCTAssertFalse([hasPdf admits:toJpeg], @"a png converter does not take a pdf");
    XCTAssertEqual([hasPdf grade:toJpeg], CSMatchGradeNone);

    // Both sides stated is the typed call.
    CSCapQuery *pdfToImage = [CSCapQuery betweenInput:[self media:@"media:ext=pdf"]
                                               output:[self media:@"media:image"]
                                                 tags:nil];
    XCTAssertTrue([pdfToImage admits:someImage]);
    XCTAssertFalse([pdfToImage admits:pages]);
    XCTAssertFalse([pdfToImage admits:toJpeg]);
}

// TEST12369: the cap-tags a query asks for are matched against the tags the
// cap HAS — a cap's own list is complete.
//
// So asking that a tag be absent selects the caps that do not carry it, which
// no cap needs to declare; and a cap may carry tags nobody asked about.
- (void)test12369_aQuerysTagsAreAskedOfTheTagsACapHas {
    CSCapUrn *toJpeg = [self cap:@"cap:convert-image;in=\"media:ext=png;image\";out=\"media:ext=jpeg;image\""];
    CSCapUrn *someImage = [self cap:@"cap:render;in=\"media:ext=pdf\";out=\"media:image\""];
    CSMediaUrn *anyImage = [self media:@"media:image"];

    CSCapQuery *converters = [CSCapQuery producing:anyImage tags:@{@"convert-image": @"*"}];
    XCTAssertTrue([converters admits:toJpeg]);
    XCTAssertFalse([converters admits:someImage], @"it renders; it is not tagged convert-image");

    CSCapQuery *notConverters = [CSCapQuery producing:anyImage tags:@{@"convert-image": @"!"}];
    XCTAssertTrue([notConverters admits:someImage], @"it does not have the tag");
    XCTAssertFalse([notConverters admits:toJpeg], @"it has it");
    XCTAssertEqual([notConverters grade:toJpeg], CSMatchGradeNone);

    // The same holds of a request: `!x` is served by a cap silent on x.
    CSCapUrn *request = [self cap:@"cap:!convert-image;out=\"media:image\""];
    XCTAssertTrue([someImage isDispatchable:request]);
    XCTAssertFalse([toJpeg isDispatchable:request]);
    XCTAssertEqual([[CSCapQuery fromRequest:request] grade:someImage], CSMatchGradeExact);
}

@end
