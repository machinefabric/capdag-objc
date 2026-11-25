//
//  CSLiveCapFabTests.m
//  CapDAGTests
//
//  Tests for CSLiveCapFab — mirrors Rust live_cap_fab.rs tests.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"
#import "CSMediaUrn.h"

@interface CSLiveCapFabTests : XCTestCase
@end

// Helper: build a test cap with given in/out/op/title
static CSCap *makeTestCap(NSString *inSpec, NSString *outSpec, NSString *op, NSString *title) {
    NSError *error = nil;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:inSpec];
    [builder outSpec:outSpec];
    [builder tag:@"op" value:op];
    CSCapUrn *built = [builder build:&error];
    NSCAssert(built != nil, @"Failed to build test cap URN: %@", error);

    CSCap *cap = [CSCap capWithUrn:built title:title aliases:@[@"test"]];
    [cap addArg:[CSCapArg argWithMediaUrn:inSpec
                                  name:@"arg1"
                                  required:YES
                                   sources:@[[CSArgSource stdinSourceWithMediaUrn:inSpec]]]];
    return cap;
}

// Helper: bookends that treat every URN appearing in the supplied caps (in or out
// direction) as bookend-eligible. Tests use this when they want graph reachability
// without an extra "filter to file formats" constraint — the planner's bookend
// filter is exercised by TEST7229.
static NSArray<CSMediaUrn *> *allBookends(NSArray<CSCap *> *caps) {
    NSMutableArray<CSMediaUrn *> *bookends = [NSMutableArray array];
    for (CSCap *cap in caps) {
        for (NSString *spec in @[[cap.capUrn getInSpec], [cap.capUrn getOutSpec]]) {
            NSError *error = nil;
            CSMediaUrn *urn = [CSMediaUrn fromString:spec error:&error];
            NSCAssert(urn != nil, @"Test cap spec '%@' is no media URN: %@", spec, error);
            [bookends addObject:urn];
        }
    }
    return bookends;
}

// Helper: the canonical texts of `urns`, in their order.
static NSArray<NSString *> *mediaTexts(NSArray<CSMediaUrn *> *urns) {
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:urns.count];
    for (CSMediaUrn *urn in urns) {
        [texts addObject:[urn toString]];
    }
    return texts;
}

// Helper: the canonical texts of `urns` in structural order.
static NSArray<NSString *> *sortedMediaTexts(NSArray<CSMediaUrn *> *urns) {
    return mediaTexts([urns sortedArrayUsingComparator:^NSComparisonResult(CSMediaUrn *a, CSMediaUrn *b) {
        return [a compareStructurally:b];
    }]);
}

@implementation CSLiveCapFabTests

// MARK: - Basic Tests (unnumbered, match Rust unnumbered tests)

- (void)test1150_AddCapAndBasicTraversal {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap = makeTestCap(@"media:document;ext=pdf", @"media:digitized", @"extract_text", @"Extract Text");
    [graph addCap:cap];
    [graph setBookends:allBookends(@[cap])];

    XCTAssertEqual([graph edgeCount], 1u);
    XCTAssertEqual([graph nodeCount], 2u);

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];
    XCTAssertNotNil(source);

    NSArray<CSReachableTargetInfo *> *targets = [graph getReachableTargetsFromSource:source maxDepth:5 isSequence:NO];
    XCTAssertEqual(targets.count, 1u);
    XCTAssertEqual(targets[0].minDepth, 1u);
}

// TEST7216: a source is read complete: a JSON record file, which does not mention `list`, takes
// the edge of a cap whose input refuses lists, though as a type it may be a list; a JSON list
// does not.
- (void)test7216_ASourceTakesAnEdgeItSatisfies {
    CSLiveCapFab *graph = [CSLiveCapFab graph];
    CSCap *cap = makeTestCap(@"media:enc=utf8;fmt=json;record;!list", @"media:enc=utf8;fmt=yaml;record",
                             @"record-to-yaml", @"Record To YAML");
    [graph addCap:cap];
    [graph setBookends:allBookends(@[cap])];

    NSError *error = nil;
    CSMediaUrn *yaml = [CSMediaUrn fromString:@"media:enc=utf8;fmt=yaml;record" error:&error];
    CSMediaUrn *record = [CSMediaUrn fromString:@"media:enc=utf8;ext=json;fmt=json;record" error:&error];
    CSMediaUrn *noList = [CSMediaUrn fromString:@"media:enc=utf8;fmt=json;record;!list" error:&error];
    CSMediaUrn *list = [CSMediaUrn fromString:@"media:enc=utf8;ext=json;fmt=json;list;record" error:&error];
    XCTAssertFalse([record conformsTo:noList], @"as a type the file may be a list");

    NSArray<CSReachableTargetInfo *> *targets = [graph getReachableTargetsFromSource:record maxDepth:5 isSequence:NO];
    XCTAssertEqual(targets.count, 1u, @"the record file takes the edge to YAML");
    XCTAssertEqualObjects(targets[0].mediaUrn, [yaml toString]);
    XCTAssertEqual(targets[0].minDepth, 1u);
    XCTAssertEqual([graph findPathsToExactTarget:record target:yaml maxDepth:5 maxPaths:10 isSequence:NO].count, 1u);

    XCTAssertEqual([graph getReachableTargetsFromSource:list maxDepth:5 isSequence:NO].count, 0u,
                   @"a list does not take an edge that refuses lists");
}

