//
//  CSMediaAdapters.m
//  CapDAG
//
//  CSMediaAdapterRegistry — tracks cartridge-provided content inspection adapters.
//  All in-process adapters have been removed. Content inspection is now performed
//  by cartridges via the adapter-selection cap protocol.
//

#import "CSInputResolver.h"
#import "CSFabricRegistry.h"
#import "CSMediaUrn.h"

// MARK: - Registered Adapter Entry

@interface CSRegisteredAdapter : NSObject
@property (nonatomic, strong) CSMediaUrn *mediaUrn;
@property (nonatomic, strong) NSString *urnString;
@property (nonatomic, strong) NSString *groupName;
@property (nonatomic, strong) NSString *cartridgeId;
@end

@implementation CSRegisteredAdapter
@end

// MARK: - CSMediaAdapterRegistry

@interface CSMediaAdapterRegistry ()
@property (nonatomic, strong) NSMutableArray<CSRegisteredAdapter *> *registeredAdapters;
@property (nonatomic, strong) CSFabricRegistry *fabricRegistry;
@end

@implementation CSMediaAdapterRegistry

- (instancetype)initWithFabricRegistry:(CSFabricRegistry *)fabricRegistry {
    self = [super init];
    if (self) {
        _registeredAdapters = [[NSMutableArray alloc] init];
        _fabricRegistry = fabricRegistry;
    }
    return self;
}

- (BOOL)registerCapGroup:(NSString *)groupName
             adapterUrns:(NSArray<NSString *> *)adapterUrns
             cartridgeId:(NSString *)cartridgeId
                   error:(NSError **)error {
    // Parse all new adapter URNs first
    NSMutableArray<CSRegisteredAdapter *> *newAdapters = [[NSMutableArray alloc] init];
    for (NSString *urnStr in adapterUrns) {
        NSError *parseError = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:urnStr error:&parseError];
        if (!urn) {
            NSAssert(NO, @"Cap group '%@' has invalid adapter URN '%@': %@",
                     groupName, urnStr, parseError.localizedDescription);
            return NO;
        }
        CSRegisteredAdapter *entry = [[CSRegisteredAdapter alloc] init];
        entry.mediaUrn = urn;
        entry.urnString = urnStr;
        entry.groupName = groupName;
        entry.cartridgeId = cartridgeId;
        [newAdapters addObject:entry];
    }

    // Check each new adapter against all existing registered adapters
    for (CSRegisteredAdapter *newAdapter in newAdapters) {
        for (CSRegisteredAdapter *existing in self.registeredAdapters) {
            BOOL newConformsToExisting = [newAdapter.mediaUrn conformsTo:existing.mediaUrn];
            BOOL existingConformsToNew = [existing.mediaUrn conformsTo:newAdapter.mediaUrn];

            if (newConformsToExisting || existingConformsToNew) {
                if (error) {
                    NSString *msg = [NSString stringWithFormat:
                        @"Cap group '%@' rejected: adapter URN '%@' conflicts with '%@' "
                        @"(registered by group '%@' in cartridge '%@'). "
                        @"One conforms to the other, creating ambiguity.",
                        groupName, newAdapter.urnString, existing.urnString,
                        existing.groupName, existing.cartridgeId];
                    *error = [NSError errorWithDomain:@"CSFabricRegistryError"
                                                 code:2001
                                             userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
                return NO;
            }
        }
    }

    // Also check new adapters against each other within the same group
    for (NSUInteger i = 0; i < newAdapters.count; i++) {
        for (NSUInteger j = i + 1; j < newAdapters.count; j++) {
            CSRegisteredAdapter *a = newAdapters[i];
            CSRegisteredAdapter *b = newAdapters[j];
            BOOL aConformsToB = [a.mediaUrn conformsTo:b.mediaUrn];
            BOOL bConformsToA = [b.mediaUrn conformsTo:a.mediaUrn];

            if (aConformsToB || bConformsToA) {
                if (error) {
                    NSString *msg = [NSString stringWithFormat:
                        @"Cap group '%@' rejected: adapter URN '%@' conflicts with '%@' "
                        @"within the same group in cartridge '%@'.",
                        groupName, a.urnString, b.urnString, cartridgeId];
                    *error = [NSError errorWithDomain:@"CSFabricRegistryError"
                                                 code:2002
                                             userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
                return NO;
            }
        }
    }

    // No conflicts — register atomically
    [self.registeredAdapters addObjectsFromArray:newAdapters];
    return YES;
}

- (NSArray<NSString *> *)cartridgeIdsForExtension:(NSString *)extension {
    NSArray<NSString *> *candidateStrings = [self.fabricRegistry mediaUrnsForExtension:extension];
    if (!candidateStrings || candidateStrings.count == 0) {
        return @[];
    }

    // Parse candidates
    NSMutableArray<CSMediaUrn *> *candidates = [[NSMutableArray alloc] init];
    for (NSString *s in candidateStrings) {
        CSMediaUrn *urn = [CSMediaUrn fromString:s error:nil];
        if (urn) {
            [candidates addObject:urn];
        }
    }

    // Find registered adapters where any candidate conforms to the registered URN
    NSMutableOrderedSet<NSString *> *result = [[NSMutableOrderedSet alloc] init];
    for (CSRegisteredAdapter *registered in self.registeredAdapters) {
        for (CSMediaUrn *candidate in candidates) {
            if ([candidate conformsTo:registered.mediaUrn]) {
                [result addObject:registered.cartridgeId];
                break;
            }
        }
    }

    return [result array];
}

- (BOOL)hasAdapterForExtension:(NSString *)extension {
    return [[self cartridgeIdsForExtension:extension] count] > 0;
}

@end
