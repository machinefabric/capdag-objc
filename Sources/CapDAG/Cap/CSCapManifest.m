//
//  CSCapManifest.m
//  CapDAG
//
//  Unified cap-based manifest for components (providers and cartridges)
//

#import "CSCapManifest.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSStandardCaps.h"

// MARK: - CSCapGroup

@implementation CSCapGroup

- (instancetype)initWithName:(NSString *)name
                        caps:(NSArray<CSCap *> *)caps
                 adapterUrns:(NSArray<NSString *> *)adapterUrns {
    self = [super init];
    if (self) {
        _name = [name copy];
        _caps = [caps copy];
        _adapterUrns = [adapterUrns copy];
    }
    return self;
}

+ (nullable instancetype)groupWithDictionary:(NSDictionary *)dictionary
                                       error:(NSError * _Nullable * _Nullable)error {
    NSString *name = dictionary[@"name"];
    if (!name) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1020
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap group missing required 'name' field"}];
        }
        return nil;
    }

    NSArray *capsArray = dictionary[@"caps"];
    NSMutableArray<CSCap *> *caps = [[NSMutableArray alloc] init];
    if (capsArray && [capsArray isKindOfClass:[NSArray class]]) {
        for (NSDictionary *capDict in capsArray) {
            if (![capDict isKindOfClass:[NSDictionary class]]) {
                if (error) {
                    *error = [NSError errorWithDomain:@"CSCapManifestError"
                                                 code:1021
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid cap format in cap group caps array"}];
                }
                return nil;
            }
            CSCap *cap = [CSCap capWithDictionary:capDict error:error];
            if (!cap) {
                return nil;
            }
            [caps addObject:cap];
        }
    }

    NSArray *adapterUrnsArray = dictionary[@"adapter_urns"];
    NSArray<NSString *> *adapterUrns = @[];
    if (adapterUrnsArray && [adapterUrnsArray isKindOfClass:[NSArray class]]) {
        adapterUrns = adapterUrnsArray;
    }

    return [[self alloc] initWithName:name caps:[caps copy] adapterUrns:adapterUrns];
}

@end

// MARK: - CSCapManifest

@implementation CSCapManifest

- (instancetype)initWithName:(NSString *)name
                     version:(NSString *)version
                     channel:(NSString *)channel
          manifestDescription:(NSString *)manifestDescription
               capGroups:(NSArray<CSCapGroup *> *)capGroups {
    self = [super init];
    if (self) {
        _name = [name copy];
        _version = [version copy];
        _channel = [channel copy];
        _manifestDescription = [manifestDescription copy];
        _capGroups = [capGroups copy];
    }
    return self;
}

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                         channel:(NSString *)channel
                     description:(NSString *)description
                       capGroups:(NSArray<CSCapGroup *> *)capGroups {
    return [[self alloc] initWithName:name
                              version:version
                              channel:channel
                   manifestDescription:description
                         capGroups:capGroups];
}

+ (nullable instancetype)manifestWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *name = dictionary[@"name"];
    NSString *version = dictionary[@"version"];
    NSString *channel = dictionary[@"channel"];
    NSString *description = dictionary[@"description"];
    NSArray *capGroupsArray = dictionary[@"cap_groups"];

    if (!name || !version || !channel || !description || !capGroupsArray) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1007
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required manifest fields: name, version, channel, description, or cap_groups"}];
        }
        return nil;
    }
    // Channel is part of the cartridge's identity. Reject anything
    // outside the closed enum {release, nightly} so a typo never
    // silently masquerades as a known channel.
    if (![channel isEqualToString:@"release"] && ![channel isEqualToString:@"nightly"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1023
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Manifest 'channel' is '%@'; expected 'release' or 'nightly'", channel]}];
        }
        return nil;
    }

    // Parse cap_groups array
    NSMutableArray<CSCapGroup *> *groups = [[NSMutableArray alloc] init];
    for (NSDictionary *groupDict in capGroupsArray) {
        if (![groupDict isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"CSCapManifestError"
                                             code:1022
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid cap_group format"}];
            }
            return nil;
        }
        CSCapGroup *group = [CSCapGroup groupWithDictionary:groupDict error:error];
        if (!group) {
            return nil;
        }
        [groups addObject:group];
    }

    CSCapManifest *manifest = [[self alloc] initWithName:name
                                                version:version
                                                channel:channel
                                     manifestDescription:description
                                              capGroups:[groups copy]];

    // Optional fields
    NSString *author = dictionary[@"author"];
    if (author) {
        manifest.author = author;
    }

    NSString *pageUrl = dictionary[@"page_url"];
    if (pageUrl) {
        manifest.pageUrl = pageUrl;
    }

    return manifest;
}