// TEST7219: the path search steps only into states the target is reachable from. Twelve kinds of
// dead-end data, each convertible into every other, give hundreds of millions of routes within
// eight steps; the one route to the target is six steps long and is found without walking them.
- (void)test7219_SearchSkipsBranchesThatCannotReachTheTarget {
    CSLiveCapFab *graph = [CSLiveCapFab graph];
    NSString *(^dead)(NSUInteger) = ^(NSUInteger n) { return [NSString stringWithFormat:@"media:dead;n=%lu", (unsigned long)n]; };
    NSString *(^route)(NSUInteger) = ^(NSUInteger n) { return [NSString stringWithFormat:@"media:route;n=%lu", (unsigned long)n]; };
    for (NSUInteger n = 0; n < 12; n++) {
        [graph addCap:makeTestCap(@"media:start", dead(n), [NSString stringWithFormat:@"into-dead-%lu", (unsigned long)n], @"Into Dead")];
        for (NSUInteger m = 0; m < 12; m++) {
            if (m == n) continue;
            [graph addCap:makeTestCap(dead(n), dead(m),
                                      [NSString stringWithFormat:@"dead-%lu-to-%lu", (unsigned long)n, (unsigned long)m], @"Dead To Dead")];
        }
    }
    [graph addCap:makeTestCap(@"media:start", route(1), @"route-1", @"Route 1")];
    for (NSUInteger n = 1; n < 5; n++) {
        [graph addCap:makeTestCap(route(n), route(n + 1), [NSString stringWithFormat:@"route-%lu", (unsigned long)(n + 1)], @"Route")];
    }
    [graph addCap:makeTestCap(route(5), @"media:finish", @"finish", @"Finish")];

    NSError *error = nil;
    CSMediaUrn *start = [CSMediaUrn fromString:@"media:start" error:&error];
    CSMediaUrn *finish = [CSMediaUrn fromString:@"media:finish" error:&error];
    NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:start target:finish maxDepth:8 maxPaths:10 isSequence:NO];
    XCTAssertEqual(paths.count, 1u, @"the one route is found");
    XCTAssertEqual(paths[0].capStepCount, 6);
}

// TEST1151: A target is reached by every route giving something inside it, the nearest first: a singular result is reached by the singular route and then the list route, a list result only by the list route.
- (void)test1151_ATargetIsReachedByEveryRouteInsideIt {
    // Verify is_equivalent distinguishes singular vs list
    NSError *error = nil;
    CSMediaUrn *singular = [CSMediaUrn fromString:@"media:analysis-result" error:&error];
    CSMediaUrn *list = [CSMediaUrn fromString:@"media:analysis-result;list" error:&error];

    XCTAssertFalse([singular isEquivalentTo:list], @"singular and list should NOT be equivalent");
    XCTAssertFalse([list isEquivalentTo:singular], @"list and singular should NOT be equivalent (reverse)");

    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap1 = makeTestCap(@"media:document;ext=pdf", @"media:analysis-result", @"analyze", @"Analyze PDF");
    CSCap *cap2 = makeTestCap(@"media:document;ext=pdf", @"media:analysis-result;list", @"analyze_multi", @"Analyze PDF Multi");
    [graph addCap:cap1];
    [graph addCap:cap2];

    CSMediaUrn *source = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];

    // The singular target, read open, holds the list as well: both routes reach it, the
    // one giving exactly what was asked first.
    CSMediaUrn *targetSingular = [CSMediaUrn fromString:@"media:analysis-result" error:&error];
    NSArray<CSStrand *> *pathsSingular = [graph findPathsToExactTarget:source target:targetSingular maxDepth:5 maxPaths:10 isSequence:NO];
    XCTAssertEqual(pathsSingular.count, 2u, @"both routes reach the singular target");
    XCTAssertEqualObjects(pathsSingular[0].steps[0].capUrn, [cap1.capUrn toString], @"the nearest route first");
    XCTAssertEqualObjects(pathsSingular[1].steps[0].capUrn, [cap2.capUrn toString]);

    // The list target does not hold a result that is no list: only the list route reaches it.
    CSMediaUrn *targetPlural = [CSMediaUrn fromString:@"media:analysis-result;list" error:&error];
    NSArray<CSStrand *> *pathsPlural = [graph findPathsToExactTarget:source target:targetPlural maxDepth:5 maxPaths:10 isSequence:NO];
    XCTAssertEqual(pathsPlural.count, 1u, @"only the route giving a list");
    XCTAssertEqualObjects(pathsPlural[0].steps[0].capUrn, [cap2.capUrn toString]);
}

// TEST1152: Multi step path
- (void)test1152_MultiStepPath {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap1 = makeTestCap(@"media:document;ext=pdf", @"media:digitized", @"extract", @"Extract");
    CSCap *cap2 = makeTestCap(@"media:digitized", @"media:summary-text", @"summarize", @"Summarize");
    [graph addCap:cap1];
    [graph addCap:cap2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:summary-text" error:&error];

    NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];

    XCTAssertEqual(paths.count, 1u);
    XCTAssertEqual(paths[0].totalSteps, 2);
    XCTAssertEqualObjects(paths[0].steps[0].capUrn, [cap1.capUrn toString]);
    XCTAssertEqualObjects(paths[0].steps[1].capUrn, [cap2.capUrn toString]);
}

// TEST1153: Deterministic ordering
- (void)test1153_DeterministicOrdering {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap1 = makeTestCap(@"media:document;ext=pdf", @"media:digitized", @"extract_a", @"Extract A");
    CSCap *cap2 = makeTestCap(@"media:document;ext=pdf", @"media:digitized", @"extract_b", @"Extract B");
    [graph addCap:cap1];
    [graph addCap:cap2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:digitized" error:&error];

    // Run twice — same order
    NSArray *paths1 = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];
    NSArray *paths2 = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];

    XCTAssertEqual(paths1.count, paths2.count);
    for (NSUInteger i = 0; i < paths1.count; i++) {
        CSStrand *p1 = paths1[i];
        CSStrand *p2 = paths2[i];
        XCTAssertEqualObjects(p1.steps[0].capUrn, p2.steps[0].capUrn);
    }
}

