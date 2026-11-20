//
//  CSCapMatcher.m
//  Choosing among registered caps for a request
//

#import "CSCapMatcher.h"

@implementation CSCapMatcher

+ (nullable CSCapUrn *)findBestMatchInCaps:(NSArray<CSCapUrn *> *)caps
                                forRequest:(CSCapUrn *)request {
    NSUInteger index = [CSCapUrn selectFromCandidates:caps forRequest:request];
    return index == NSNotFound ? nil : caps[index];
}

+ (NSArray<CSCapUrn *> *)findAllMatchesInCaps:(NSArray<CSCapUrn *> *)caps
                                   forRequest:(CSCapUrn *)request {
    NSMutableArray<CSCapUrn *> *serving = [NSMutableArray array];
    for (CSCapUrn *cap in caps) {
        if ([cap isDispatchable:request]) {
            [serving addObject:cap];
        }
    }
    // A stable sort, so caps of equal key keep their registration order.
    return [serving sortedArrayWithOptions:NSSortStable
                           usingComparator:^NSComparisonResult(CSCapUrn *a, CSCapUrn *b) {
        return [a compareRankWith:b forRequest:request];
    }];
}

+ (BOOL)areCompatible:(NSArray<CSCapUrn *> *)caps1 with:(NSArray<CSCapUrn *> *)caps2 {
    for (CSCapUrn *c1 in caps1) {
        for (CSCapUrn *c2 in caps2) {
            if ([c1 isComparable:c2]) {
                return YES;
            }
        }
    }
    return NO;
}

@end
