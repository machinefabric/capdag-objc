//
//  CSCapMatcher.h
//  Choosing among registered caps for a request
//

#import <Foundation/Foundation.h>
#import "CSCapUrn.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Choosing among registered caps for a request, as the proved ranking does
 * (CapDAG.Exec.select): only the caps that serve the request
 * (-[CSCapUrn isDispatchable:]) are considered, the one whose specificity is
 * closest to the request's ranks first (an exact match, then the nearest
 * refinement, then the nearest fallback), and of caps that rank alike the first
 * registered comes first. `caps` is in registration order.
 */
@interface CSCapMatcher : NSObject

/**
 * The cap the ranking chooses to serve `request`
 * (+[CSCapUrn selectFromCandidates:forRequest:]).
 * @param caps Registered caps, in registration order
 * @param request The request to serve
 * @return The chosen cap, or nil when no cap serves the request
 */
+ (nullable CSCapUrn *)findBestMatchInCaps:(NSArray<CSCapUrn *> * _Nonnull)caps
                                forRequest:(CSCapUrn * _Nonnull)request;

/**
 * Every cap that serves `request`, in ranking order: the one
 * findBestMatchInCaps:forRequest: chooses first, and caps that rank alike in
 * registration order.
 * @param caps Registered caps, in registration order
 * @param request The request to serve
 */
+ (NSArray<CSCapUrn *> * _Nonnull)findAllMatchesInCaps:(NSArray<CSCapUrn *> * _Nonnull)caps
                                            forRequest:(CSCapUrn * _Nonnull)request;

/**
 * Whether two cap sets overlap: some cap of one is comparable with some cap of
 * the other (-[CSCapUrn isComparable:]).
 */
+ (BOOL)areCompatible:(NSArray<CSCapUrn *> * _Nonnull)caps1
                 with:(NSArray<CSCapUrn *> * _Nonnull)caps2;

@end

NS_ASSUME_NONNULL_END