// Helper: a test cap from format-a to format-c whose cap URN carries the tags
// written in tagsText (such as "convert;fast").
static CSCap *makeTaggedTestCap(NSString *tagsText, NSString *title) {
    NSError *error = nil;
    NSString *text = [NSString stringWithFormat:@"cap:%@;in=\"media:format-a\";out=\"media:format-c\"", tagsText];
    CSCapUrn *built = [CSCapUrn fromString:text error:&error];
    NSCAssert(built != nil, @"Failed to parse test cap URN '%@': %@", text, error);

    CSCap *cap = [CSCap capWithUrn:built title:title aliases:@[@"test"]];
    [cap addArg:[CSCapArg argWithMediaUrn:@"media:format-a"
                                     name:@"arg1"
                                 required:YES
                                  sources:@[[CSArgSource stdinSourceWithMediaUrn:@"media:format-a"]]]];
    return cap;
}

// TEST7271: Among paths with as many cap steps, the one whose steps' specificities sum higher comes first, whatever order the caps were added in
- (void)test7271_PathsOfAsManyStepsAreOrderedBySpecificity {
    CSCap *general = makeTaggedTestCap(@"convert", @"Convert");
    CSCap *specific = makeTaggedTestCap(@"convert;fast", @"Convert fast");
    XCTAssertGreaterThan([specific.capUrn specificity], [general.capUrn specificity]);

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:format-a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:format-c" error:&error];
    NSArray<NSArray<CSCap *> *> *orders = @[@[general, specific], @[specific, general]];
    for (NSArray<CSCap *> *caps in orders) {
        CSLiveCapFab *graph = [CSLiveCapFab graph];
        for (CSCap *cap in caps) {
            [graph addCap:cap];
        }
        NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];
        XCTAssertEqual(paths.count, 2u, @"one path through each cap");
        CSCapUrn *first = [CSCapUrn fromString:paths[0].steps[0].capUrn error:&error];
        XCTAssertTrue([first isEquivalent:specific.capUrn],
                      @"the convert;fast path comes first, got %@", paths[0].steps[0].capUrn);
    }
}

// TEST7272: Paths equal in cap steps and specificity are ordered by their cap URNs' structure, not by their text or titles
- (void)test7272_EqualPathsAreOrderedStructurallyNotByText {
    // Structurally the tag key `a` comes before `a-x`. As text,
    // `cap:a-x=c;…` sorts before `cap:a=b;…` ('-' < '='), and by title
    // "Alpha" sorts before "Zed": either would put the other path first.
    CSCap *zed = makeTaggedTestCap(@"a=b", @"Zed");
    CSCap *alpha = makeTaggedTestCap(@"a-x=c", @"Alpha");
    XCTAssertEqual([zed.capUrn specificity], [alpha.capUrn specificity]);

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:format-a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:format-c" error:&error];
    NSArray<NSArray<CSCap *> *> *orders = @[@[zed, alpha], @[alpha, zed]];
    for (NSArray<CSCap *> *caps in orders) {
        CSLiveCapFab *graph = [CSLiveCapFab graph];
        for (CSCap *cap in caps) {
            [graph addCap:cap];
        }
        NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];
        XCTAssertEqual(paths.count, 2u, @"one path through each cap");
        CSCapUrn *first = [CSCapUrn fromString:paths[0].steps[0].capUrn error:&error];
        CSCapUrn *second = [CSCapUrn fromString:paths[1].steps[0].capUrn error:&error];
        XCTAssertTrue([first isEquivalent:zed.capUrn],
                      @"the a=b path (Zed) comes first, got %@", paths[0].steps[0].capUrn);
        XCTAssertTrue([second isEquivalent:alpha.capUrn],
                      @"the a-x=c path (Alpha) comes second, got %@", paths[1].steps[0].capUrn);
    }
}

// TEST1154: Sync from caps
- (void)test1154_SyncFromCaps {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    NSArray *caps = @[
        makeTestCap(@"media:document;ext=pdf", @"media:digitized", @"op1", @"Op1"),
        makeTestCap(@"media:digitized", @"media:summary-text", @"op2", @"Op2"),
    ];
    [graph syncFromCaps:caps bookendUrns:allBookends(caps)];

    XCTAssertEqual([graph edgeCount], 2u);
    XCTAssertEqual([graph nodeCount], 3u);

    // Sync again — should replace
    NSArray *newCaps = @[
        makeTestCap(@"media:image", @"media:digitized", @"ocr", @"OCR"),
    ];
    [graph syncFromCaps:newCaps bookendUrns:allBookends(newCaps)];

    XCTAssertEqual([graph edgeCount], 1u);
    XCTAssertEqual([graph nodeCount], 2u);
}

// MARK: - Numbered Tests

