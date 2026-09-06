//
//  CSCartridgeCaps.h
//  CapDAG Cartridge SDK
//
//  A small ordered collection of CSCap values. The CapDAG host exposes this
//  to surface a cartridge's own caps for display — nothing more.
//

#import <Foundation/Foundation.h>
#import "CSCap.h"

NS_ASSUME_NONNULL_BEGIN

@interface CSCartridgeCaps : NSObject <NSCopying, NSCoding>

/// Caps in the order they were added.
@property (nonatomic, readonly) NSArray<CSCap *> *caps;

/// Create a new empty collection.
+ (instancetype)new;

/// Append a cap.
- (void)addCap:(CSCap *)cap;

/// URN strings for every cap, in insertion order.
///
/// Callers wanting to match or compare these must parse them with
/// `+[CSCapUrn fromString:error:]`. Tagged URNs are not strings — they carry
/// tag ordering and normalization rules that string comparison cannot honor.
- (NSArray<NSString *> *)capUrns;

@end

NS_ASSUME_NONNULL_END