- (CSCapManifest *)withAuthor:(NSString *)author {
    self.author = [author copy];
    return self;
}

- (CSCapManifest *)withPageUrl:(NSString *)pageUrl {
    self.pageUrl = [pageUrl copy];
    return self;
}

- (NSArray<CSCap *> *)allCaps {
    NSMutableArray<CSCap *> *result = [[NSMutableArray alloc] init];
    for (CSCapGroup *group in self.capGroups) {
        [result addObjectsFromArray:group.caps];
    }
    return [result copy];
}

- (BOOL)validate:(NSError **)error {
    // Parse CAP_IDENTITY URN
    NSError *parseError = nil;
    CSCapUrn *identityUrn = [CSCapUrn fromString:CSCapIdentity error:&parseError];
    if (!identityUrn) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1009
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"BUG: CAP_IDENTITY constant is invalid: %@", parseError.localizedDescription]}];
        }
        return NO;
    }

    // Check all caps (including cap groups) for identity
    BOOL hasIdentity = NO;
    for (CSCap *cap in [self allCaps]) {
        if ([identityUrn conformsTo:cap.capUrn]) {
            hasIdentity = YES;
            break;
        }
    }

    if (!hasIdentity) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1010
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Manifest missing required CAP_IDENTITY (%@)", CSCapIdentity]}];
        }
        return NO;
    }

    return YES;
}

- (CSCapManifest *)ensureIdentity {
    // Parse CAP_IDENTITY URN
    CSCapUrn *identityUrn = [CSCapUrn fromString:CSCapIdentity error:nil];
    if (!identityUrn) {
        NSAssert(NO, @"BUG: CAP_IDENTITY constant is invalid");
        return self;
    }

    // Check if identity is already present (in all caps including groups)
    BOOL hasIdentity = NO;
    for (CSCap *cap in [self allCaps]) {
        if ([identityUrn conformsTo:cap.capUrn]) {
            hasIdentity = YES;
            break;
        }
    }

    if (hasIdentity) {
        return self;
    }

    // Add identity cap to the first cap group (or create one)
    CSCap *identityCap = [CSCap capWithUrn:identityUrn
                                     title:@"Identity"
                                   command:@"identity"];

    NSMutableArray<CSCapGroup *> *newGroups = [self.capGroups mutableCopy];
    if (newGroups.count > 0) {
        // Add to first group
        CSCapGroup *firstGroup = newGroups[0];
        NSMutableArray *groupCaps = [firstGroup.caps mutableCopy];
        [groupCaps addObject:identityCap];
        newGroups[0] = [[CSCapGroup alloc] initWithName:firstGroup.name
                                                   caps:[groupCaps copy]
                                            adapterUrns:firstGroup.adapterUrns];
    } else {
        // Create a default group
        CSCapGroup *defaultGroup = [[CSCapGroup alloc] initWithName:@"default"
                                                              caps:@[identityCap]
                                                       adapterUrns:@[]];
        [newGroups addObject:defaultGroup];
    }

    return [CSCapManifest manifestWithName:self.name
                                   version:self.version
                                   channel:self.channel
                               description:self.manifestDescription
                                 capGroups:[newGroups copy]];
}

@end