// TEST6650: Multi-step path through intermediate node
- (void)test6650_findPathsMultiStep {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap1 = makeTestCap(@"media:a", @"media:b", @"step1", @"A to B");
    CSCap *cap2 = makeTestCap(@"media:b", @"media:c", @"step2", @"B to C");
    [graph addCap:cap1];
    [graph addCap:cap2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:c" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];

    XCTAssertEqual(paths.count, 1u, @"Should find one path through intermediate");
    CSStrand *path = paths[0];
    XCTAssertEqual(path.steps.count, 2u, @"Path should have 2 steps");
    XCTAssertEqualObjects(path.steps[0].capUrn, [cap1.capUrn toString]);
    XCTAssertEqualObjects(path.steps[1].capUrn, [cap2.capUrn toString]);
}

// TEST6651: Empty when target unreachable
- (void)test6651_findPathsEmptyWhenNoPath {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap1 = makeTestCap(@"media:a", @"media:b", @"step1", @"A to B");
    [graph addCap:cap1];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:c" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];

    XCTAssertEqual(paths.count, 0u, @"Should find no paths when target unreachable");
}

// TEST6652: BFS finds multiple direct targets
- (void)test6652_getReachableTargetsAll {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap1 = makeTestCap(@"media:a", @"media:b", @"step1", @"A to B");
    CSCap *cap2 = makeTestCap(@"media:a", @"media:d", @"step3", @"A to D");
    [graph addCap:cap1];
    [graph addCap:cap2];
    [graph setBookends:allBookends(@[cap1, cap2])];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:a" error:&error];

    NSArray<CSReachableTargetInfo *> *targets = [graph getReachableTargetsFromSource:source maxDepth:5 isSequence:NO];

    XCTAssertEqual(targets.count, 2u, @"Should find 2 reachable targets");
    NSMutableSet *targetMediaUrns = [NSMutableSet set];
    for (CSReachableTargetInfo *t in targets) {
        [targetMediaUrns addObject:t.mediaUrn];
    }
    XCTAssertTrue([targetMediaUrns containsObject:@"media:b"], @"B should be reachable");
    XCTAssertTrue([targetMediaUrns containsObject:@"media:d"], @"D should be reachable");
}

// TEST6653: PDF cap does not match PNG input
- (void)test6653_typeMismatchPdfPng {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap = makeTestCap(@"media:document;ext=pdf", @"media:enc=utf8", @"pdf2text", @"PDF to Text");
    [graph addCap:cap];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:ext=png;image" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:enc=utf8" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];
    XCTAssertEqual(paths.count, 0u, @"Should NOT find path from PNG via PDF cap");
}

// TEST6654: PNG cap does not match PDF input
- (void)test6654_typeMismatchPngPdf {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *cap = makeTestCap(@"media:ext=png;image", @"media:thumbnail", @"png2thumb", @"PNG to Thumbnail");
    [graph addCap:cap];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:thumbnail" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];
    XCTAssertEqual(paths.count, 0u, @"Should NOT find path from PDF via PNG cap");
}

// TEST6655: BFS respects type matching
- (void)test6655_reachableTargetsTypeMatching {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *pdfCap = makeTestCap(@"media:document;ext=pdf", @"media:enc=utf8", @"pdf2text", @"PDF to Text");
    CSCap *pngCap = makeTestCap(@"media:ext=png;image", @"media:thumbnail", @"png2thumb", @"PNG to Thumbnail");
    [graph addCap:pdfCap];
    [graph addCap:pngCap];
    [graph setBookends:allBookends(@[pdfCap, pngCap])];

    NSError *error = nil;
    // PNG should only reach thumbnail
    CSMediaUrn *pngSource = [CSMediaUrn fromString:@"media:ext=png;image" error:&error];
    NSArray *pngTargets = [graph getReachableTargetsFromSource:pngSource maxDepth:5 isSequence:NO];
    XCTAssertEqual(pngTargets.count, 1u, @"PNG should reach 1 target");
    XCTAssertEqualObjects(((CSReachableTargetInfo *)pngTargets[0]).mediaUrn, @"media:thumbnail");

    // PDF should only reach text (media:enc=utf8)
    CSMediaUrn *pdfSource = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];
    NSArray *pdfTargets = [graph getReachableTargetsFromSource:pdfSource maxDepth:5 isSequence:NO];
    XCTAssertEqual(pdfTargets.count, 1u, @"PDF should reach 1 target");
    XCTAssertEqualObjects(((CSReachableTargetInfo *)pdfTargets[0]).mediaUrn, @"media:enc=utf8");
}

// TEST6656: Multi-step type chain enforcement
- (void)test6656_findPathsTypeChain {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *resize = makeTestCap(@"media:ext=png;image", @"media:resized-png", @"resize", @"Resize PNG");
    CSCap *toThumb = makeTestCap(@"media:resized-png", @"media:thumbnail", @"thumb", @"To Thumbnail");
    [graph addCap:resize];
    [graph addCap:toThumb];

    NSError *error = nil;
    // PNG should find 2-step path
    CSMediaUrn *pngSource = [CSMediaUrn fromString:@"media:ext=png;image" error:&error];
    CSMediaUrn *thumbTarget = [CSMediaUrn fromString:@"media:thumbnail" error:&error];
    NSArray *pngPaths = [graph findPathsToExactTarget:pngSource target:thumbTarget maxDepth:5 maxPaths:10 isSequence:NO];
    XCTAssertEqual(pngPaths.count, 1u, @"PNG should find 1 path to thumbnail");
    XCTAssertEqual(((CSStrand *)pngPaths[0]).steps.count, 2u, @"Path should have 2 steps");

    // PDF should find no path
    CSMediaUrn *pdfSource = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];
    NSArray *pdfPaths = [graph findPathsToExactTarget:pdfSource target:thumbTarget maxDepth:5 maxPaths:10 isSequence:NO];
    XCTAssertEqual(pdfPaths.count, 0u, @"PDF should find no path to thumbnail");
}

// TEST6657: Sorting prefers shorter paths
- (void)test6657_sortingShorterFirst {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    CSCap *direct = makeTestCap(@"media:format-a", @"media:format-c", @"direct", @"Direct");
    CSCap *step1 = makeTestCap(@"media:format-a", @"media:format-b", @"step1", @"Step 1");
    CSCap *step2 = makeTestCap(@"media:format-b", @"media:format-c", @"step2", @"Step 2");
    [graph addCap:direct];
    [graph addCap:step1];
    [graph addCap:step2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:format-a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:format-c" error:&error];

    NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10 isSequence:NO];

    XCTAssertGreaterThanOrEqual(paths.count, 2u, @"Should find at least 2 paths");
    XCTAssertEqual(paths[0].steps.count, 1u, @"Shortest path should be first (1 step)");
    XCTAssertEqualObjects(paths[0].steps[0].capUrn, [direct.capUrn toString]);
}

