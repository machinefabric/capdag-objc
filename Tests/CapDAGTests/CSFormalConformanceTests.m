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
        BOOL got = [a conformsTo:b];
        if (got != [r[@"refines"] boolValue]) {
            [wrong addObject:[NSString stringWithFormat:@"%@ ⪯ %@: model %@, got %d", r[@"instance"], r[@"pattern"], r[@"refines"], got]];
        }
        NSDictionary<NSString *, NSNumber *> *media = @{
            @"meets": @([a meets:b]),
            @"satisfies": @([a satisfies:b]),
            @"may_satisfy": @([a maySatisfy:b]),
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
        CSCapQuery *request = [CSCapQuery fromCall:q];
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

- (NSDictionary *)modelTable {
    NSString *path = [NSString stringWithUTF8String:__FILE__];
    for (int i = 0; i < 4; i++) path = [path stringByDeletingLastPathComponent];
    path = [[path stringByAppendingPathComponent:@"formal"] stringByAppendingPathComponent:@"conformance.json"];
    NSData *raw = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(raw, @"the model's table at %@", path);
    return [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
}

// TEST7123: the cap URN parser refuses a cap exactly when the model says it
// cannot be declared, and for the reason the model gives: the bare top form,
// or an effect=none cap whose input is not inside its output. Every other cap
// over every effect, patch included, parses.
- (void)test7123_admissibilityIsTheModels {
    NSArray *rows = [self modelTable][@"admissible"];
    XCTAssertEqual(rows.count, 500u, @"every cap over the directions, cap-tags and effects");
    NSMutableArray *wrong = [NSMutableArray array];
    for (NSDictionary *r in rows) {
        NSError *error = nil;
        CSCapUrn *cap = [CSCapUrn fromString:r[@"cap"] error:&error];
        NSString *got = nil;
        if (!cap) {
            NSString *message = error.localizedDescription;
            if (![error.domain isEqualToString:CSCapUrnErrorDomain] || error.code != CSCapUrnErrorIllegalDeclaration) {
                got = [NSString stringWithFormat:@"refused, not as illegal: %@", message];
            } else if ([message hasPrefix:@"illegal bare top cap"]) {
                got = @"bare_top";
            } else if ([message hasPrefix:@"effect=none requires declared input"]) {
                got = @"none_not_inside";
            } else {
                got = [NSString stringWithFormat:@"refused: %@", message];
            }
        }
        id model = r[@"illegal"];
        NSString *expected = model == [NSNull null] ? nil : model;
        if (!(got == expected || [got isEqualToString:expected])) {
            [wrong addObject:[NSString stringWithFormat:@"%@: model %@, got %@", r[@"cap"], expected, got]];
        }
    }
    XCTAssertEqual(wrong.count, 0u, @"%lu of %lu row(s) differ from the model, e.g. %@",
                   (unsigned long)wrong.count, (unsigned long)rows.count,
                   [wrong subarrayWithRange:NSMakeRange(0, MIN(8u, wrong.count))]);
}

- (NSArray<CSMediaUrn *> *)mediaOf:(NSArray<NSString *> *)texts {
    NSMutableArray<CSMediaUrn *> *urns = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSString *text in texts) {
        NSError *error = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:text error:&error];
        XCTAssertNotNil(urn, @"%@: %@", text, error);
        [urns addObject:urn];
    }
    return urns;
}

// TEST7124: what a file is, decided through the detection module as a host
// runs it: which candidates stand, given what their rules say of the content,
// the consulted adapters and what their cartridges claimed; which of those
// each line of refinement keeps; and which of the kept a host that cannot ask
// takes. The content is one byte, so a rule of at least one byte is met and a
// rule of at least two is not.
- (void)test7124_detectionIsTheModels {
    NSArray *rows = [self modelTable][@"detect"];
    XCTAssertEqual(rows.count, (NSUInteger)((9 + 81) * 2 * 4), @"every rule, owner and claim set over both lists");
    NSData *content = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *rules = @{@"met": @{@"min_length": @1}, @"unmet": @{@"min_length": @2}};
    NSMutableArray *wrong = [NSMutableArray array];
    for (NSDictionary *r in rows) {
        NSMutableArray<CSFileMediaCandidate *> *candidates = [NSMutableArray array];
        for (NSDictionary *c in r[@"candidates"]) {
            CSFileMediaCandidate *candidate = [CSFileMediaCandidate new];
            candidate.urn = [self mediaOf:@[c[@"urn"]]].firstObject;
            candidate.validation = rules[c[@"rules"]];
            XCTAssertTrue([c[@"rules"] isEqualToString:@"unruled"] || candidate.validation != nil,
                          @"the model's table names no rules '%@'", c[@"rules"]);
            [candidates addObject:candidate];
        }
        NSString *failure = nil;
        NSArray<CSMediaUrn *> *survivors = CSSurvivingCandidates(content, candidates, [self mediaOf:r[@"owners"]],
                                                                 [self mediaOf:r[@"claims"]], &failure);
        XCTAssertNotNil(survivors, @"%@", failure);
        NSMutableArray<NSNumber *> *stands = [NSMutableArray array];
        for (CSFileMediaCandidate *c in candidates) {
            [stands addObject:@([survivors indexOfObjectIdenticalTo:c.urn] != NSNotFound)];
        }
        if (![stands isEqualToArray:r[@"stands"]]) {
            [wrong addObject:[NSString stringWithFormat:@"%@: stands %@", r, stands]];
            continue;
        }
        NSArray<NSString *> *kept = CSSettle(survivors);
        NSMutableArray<NSNumber *> *mostSpecific = [NSMutableArray array];
        NSUInteger keptCount = 0;
        for (CSMediaUrn *s in survivors) [mostSpecific addObject:@([kept containsObject:[s toString]])];
        for (NSNumber *k in r[@"most_specific"]) keptCount += k.boolValue ? 1 : 0;
        if (![mostSpecific isEqualToArray:r[@"most_specific"]] || kept.count != keptCount) {
            [wrong addObject:[NSString stringWithFormat:@"%@: kept %@", r, kept]];
            continue;
        }
        NSError *error = nil;
        NSString *primary = CSPrimaryMedia(kept, &error);
        XCTAssertNil(error);
        id position = r[@"primary"];
        NSString *expected = position == [NSNull null] ? nil : kept[[position unsignedIntegerValue]];
        if (!(primary == expected || [primary isEqualToString:expected])) {
            [wrong addObject:[NSString stringWithFormat:@"%@: primary %@", r, primary]];
        }
    }
    XCTAssertEqual(wrong.count, 0u, @"%lu of %lu row(s) differ from the model, e.g. %@",
                   (unsigned long)wrong.count, (unsigned long)rows.count,
                   [wrong subarrayWithRange:NSMakeRange(0, MIN(8u, wrong.count))]);
}

@end
