//
//  CSMediaAdapters.m
//  CapDAG
//
//  CSMediaAdapterRegistry — tracks cartridge-provided content inspection adapters
//  and names the cartridges to consult for a file's candidates. Content
//  inspection is performed by cartridges via the adapter-selection cap protocol.
//
//  Mirrors Rust: capdag/src/input_resolver/adapters/registry.rs
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

- (NSUInteger)registeredAdapterCount {
    return self.registeredAdapters.count;
}

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

    // Exact re-registration is IDEMPOTENT: an adapter URN equivalent to one
    // this same (cartridgeId, groupName) already registered is neither a
    // conflict nor a second row — a cartridge attached through more than one
    // hosting route (e.g. app-bundled and system-installed) is still one
    // adapter provider, not an ambiguity with itself. The skip is logged.
    NSMutableArray<CSRegisteredAdapter *> *freshAdapters = [[NSMutableArray alloc] init];
    for (CSRegisteredAdapter *newAdapter in newAdapters) {
        BOOL alreadyRegistered = NO;
        for (CSRegisteredAdapter *existing in self.registeredAdapters) {
            if ([existing.cartridgeId isEqualToString:cartridgeId] &&
                [existing.groupName isEqualToString:groupName] &&
                [existing.mediaUrn isEquivalentTo:newAdapter.mediaUrn]) {
                alreadyRegistered = YES;
                break;
            }
        }
        if (alreadyRegistered) {
            NSLog(@"[WARN] Adapter URN '%@' of cap group '%@' is already registered by "
                  @"cartridge '%@' — the cartridge is attached through more than one "
                  @"hosting route; keeping the first registration and skipping this one",
                  newAdapter.urnString, groupName, cartridgeId);
        } else {
            [freshAdapters addObject:newAdapter];
        }
    }

    // Check each new adapter against all existing registered adapters
    for (CSRegisteredAdapter *newAdapter in freshAdapters) {
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

    // No conflicts — register atomically (re-registered URNs already have
    // their row).
    [self.registeredAdapters addObjectsFromArray:freshAdapters];
    return YES;
}

- (NSArray<CSCartridgeAdapter *> *)adaptersForCandidates:(NSArray<CSMediaUrn *> *)candidates {
    NSMutableArray<CSCartridgeAdapter *> *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seenCartridges = [NSMutableSet set];
    for (CSRegisteredAdapter *registered in self.registeredAdapters) {
        BOOL matches = NO;
        for (CSMediaUrn *candidate in candidates) {
            if ([candidate conformsTo:registered.mediaUrn]) {
                matches = YES;
                break;
            }
        }
        if (matches && ![seenCartridges containsObject:registered.cartridgeId]) {
            [seenCartridges addObject:registered.cartridgeId];
            [results addObject:[CSCartridgeAdapter adapterWithCartridgeId:registered.cartridgeId
                                                               adapterUrn:registered.mediaUrn]];
        }
    }
    return results;
}

/// The file media types the fabric declares for an extension, parsed. A
/// definition with no valid URN is an error naming it.
- (void)extensionCandidates:(NSString *)extension
                 completion:(void (^)(NSArray<CSMediaUrn *> *_Nullable candidates, NSError *_Nullable error))completion {
    [self.fabricRegistry fileMediaForExtension:extension completion:^(NSArray<NSDictionary *> *definitions, NSError *error) {
        if (!definitions) {
            completion(nil, error);
            return;
        }
        NSMutableArray<CSMediaUrn *> *candidates = [NSMutableArray arrayWithCapacity:definitions.count];
        for (NSDictionary *definition in definitions) {
            NSError *parseError = nil;
            id urnString = definition[@"urn"];
            CSMediaUrn *urn = [urnString isKindOfClass:[NSString class]]
                ? [CSMediaUrn fromString:urnString error:&parseError]
                : nil;
            if (!urn) {
                completion(nil, [NSError errorWithDomain:CSFabricRegistryErrorDomain
                                                    code:1001
                                                userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"the fabric's media definition '%@' has no valid URN: %@",
                        urnString, parseError.localizedDescription ?: @"it is not a string"]
                }]);
                return;
            }
            [candidates addObject:urn];
        }
        completion(candidates, nil);
    }];
}

- (void)findAdaptersForExtension:(NSString *)extension
                      completion:(void (^)(NSArray<CSCartridgeAdapter *> *_Nullable adapters,
                                           NSError *_Nullable error))completion {
    [self extensionCandidates:extension completion:^(NSArray<CSMediaUrn *> *candidates, NSError *error) {
        if (!candidates) {
            completion(nil, error);
            return;
        }
        completion([self adaptersForCandidates:candidates], nil);
    }];
}

- (void)hasAdapterForExtension:(NSString *)extension
                    completion:(void (^)(BOOL hasAdapter, NSError *_Nullable error))completion {
    [self extensionCandidates:extension completion:^(NSArray<CSMediaUrn *> *candidates, NSError *error) {
        if (!candidates) {
            completion(NO, error);
            return;
        }
        completion([self adaptersForCandidates:candidates].count > 0, nil);
    }];
}

@end