// TEST6658: ForEach synthesized when input is a sequence
- (void)test6658_forEachWithSequenceInput {
    CSLiveCapFab *graph = [CSLiveCapFab graph];

    // Two caps: pdf→page and text(enc=utf8)→decision
    CSCap *disbind = makeTestCap(@"media:document;ext=pdf", @"media:enc=utf8;page", @"disbind", @"Disbind PDF");
    CSCap *choose = makeTestCap(@"media:enc=utf8", @"media:decision;bool", @"choose", @"Make a Decision");

    [graph syncFromCaps:@[disbind, choose] bookendUrns:allBookends(@[disbind, choose])];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:document;ext=pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:decision;bool" error:&error];

    // With isSequence:NO (single PDF), should find direct path: disbind → choose (no ForEach)
    NSArray<CSStrand *> *scalarPaths = [graph findPathsToExactTarget:source target:target maxDepth:10 maxPaths:20 isSequence:NO];
    BOOL hasForEachScalar = NO;
    for (CSStrand *path in scalarPaths) {
        for (CSStrandStep *step in path.steps) {
            if (step.stepType == CSStrandStepTypeForEach) {
                hasForEachScalar = YES;
                break;
            }
        }
    }
    XCTAssertFalse(hasForEachScalar, @"Scalar input should NOT produce ForEach step");

    // With isSequence:YES (multiple PDFs), should find path with ForEach
    NSArray<CSStrand *> *seqPaths = [graph findPathsToExactTarget:source target:target maxDepth:10 maxPaths:20 isSequence:YES];
    BOOL hasForEachSeq = NO;
    for (CSStrand *path in seqPaths) {
        for (CSStrandStep *step in path.steps) {
            if (step.stepType == CSStrandStepTypeForEach) {
                hasForEachSeq = YES;
                break;
            }
        }
    }
    XCTAssertTrue(hasForEachSeq, @"Sequence input should produce ForEach step");
}

// TEST8064: a sequence-consuming cap is reached directly from sequence data,
// never through a dangling ForEach boundary. A ForEach followed by a SCALAR cap
// stays legal — that is the map half of the ordinary map-then-fold plan — so the
// invariant is about what may follow the boundary, not about ForEach appearing.
- (void)test8064_sequenceConsumerNeverFollowsForEachDirectly {
    CSLiveCapFab *graph = [CSLiveCapFab graph];
    NSError *error = nil;
    CSCap *concat = [CSCap capWithDictionary:@{
        @"urn": @"cap:concat;in=\"media:enc=utf8\";out=\"media:enc=utf8;ext=txt;plain-text\"",
        @"title": @"Concat Text",
        @"aliases": @[@"concat"],
        @"args": @[@{
            @"media_urn": @"media:enc=utf8",
            @"name": @"texts",
            @"required": @YES,
            @"is_sequence": @YES,
            @"sources": @[@{@"stdin": @"media:enc=utf8"}],
        }],
        @"outputs": @[@{@"media_urn": @"media:enc=utf8;ext=txt;plain-text", @"name": @"text", @"output_description": @"The text"}],
    } error:&error];
    XCTAssertNotNil(concat, @"%@", error);
    [graph addCap:concat];
    [graph addCap:makeTestCap(@"media:enc=utf8",
                              @"media:enc=utf8;summary",
                              @"summarize",
                              @"Summarize Text")];

    CSMediaUrn *source = [CSMediaUrn fromString:@"media:enc=utf8;page" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:enc=utf8;ext=txt;plain-text" error:&error];
    NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:source
                                                        target:target
                                                      maxDepth:4
                                                      maxPaths:20
                                                    isSequence:YES];

    XCTAssertGreaterThan(paths.count, 0u);

    BOOL direct = NO;
    for (CSStrand *path in paths) {
        if (path.steps.count == 1 &&
            path.steps[0].stepType == CSStrandStepTypeCap &&
            path.steps[0].inputIsSequence) {
            direct = YES;
        }
    }
    XCTAssertTrue(direct, @"sequence data must reach the sequence consumer directly");

    for (CSStrand *path in paths) {
        [path.steps enumerateObjectsUsingBlock:^(CSStrandStep *step, NSUInteger index, BOOL *stop) {
            if (step.stepType != CSStrandStepTypeForEach) return;
            XCTAssertLessThan(index + 1, path.steps.count,
                              @"a ForEach boundary must be followed by a cap");
            CSStrandStep *next = path.steps[index + 1];
            XCTAssertEqual(next.stepType, CSStrandStepTypeCap);
            XCTAssertFalse(next.inputIsSequence,
                           @"a ForEach boundary must qualify a SCALAR-input cap");
        }];
    }
}

// TEST790: Tests identity_urn is specific and doesn't match everything
- (void)test790_identityUrnSpecific {
    NSError *error = nil;
    CSCapUrn *identity = [CSCapUrn fromString:CSCapIdentity error:&error];
    XCTAssertNotNil(identity, @"Should parse identity URN");

    // Identity has wildcard specs
    XCTAssertEqualObjects([identity getInSpec], @"media:");
    XCTAssertEqualObjects([identity getOutSpec], @"media:");

    // A specific cap should NOT be equivalent to identity
    CSCapUrnBuilder *specificBuilder = [CSCapUrnBuilder builder];
    [specificBuilder inSpec:@"media:document;ext=pdf"];
    [specificBuilder outSpec:@"media:enc=utf8;disbound-page;list"];
    [specificBuilder tag:@"op" value:@"disbind"];
    CSCapUrn *built = [specificBuilder build:&error];
    XCTAssertNotNil(built);

    XCTAssertFalse([built isEquivalent:identity],
                   @"A specific disbind cap should NOT be equivalent to identity");
}

