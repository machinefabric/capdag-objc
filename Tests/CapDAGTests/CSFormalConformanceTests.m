//
//  CSFormalConformanceTests.m
//  TEST12166: matching, specificity, dispatch and acceptance are the proved model's.
//
//  The rules are proved in capdag/formal (Lean); this is what ties them to
//  this mirror: every row of ../formal/conformance.json (written by the
//  model, `lake exe conformance`) is parsed by the media and cap URN parsers
//  here and must get the model's verdict. The same table runs in every mirror.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSFormalConformanceTests : XCTestCase
@end

@implementation CSFormalConformanceTests

// TEST12166: every row of the proved model's table
- (void)test12166_theImplementationIsTheProvedModel {
    NSString *path = [NSString stringWithUTF8String:__FILE__];
    for (int i = 0; i < 4; i++) path = [path stringByDeletingLastPathComponent];
    path = [[path stringByAppendingPathComponent:@"formal"] stringByAppendingPathComponent:@"conformance.json"];
    NSData *raw = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(raw, @"the model's table at %@", path);
    NSDictionary *table = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    NSArray *refines = table[@"refines"];
    NSArray *scores = table[@"scores"];
    NSArray *dispatch = table[@"dispatch"];
    NSMutableArray *wrong = [NSMutableArray array];
    NSError *error = nil;

    for (NSDictionary *r in refines) {
        CSMediaUrn *a = [CSMediaUrn fromString:r[@"instance"] error:&error];
        CSMediaUrn *b = [CSMediaUrn fromString:r[@"pattern"] error:&error];
        XCTAssertNotNil(a);
        XCTAssertNotNil(b);
        BOOL got = [a conformsTo:b error:&error];
        if (got != [r[@"refines"] boolValue]) {
            [wrong addObject:[NSString stringWithFormat:@"%@ ⪯ %@: model %@, got %d", r[@"instance"], r[@"pattern"], r[@"refines"], got]];
        }
    }
    for (NSDictionary *r in scores) {
        CSMediaUrn *u = [CSMediaUrn fromString:r[@"urn"] error:&error];
        XCTAssertNotNil(u);
        NSInteger got = [u specificity];
        if (got != [r[@"score"] integerValue]) {
            [wrong addObject:[NSString stringWithFormat:@"score %@: model %@, got %ld", r[@"urn"], r[@"score"], (long)got]];
        }
    }
    for (NSDictionary *r in dispatch) {
        CSCapUrn *c = [CSCapUrn fromString:r[@"candidate"] error:&error];
        CSCapUrn *q = [CSCapUrn fromString:r[@"request"] error:&error];
        XCTAssertNotNil(c);
        XCTAssertNotNil(q);
        BOOL got = [c isDispatchable:q];
        if (got != [r[@"dispatch"] boolValue]) {
            [wrong addObject:[NSString stringWithFormat:@"%@ serves %@: model %@, got %d", r[@"candidate"], r[@"request"], r[@"dispatch"], got]];
        }
        got = [c accepts:q];
        if (got != [r[@"accepts"] boolValue]) {
            [wrong addObject:[NSString stringWithFormat:@"%@ accepts %@: model %@, got %d", r[@"candidate"], r[@"request"], r[@"accepts"], got]];
        }
    }
    XCTAssertTrue(refines.count > 4000 && dispatch.count > 20000, @"the table is the full one");
    XCTAssertEqual(wrong.count, 0u, @"%lu row(s) differ from the model, e.g. %@",
                   (unsigned long)wrong.count,
                   [wrong subarrayWithRange:NSMakeRange(0, MIN(8u, wrong.count))]);
}

@end
