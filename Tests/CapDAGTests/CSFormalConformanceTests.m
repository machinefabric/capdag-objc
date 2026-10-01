//
//  CSFormalConformanceTests.m
//  TEST12166: every answer about media and caps is the proved model's.
//
//  The rules are proved in capdag/formal (Lean); this is what ties them to
//  this mirror: every row of ../formal/conformance.json (written by the
//  model, `lake exe conformance`) is parsed by the media and cap URN parsers
//  here and must get the model's verdict: between media, the guarantee, the
//  possibility and the complete reading; between caps, serving, could-serve and
//  the grade of a request, fitting a pattern, being the same cap, and flowing
//  into one another. The same table runs in every mirror.
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
        NSDictionary<NSString *, NSNumber *> *media = @{
            @"meets": @([a meets:b error:&error]),
            @"satisfies": @([a satisfies:b error:&error]),
            @"may_satisfy": @([a maySatisfy:b error:&error]),
        };
        for (NSString *name in media) {
            if (media[name].boolValue != [r[name] boolValue]) {
                [wrong addObject:[NSString stringWithFormat:@"%@ %@ %@: model %@, got %@", r[@"instance"], name, r[@"pattern"], r[name], media[name]]];
            }
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
        CSCapQuery *request = [CSCapQuery fromRequest:q];
        NSString *grade = CSMatchGradeName([request grade:c]);
        if (![grade isEqualToString:r[@"grade"]]) {
            [wrong addObject:[NSString stringWithFormat:@"grade of %@ for %@: model %@, got %@", r[@"candidate"], r[@"request"], r[@"grade"], grade]];
        }
        NSArray<NSArray *> *checks = @[
            @[@"dispatch", @([c isDispatchable:q])],
            @[@"dispatch", @([request admits:c])],
            @[@"may_dispatch", @([c mayDispatch:q])],
            @[@"may_dispatch", @([request mayAdmit:c])],
            @[@"accepts", @([c accepts:q])],
            @[@"accepts", @([[CSCapQuery fromPattern:c] admits:q])],
            @[@"accepts", @([q conformsTo:c])],
            @[@"equivalent", @([c isEquivalent:q])],
            @[@"flows", @([c flowsInto:q])],
        ];
        for (NSArray *check in checks) {
            NSString *name = check[0];
            if ([check[1] boolValue] != [r[name] boolValue]) {
                [wrong addObject:[NSString stringWithFormat:@"%@: %@ / %@: model %@, got %@", name, r[@"candidate"], r[@"request"], r[name], check[1]]];
            }
        }
    }
    XCTAssertTrue(refines.count > 4000 && dispatch.count > 30000, @"the table is the full one");
    XCTAssertEqual(wrong.count, 0u, @"%lu row(s) differ from the model, e.g. %@",
                   (unsigned long)wrong.count,
                   [wrong subarrayWithRange:NSMakeRange(0, MIN(8u, wrong.count))]);
}

@end