// TEST12847: every output of a cap other than its main one is reachable by
// planning: the search has an edge from the cap's input to that output's own
// type, and a strand that reaches it records which output it took (by URN),
// with that output's cardinality. An output that carries the input has no
// type of its own and no edge; the main output's edge is the cap's.
- (void)test12847_aCapsOtherOutputsAreReachableByPlanning {
    CSCap *split = makeTestCap(@"media:enc=utf8;ext=txt;plain-text", @"media:enc=utf8;head", @"split", @"Split");
    [split setOutputs:@[
        [CSCapOutput outputWithMediaUrn:@"media:enc=utf8;head" name:@"head" outputDescription:@"the head"],
        [CSCapOutput outputWithMediaUrn:@"media:enc=utf8;rest" name:@"rest" outputDescription:@"the rest"],
        [[CSCapOutput outputWithMediaUrn:@"media:enc=utf8;part" name:@"parts" outputDescription:@"the parts"] outputAsSequence:YES],
        [[CSCapOutput outputWithMediaUrn:@"media:enc=utf8;same" name:@"same" outputDescription:@"the input"] outputCarryingInput],
    ]];
    CSCap *count = makeTestCap(@"media:enc=utf8;rest", @"media:integer;numeric", @"count", @"Count");
    CSLiveCapFab *graph = [CSLiveCapFab graph];
    [graph addCap:split];
    [graph addCap:count];
    [graph setBookends:allBookends(@[split, count])];
    XCTAssertEqual([graph edgeCount], 4u, @"split: head, rest, parts; count: one");

    CSMediaUrn *(^media)(NSString *) = ^CSMediaUrn *(NSString *text) { return [CSMediaUrn fromString:text error:nil]; };
    CSMediaUrn *text = media(@"media:enc=utf8;ext=txt;plain-text");
    CSStrandStep *(^onlyStep)(NSString *) = ^CSStrandStep *(NSString *target) {
        NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:text target:media(target) maxDepth:3 maxPaths:10 isSequence:NO];
        XCTAssertEqual(paths.count, 1u, @"one path to %@", target);
        XCTAssertEqual(paths.firstObject.steps.count, 1u);
        return paths.firstObject.steps.firstObject;
    };

    XCTAssertNil(onlyStep(@"media:enc=utf8;head").outputUrn);

    CSStrandStep *rest = onlyStep(@"media:enc=utf8;rest");
    XCTAssertEqualObjects(rest.capUrn, [split.capUrn toString]);
    XCTAssertEqualObjects(rest.outputUrn, @"media:enc=utf8;rest");
    XCTAssertFalse(rest.outputIsSequence);
    XCTAssertEqualObjects(rest.toSpec, @"media:enc=utf8;rest", @"the output's own type, not the effect's");

    XCTAssertTrue(onlyStep(@"media:enc=utf8;part").outputIsSequence, @"the output's own cardinality");

    XCTAssertEqual([graph findPathsToExactTarget:text target:media(@"media:enc=utf8;same") maxDepth:3 maxPaths:10 isSequence:NO].count, 0u,
                   @"a carried output is reached by no edge");

    // Through another output and on.
    NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:text target:media(@"media:integer;numeric") maxDepth:3 maxPaths:10 isSequence:NO];
    XCTAssertEqual(paths.count, 1u);
    NSArray<CSStrandStep *> *steps = paths.firstObject.steps;
    XCTAssertEqual(steps.count, 2u);
    XCTAssertEqualObjects(steps.firstObject.outputUrn, @"media:enc=utf8;rest");
    XCTAssertNil(steps.lastObject.outputUrn);
}

// TEST7229: a node that may have several shapes ends on the bookends its shapes are,
// read complete. A save that gives JSON which may or may not be a list and may or may
// not be a record ends on the four JSON file types, each a target of a route through
// it; a search for the JSON file type, which holds all four, finds the route, and one
// for the JSON record file does not, since the save may give a list or a value. A node
// one of whose shapes is no file type ends on none.
- (void)test7229_aNodeOfSeveralShapesEndsOnEachBookendItMayBe {
    NSString *saved = @"media:enc=utf8;ext=json;fmt=json;?list;?record";
    NSArray<NSString *> *fileTexts = @[
        @"media:enc=utf8;ext=json;fmt=json",
        @"media:enc=utf8;ext=json;fmt=json;list",
        @"media:enc=utf8;ext=json;fmt=json;record",
        @"media:enc=utf8;ext=json;fmt=json;list;record",
    ];
    CSMediaUrn *(^media)(NSString *) = ^CSMediaUrn *(NSString *text) {
        NSError *error = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:text error:&error];
        XCTAssertNotNil(urn, @"%@: %@", text, error);
        return urn;
    };
    NSMutableArray<CSMediaUrn *> *files = [NSMutableArray array];
    for (NSString *text in fileTexts) {
        [files addObject:media(text)];
    }
    CSLiveCapFab *graph = [CSLiveCapFab graph];
    [graph addCap:makeTestCap(@"media:enc=utf8;fmt=json;!ext", saved, @"save-as-json", @"Save as JSON")];
    CSMediaUrn *source = media(@"media:enc=utf8;fmt=json;list;record");
    CSMediaUrn *recordFile = media(@"media:enc=utf8;ext=json;fmt=json;record");

    [graph setBookends:files];
    XCTAssertTrue([graph isBookend:media(saved)]);
    XCTAssertEqualObjects(mediaTexts([graph endsOn:media(saved)]), sortedMediaTexts(files),
                          @"one bookend for each shape");

    NSMutableArray<CSMediaUrn *> *targets = [NSMutableArray array];
    for (CSReachableTargetInfo *target in [graph getReachableTargetsFromSource:source maxDepth:3 isSequence:NO]) {
        XCTAssertEqual(target.minDepth, 1u, @"%@ is one save away", target.mediaUrn);
        [targets addObject:media(target.mediaUrn)];
    }
    XCTAssertEqualObjects(sortedMediaTexts(targets), sortedMediaTexts(files),
                          @"every file type the save may give is a target");

    NSArray<CSStrand *> *paths = [graph findPathsToExactTarget:source target:files[0] maxDepth:3 maxPaths:10 isSequence:NO];
    XCTAssertEqual(paths.count, 1u, @"the route through the save");
    XCTAssertEqual(paths.firstObject.capStepCount, 1);
    XCTAssertTrue([media(paths.firstObject.targetMediaUrn) isEquivalentTo:media(saved)],
                  @"the route gives what the save may be");
    XCTAssertEqual([graph findPathsToExactTarget:source target:recordFile maxDepth:3 maxPaths:10 isSequence:NO].count, 0u);

    // Without a file type for JSON that is neither a list nor a record, one of the
    // save's shapes is no file: the node ends on nothing.
    [graph setBookends:[files subarrayWithRange:NSMakeRange(1, files.count - 1)]];
    XCTAssertFalse([graph isBookend:media(saved)]);
    XCTAssertEqual([graph endsOn:media(saved)].count, 0u);
    XCTAssertEqual([graph getReachableTargetsFromSource:source maxDepth:3 isSequence:NO].count, 0u);
}

// The graph a YAML record is planned to a JSON file in, as the fabric declares its
// caps: YAML to JSON (a patch, keeping the record), the merge of YAML mappings into a
// JSON array (taking a sequence), and the four JSON saves, with the file types they
// read and write as bookends.
static NSString *const kSaveAsJson = @"cap:in=\"media:enc=utf8;fmt=json;!ext\";out=\"media:enc=utf8;ext=json;fmt=json;?list;?record\";save-as-json";
static NSString *const kSaveAsJsonValue = @"cap:in=\"media:enc=utf8;fmt=json;!list;!record;!ext\";out=\"media:enc=utf8;ext=json;fmt=json\";save-as-json";
static NSString *const kSaveAsJsonRecord = @"cap:in=\"media:enc=utf8;fmt=json;!list;record;!ext\";out=\"media:enc=utf8;ext=json;fmt=json;record\";save-as-json";
static NSString *const kSaveAsJsonListOfRecords = @"cap:in=\"media:enc=utf8;fmt=json;list;record;!ext\";out=\"media:enc=utf8;ext=json;fmt=json;list;record\";save-as-json";

// A cap of the cap URN `capText`, taking its input on stdin, as one value or, with
// `sequence`, as a sequence.
static CSCap *capOfUrn(NSString *capText, NSString *title, BOOL sequence) {
    NSError *error = nil;
    CSCapUrn *capUrn = [CSCapUrn fromString:capText error:&error];
    NSCAssert(capUrn != nil, @"%@: %@", capText, error);
    CSCap *cap = [CSCap capWithUrn:capUrn title:title aliases:@[@"test"]];
    NSString *inSpec = [capUrn getInSpec];
    [cap addArg:[[CSCapArg argWithMediaUrn:inSpec
                                      name:@"input"
                                  required:YES
                                   sources:@[[CSArgSource stdinSourceWithMediaUrn:inSpec]]] argAsSequence:sequence]];
    return cap;
}

static CSLiveCapFab *jsonSavesGraph(void) {
    NSArray<CSCap *> *caps = @[
        capOfUrn(@"cap:convert-format;effect=patch;in=\"media:enc=utf8;fmt=yaml\";out=\"media:enc=utf8;fmt=json;!ext\";yaml-to-json", @"Convert YAML to JSON", NO),
        capOfUrn(@"cap:collect-yaml-mappings-to-json-array;in=\"media:enc=utf8;fmt=yaml;!list;record\";out=\"media:enc=utf8;fmt=json;list;record\"", @"Merge YAML Mappings into JSON Array", YES),
        capOfUrn(kSaveAsJson, @"Save as JSON", NO),
        capOfUrn(kSaveAsJsonValue, @"Save as JSON Value", NO),
        capOfUrn(kSaveAsJsonRecord, @"Save as JSON Record", NO),
        capOfUrn(kSaveAsJsonListOfRecords, @"Save as JSON List of Records", NO),
    ];
    NSMutableArray<CSMediaUrn *> *bookends = [NSMutableArray array];
    for (NSString *text in @[@"media:enc=utf8;ext=yaml;fmt=yaml;record",
                             @"media:enc=utf8;ext=json;fmt=json",
                             @"media:enc=utf8;ext=json;fmt=json;list",
                             @"media:enc=utf8;ext=json;fmt=json;record",
                             @"media:enc=utf8;ext=json;fmt=json;list;record"]) {
        NSError *error = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:text error:&error];
        NSCAssert(urn != nil, @"%@: %@", text, error);
        [bookends addObject:urn];
    }
    CSLiveCapFab *graph = [CSLiveCapFab graph];
    [graph syncFromCaps:caps bookendUrns:bookends];
    return graph;
}

// The cap URNs of the routes' last steps, in order.
static NSArray<NSString *> *lastCaps(NSArray<CSStrand *> *routes) {
    NSMutableArray<NSString *> *caps = [NSMutableArray arrayWithCapacity:routes.count];
    for (CSStrand *route in routes) {
        [caps addObject:route.steps.lastObject.capUrn];
    }
    return caps;
}

// The first of `caps` that is the cap `capText`, or NSNotFound.
static NSUInteger indexOfCap(NSArray<NSString *> *caps, NSString *capText) {
    CSCapUrn *wanted = [CSCapUrn fromString:capText error:nil];
    NSCAssert(wanted != nil, @"%@ is no cap URN", capText);
    for (NSUInteger i = 0; i < caps.count; i++) {
        if ([[CSCapUrn fromString:caps[i] error:nil] isEquivalent:wanted]) return i;
    }
    return NSNotFound;
}

static CSMediaUrn *mediaOf(NSString *text) {
    NSError *error = nil;
    CSMediaUrn *urn = [CSMediaUrn fromString:text error:&error];
    NSCAssert(urn != nil, @"%@: %@", text, error);
    return urn;
}

// TEST7277: A patch cap's edge gives what it was sent with its change, not its declared output: JSON to YAML sent a JSON list of records file gives a YAML list of records, no file, which the save of a YAML list of records takes
- (void)test7277_aPatchEdgeGivesWhatItWasSentWithItsChange {
    CSMediaUrn *source = mediaOf(@"media:enc=utf8;ext=json;fmt=json;list;record");
    CSMediaUrn *target = mediaOf(@"media:enc=utf8;ext=yaml;fmt=yaml;list;record");
    CSLiveCapFab *graph = [CSLiveCapFab graph];
    [graph syncFromCaps:@[
        capOfUrn(@"cap:convert-format;effect=patch;in=\"media:enc=utf8;fmt=json\";json-to-yaml;out=\"media:enc=utf8;fmt=yaml;!ext\"", @"Convert JSON to YAML", NO),
        capOfUrn(@"cap:in=\"media:enc=utf8;fmt=yaml;list;record;!ext\";out=\"media:enc=utf8;ext=yaml;fmt=yaml;list;record\";save-as-yaml", @"Save as YAML List of Records", NO),
    ] bookendUrns:@[source, target]];

    NSArray<CSStrand *> *routes = [graph findPathsToExactTarget:source target:target maxDepth:4 maxPaths:10 isSequence:NO];
    XCTAssertEqual(routes.count, 1u, @"JSON to YAML, then the save");
    XCTAssertEqual(routes.firstObject.capStepCount, 2);
    NSString *converted = routes.firstObject.steps.firstObject.toSpec;
    XCTAssertTrue([mediaOf(converted) isEquivalentTo:mediaOf(@"media:enc=utf8;!ext;fmt=yaml;list;record")],
                  @"the patch gives a YAML list of records, no file, not %@", converted);
}

// TEST7275: A target is a search over what routes give: from a YAML record, every route whose output is inside the JSON file type reaches it, listed nearest to what was asked first, each with what it gives
- (void)test7275_routesToATargetAreEveryRouteInsideItNearestFirst {
    CSLiveCapFab *graph = jsonSavesGraph();
    CSMediaUrn *source = mediaOf(@"media:enc=utf8;ext=yaml;fmt=yaml;record");
    CSMediaUrn *target = mediaOf(@"media:enc=utf8;ext=json;fmt=json");

    NSArray<CSStrand *> *routes = [graph findPathsToExactTarget:source target:target maxDepth:4 maxPaths:50 isSequence:NO];
    NSArray<NSString *> *caps = lastCaps(routes);
    NSUInteger generic = indexOfCap(caps, kSaveAsJson);
    NSUInteger record = indexOfCap(caps, kSaveAsJsonRecord);
    NSUInteger listOfRecords = indexOfCap(caps, kSaveAsJsonListOfRecords);
    XCTAssertTrue(generic != NSNotFound && record != NSNotFound && listOfRecords != NSNotFound,
                  @"a route ends with each save: %@", caps);
    XCTAssertTrue(generic < record && record < listOfRecords,
                  @"the generic save (as specific as the target), then the record save, then the list-of-records save: %@", caps);
    for (CSStrand *route in routes) {
        CSMediaUrn *gives = mediaOf(route.steps.lastObject.toSpec);
        XCTAssertTrue([gives satisfies:target], @"%@ is inside %@", gives, target);
        XCTAssertTrue([mediaOf(route.targetMediaUrn) isEquivalentTo:gives],
                      @"the route names what it gives, %@, not %@", gives, route.targetMediaUrn);
    }
}

// TEST7276: A route whose output may fall outside the target does not reach it: none from a YAML record reaches a JSON file that is neither a list nor a record, and the generic save does not reach a JSON record file, which the record save does
- (void)test7276_aRouteThatMayGiveMoreThanWasAskedDoesNotReachIt {
    CSLiveCapFab *graph = jsonSavesGraph();
    CSMediaUrn *source = mediaOf(@"media:enc=utf8;ext=yaml;fmt=yaml;record");

    CSMediaUrn *plain = mediaOf(@"media:enc=utf8;ext=json;fmt=json;!list;!record");
    NSArray<NSString *> *plainCaps = lastCaps([graph findPathsToExactTarget:source target:plain maxDepth:4 maxPaths:50 isSequence:NO]);
    XCTAssertEqual(plainCaps.count, 0u,
                   @"no save of a YAML record's content gives JSON that is surely neither a list nor a record: %@", plainCaps);

    CSMediaUrn *recordFile = mediaOf(@"media:enc=utf8;ext=json;fmt=json;record");
    NSArray<NSString *> *caps = lastCaps([graph findPathsToExactTarget:source target:recordFile maxDepth:4 maxPaths:50 isSequence:NO]);
    XCTAssertNotEqual(indexOfCap(caps, kSaveAsJsonRecord), NSNotFound, @"%@", caps);
    XCTAssertEqual(indexOfCap(caps, kSaveAsJson), NSNotFound,
                   @"the generic save may write a list or a value, so it does not reach a JSON record file: %@", caps);
}

@end
