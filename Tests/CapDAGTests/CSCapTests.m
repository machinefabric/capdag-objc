//
//  CSCapTests.m
//  CapDAGTests
//
//  NOTE: All ArgumentType/OutputType enums have been removed.
//  Arguments and outputs now use mediaUrn fields containing media URNs
//  (e.g., "media:string") that resolve via the mediaDefs table.
//

#import <XCTest/XCTest.h>
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSCapManifest.h"
#import "CSMediaDef.h"
#import "CSMediaUrn.h"
#import "CSFabricRegistry.h"

@interface CSCapTests : XCTestCase

@end

static CSFabricRegistry *registryWithSpecs(NSArray<NSDictionary *> *specs) {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    for (NSDictionary *spec in specs) {
        [registry addMediaDef:spec];
    }
    return registry;
}

@implementation CSCapTests

// TEST0108: Cap creation
- (void)test0108_CapCreation {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;transform;out=\"media:enc=utf-8;record\";format=json;data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Test Cap"
                           aliases:@[@"test-command"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    XCTAssertNotNil(cap);
    // URN tags are sorted alphabetically — markers (bare keys) sort
    // with keyed tags by key name. Order: data_processing, format,
    // in, out, transform.
    XCTAssertEqualObjects([cap urnString], @"cap:data_processing;format=json;in=media:void;out=\"media:enc=utf-8;record\";transform");
    XCTAssertEqualObjects(cap.primaryAlias, @"test-command");
    XCTAssertNil([cap getStdinMediaUrn], @"stdinType should be nil when not specified");
}

// TEST0314: Cap with description
- (void)test0314_CapWithDescription {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;parse;out=\"media:enc=utf-8;record\";format=json;data" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Parse JSON"
                           aliases:@[@"parse-cmd"]
                       description:@"Parse JSON data"
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    XCTAssertNotNil(cap);
    XCTAssertEqualObjects(cap.capDescription, @"Parse JSON data");
    XCTAssertNil([cap getStdinMediaUrn], @"stdinType should be nil when not specified");
}

// TEST0315: Cap stdin type
- (void)test0315_CapStdinType {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;generate;out=\"media:enc=utf-8;record\";target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    // Test with stdin = nil (does not accept stdin)
    CSCap *cap1 = [CSCap capWithUrn:key
                              title:@"Generate"
                            aliases:@[@"generate"]
                        description:@"Generate embeddings"
                      documentation:nil
                           metadata:@{}
                          args:@[]
                             output:nil
                       metadataJSON:nil];

    XCTAssertNotNil(cap1);
    XCTAssertNil([cap1 getStdinMediaUrn], @"stdinType should be nil when not set");
    XCTAssertFalse([cap1 acceptsStdin], @"Cap should not accept stdin when no stdin source is defined");

    // Test with stdin = media type (accepts stdin) - encoded as arg with stdin source
    NSString *stdinMediaType = @"media:enc=utf-8";
    CSArgSource *stdinSource = [CSArgSource stdinSourceWithMediaUrn:stdinMediaType];
    CSCapArg *stdinArg = [CSCapArg argWithMediaUrn:stdinMediaType
                                          required:YES
                                           sources:@[stdinSource]];
    CSCap *cap2 = [CSCap capWithUrn:key
                              title:@"Generate"
                            aliases:@[@"generate"]
                        description:@"Generate embeddings"
                      documentation:nil
                           metadata:@{}
                               args:@[stdinArg]
                             output:nil
                       metadataJSON:nil];

    XCTAssertNotNil(cap2);
    XCTAssertNotNil([cap2 getStdinMediaUrn], @"stdinType should be set");
    XCTAssertEqualObjects([cap2 getStdinMediaUrn], stdinMediaType, @"stdinType should match the set value");
    XCTAssertTrue([cap2 acceptsStdin], @"Cap should accept stdin");
}

// TEST0110: Cap matching
- (void)test0110_CapMatching {
    NSError *error;
    // Use type=data_processing key=value for proper matching tests
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;transform;out=\"media:enc=utf-8;record\";format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Transform"
                           aliases:@[@"test-command"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    // URN tags are sorted alphabetically
    XCTAssertTrue([cap acceptsRequest:@"cap:format=json;in=media:void;transform;out=\"media:enc=utf-8;record\";type=data_processing"]);
    XCTAssertTrue([cap acceptsRequest:@"cap:format=*;in=media:void;transform;out=\"media:enc=utf-8;record\";type=data_processing"]); // Request wants any format, cap handles json specifically
    XCTAssertTrue([cap acceptsRequest:@"cap:in=media:void;out=\"media:enc=utf-8;record\";type=data_processing"]);
    XCTAssertFalse([cap acceptsRequest:@"cap:in=media:void;out=\"media:enc=utf-8;record\";type=compute"]);
}

// TEST0317: Cap stdin serialization
- (void)test0317_CapStdinSerialization {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;generate;out=\"media:enc=utf-8;record\";target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSString *stdinMediaType = @"media:enc=utf-8";

    // Test copying preserves stdin - encoded as arg with stdin source
    CSArgSource *stdinSource = [CSArgSource stdinSourceWithMediaUrn:stdinMediaType];
    CSCapArg *stdinArg = [CSCapArg argWithMediaUrn:stdinMediaType
                                          required:YES
                                           sources:@[stdinSource]];
    CSCap *original = [CSCap capWithUrn:key
                                  title:@"Generate"
                                aliases:@[@"generate"]
                            description:@"Generate embeddings"
                          documentation:nil
                               metadata:@{@"model": @"sentence-transformer"}
                                   args:@[stdinArg]
                                 output:nil
                           metadataJSON:nil];

    CSCap *copied = [original copy];
    XCTAssertNotNil(copied);
    XCTAssertEqualObjects([original getStdinMediaUrn], [copied getStdinMediaUrn]);
    XCTAssertEqualObjects([copied getStdinMediaUrn], stdinMediaType);
    XCTAssertNotNil([copied getStdinMediaUrn], @"stdinType should be preserved after copy");
}

// TEST0318: Canonical dictionary deserialization
- (void)test0318_CanonicalDictionaryDeserialization {
    // Test CSCap.capWithDictionary with new args format (stdin is part of arg sources)
    NSString *stdinMediaType = @"media:ext=pdf";
    NSDictionary *capDict = @{
        @"urn": @"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata",
        @"title": @"Extract Metadata",
        @"aliases": @[@"extract-metadata"],
        @"cap_description": @"Extract metadata from documents",
        @"metadata": @{@"ext": @"json"},
        @"args": @[
            @{
                @"media_urn": @"media:enc=utf-8;file-path",
                @"required": @YES,
                @"sources": @[
                    @{@"stdin": stdinMediaType},
                    @{@"position": @0}
                ],
                @"arg_description": @"Path to the document file"
            }
        ]
    };

    NSError *error;
    CSCap *cap = [CSCap capWithDictionary:capDict error:&error];

    XCTAssertNil(error, @"Dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Cap should be created from dictionary");
    XCTAssertEqualObjects([cap urnString], @"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata");
    XCTAssertEqualObjects(cap.primaryAlias, @"extract-metadata");
    XCTAssertEqualObjects(cap.capDescription, @"Extract metadata from documents");
    XCTAssertNotNil([cap getStdinMediaUrn], @"stdinType should be set when arg has stdin source");
    XCTAssertEqualObjects([cap getStdinMediaUrn], stdinMediaType, @"stdinType should match stdin source value");

    // Test with missing required fields - should fail hard
    NSDictionary *invalidDict = @{
        @"aliases": @[@"extract-metadata"]
        // Missing "urn" field
    };

    error = nil;
    CSCap *invalidCap = [CSCap capWithDictionary:invalidDict error:&error];

    XCTAssertNotNil(error, @"Should fail when required fields are missing");
    XCTAssertNil(invalidCap, @"Should return nil when deserialization fails");
    XCTAssertTrue([error.localizedDescription containsString:@"urn"], @"Error should mention missing urn field");
}

// TEST6549: Canonical arguments deserialization
- (void)test6549_CanonicalArgumentsDeserialization {
    // Test CSCapArg.argWithDictionary with media_urn format
    NSDictionary *argDict = @{
        @"media_urn": CSMediaString,
        @"required": @YES,
        @"sources": @[
            @{@"position": @0},
            @{@"cli_flag": @"--file_path"}
        ],
        @"arg_description": @"Path to file"
    };

    NSError *error;
    CSCapArg *arg = [CSCapArg argWithDictionary:argDict error:&error];

    XCTAssertNil(error, @"Argument dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(arg, @"Argument should be created from dictionary");
    XCTAssertEqualObjects(arg.mediaUrn, CSMediaString);  // Verify spec ID
    XCTAssertTrue(arg.required, @"Should be a required argument");
    XCTAssertNotNil([arg getPosition], @"Should have position source");
    XCTAssertEqualObjects([arg getPosition], @0);
    XCTAssertEqualObjects([arg getCliFlag], @"--file_path");
}

// TEST6551: Canonical output deserialization
- (void)test6551_CanonicalOutputDeserialization {
    // Test CSCapOutput.outputWithDictionary with media_urn format
    NSDictionary *outputDict = @{
        @"media_urn": CSMediaObject,
        @"output_description": @"JSON metadata object"
    };

    NSError *error;
    CSCapOutput *output = [CSCapOutput outputWithDictionary:outputDict error:&error];

    XCTAssertNil(error, @"Output dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(output, @"Output should be created from dictionary");
    XCTAssertEqualObjects(output.mediaUrn, CSMediaObject);  // Verify spec ID
    XCTAssertEqualObjects(output.outputDescription, @"JSON metadata object");
}

// TEST6553: Canonical validation deserialization
- (void)test6553_CanonicalValidationDeserialization {
    // Test CSMediaValidation.validationWithDictionary
    NSDictionary *validationDict = @{
        @"min_length": @1,
        @"max_length": @255,
        @"pattern": @"^[^\\0]+$",
        @"allowed_values": @[@"json", @"xml", @"yaml"]
    };

    NSError *error;
    CSMediaValidation *validation = [CSMediaValidation validationWithDictionary:validationDict error:&error];

    XCTAssertNil(error, @"Validation dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(validation, @"Validation should be created from dictionary");
    XCTAssertEqualObjects(validation.minLength, @1);
    XCTAssertEqualObjects(validation.maxLength, @255);
    XCTAssertEqualObjects(validation.pattern, @"^[^\\0]+$");
    XCTAssertEqualObjects(validation.allowedValues, (@[@"json", @"xml", @"yaml"]));
}

// TEST6555: Complete cap deserialization
- (void)test6555_CompleteCapDeserialization {
    // Test a complete cap with all nested structures using new args format
    NSString *stdinMediaType = @"media:fmt=json;record";
    NSDictionary *completeCapDict = @{
        @"urn": @"cap:in=media:void;transform;out=\"media:enc=utf-8;record\";format=json;data",
        @"title": @"Transform Data",
        @"aliases": @[@"transform-data"],
        @"cap_description": @"Transform JSON data with validation",
        @"metadata": @{@"engine": @"jq", @"performance": @"high"},
        @"media_defs": @[
            @{
                @"urn": @"media:output",
                @"media_type": @"application/json",
                @"profile_uri": @"https://capdag.com/schema/transform-output"
            }
        ],
        @"args": @[
            @{
                @"media_urn": CSMediaString,
                @"required": @YES,
                @"sources": @[
                    @{@"stdin": stdinMediaType},
                    @{@"position": @0}
                ],
                @"arg_description": @"JQ transformation expression",
                @"validation": @{
                    @"min_length": @1,
                    @"max_length": @1000
                }
            },
            @{
                @"media_urn": CSMediaString,
                @"required": @NO,
                @"sources": @[
                    @{@"cli_flag": @"--ext"}
                ],
                @"arg_description": @"Output format",
                @"default_value": @"json",
                @"validation": @{
                    @"allowed_values": @[@"json", @"yaml", @"xml"]
                }
            }
        ],
        @"output": @{
            @"media_urn": @"media:output",
            @"output_description": @"Transformed data"
        }
    };

    NSError *error;
    CSCap *cap = [CSCap capWithDictionary:completeCapDict error:&error];

    XCTAssertNil(error, @"Complete cap deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Complete cap should be created");

    // Verify basic properties - URN tags are sorted alphabetically
    // Flags sort with key=value pairs by key name: data (flag) < format
    XCTAssertEqualObjects([cap urnString], @"cap:data;format=json;in=media:void;out=\"media:enc=utf-8;record\";transform");
    XCTAssertEqualObjects(cap.primaryAlias, @"transform-data");
    XCTAssertNotNil([cap getStdinMediaUrn], @"stdinType should be set");
    XCTAssertEqualObjects([cap getStdinMediaUrn], stdinMediaType);

    // Verify metadata
    XCTAssertEqualObjects(cap.metadata[@"engine"], @"jq");
    XCTAssertEqualObjects(cap.metadata[@"performance"], @"high");

    // Verify arguments
    XCTAssertEqual([cap getRequiredArgs].count, 1);
    XCTAssertEqual([cap getOptionalArgs].count, 1);

    CSCapArg *requiredArg = [cap getRequiredArgs].firstObject;
    XCTAssertEqualObjects(requiredArg.mediaUrn, CSMediaString);

    CSCapArg *optionalArg = [cap getOptionalArgs].firstObject;
    XCTAssertEqualObjects(optionalArg.mediaUrn, CSMediaString);

    // Verify output
    XCTAssertNotNil(cap.output);
    XCTAssertEqualObjects(cap.output.mediaUrn, @"media:output");
}

// TEST6317: Media urn resolution with registry
- (void)test6317_MediaUrnResolutionThroughRegistry {
    // Caps no longer carry inline media defs; the unified
    // CSFabricRegistry is the only source. This test seeds three
    // specs into a fresh registry and verifies each resolves through
    // CSResolveMediaUrn, plus that an unseeded URN fails hard.
    NSError *error;
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];

    [registry addMediaDef:@{
        @"urn": @"media:custom-output",
        @"media_type": @"application/json",
        @"profile_uri": @"https://example.com/schema/custom-output",
        @"schema": @{
            @"type": @"object",
            @"properties": @{
                @"result": @{@"type": @"string"}
            },
            @"required": @[@"result"]
        }
    }];
    [registry addMediaDef:@{
        @"urn": @"media:text-input",
        @"media_type": @"text/plain",
        @"profile_uri": @"https://example.com/schema/text-input"
    }];
    [registry addMediaDef:@{
        @"urn": CSMediaString,
        @"media_type": @"text/plain",
        @"profile_uri": @"https://capdag.com/schema/string"
    }];

    // Custom spec
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:custom-output", registry, &error);
    XCTAssertNotNil(resolved, @"Should resolve custom URN through registry: %@", error);
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertNotNil(resolved.schema);

    // Text spec
    CSMediaDef *resolvedText = CSResolveMediaUrn(@"media:text-input", registry, &error);
    XCTAssertNotNil(resolvedText, @"Should resolve text URN through registry: %@", error);
    XCTAssertEqualObjects(resolvedText.contentType, @"text/plain");

    // Standard spec
    CSMediaDef *resolvedFromArray = CSResolveMediaUrn(CSMediaString, registry, &error);
    XCTAssertNotNil(resolvedFromArray, @"Should resolve standard URN through registry: %@", error);
    XCTAssertEqualObjects(resolvedFromArray.contentType, @"text/plain");

    // Unseeded URN fails hard. Surfacing the failure is the only
    // honest behaviour — fallbacks would hide the real issue.
    error = nil;
    CSMediaDef *unknown = CSResolveMediaUrn(@"unknown:spec.v1", registry, &error);
    XCTAssertNil(unknown, @"Unseeded URN should fail to resolve");
    XCTAssertNotNil(error, @"Failure must set an error");
}

// MARK: - Cap Manifest Tests

- (void)test6558_CapManifestCreation {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           aliases:@[@"extract-metadata"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"TestComponent"
                                                       version:@"0.1.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"A test component for validation"
                                                     capGroups:@[[[CSCapGroup alloc] initWithName:@"default"
                                                                 caps:@[cap]
                                                          adapterUrns:@[]]]];

    XCTAssertEqualObjects(manifest.name, @"TestComponent");
    XCTAssertEqualObjects(manifest.version, @"0.1.0");
    XCTAssertEqualObjects(manifest.manifestDescription, @"A test component for validation");
    XCTAssertEqual([manifest allCaps].count, 1);
    XCTAssertNil(manifest.author);
}

// TEST149: Cap manifest with author
- (void)test149_CapManifestWithAuthor {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           aliases:@[@"extract-metadata"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifest = [[CSCapManifest manifestWithName:@"TestComponent"
                                                       version:@"0.1.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"A test component for validation"
                                                     capGroups:@[[[CSCapGroup alloc] initWithName:@"default"
                                                                 caps:@[cap]
                                                          adapterUrns:@[]]]]
                                      withAuthor:@"Test Author"];

    XCTAssertEqualObjects(manifest.author, @"Test Author");
}

// TEST6363: Cap manifest with page url
- (void)test6363_CapManifestWithPageUrl {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           aliases:@[@"extract-metadata"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifest = [[[CSCapManifest manifestWithName:@"TestComponent"
                                                       version:@"0.1.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"A test component for validation"
                                                     capGroups:@[[[CSCapGroup alloc] initWithName:@"default"
                                                                 caps:@[cap]
                                                          adapterUrns:@[]]]]
                                       withAuthor:@"Test Author"]
                                       withPageUrl:@"https://github.com/example/test"];

    XCTAssertEqualObjects(manifest.author, @"Test Author");
    XCTAssertEqualObjects(manifest.pageUrl, @"https://github.com/example/test");
}

// TEST6564: Cap manifest dictionary deserialization
- (void)test6564_CapManifestDictionaryDeserialization {
    NSString *stdinMediaType = @"media:ext=pdf";
    NSDictionary *manifestDict = @{
        @"name": @"TestComponent",
        @"version": @"0.1.0",
        @"channel": @"release",
        @"registry_url": [NSNull null],
        @"description": @"A test component for validation",
        @"author": @"Test Author",
        @"page_url": @"https://github.com/example/test",
        @"cap_groups": @[
            @{
                @"name": @"default",
                @"caps": @[
                    @{
                        @"urn": @"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata",
                        @"title": @"Extract Metadata",
                        @"aliases": @[@"extract-metadata"],
                        @"args": @[
                            @{
                                @"media_urn": @"media:enc=utf-8;file-path",
                                @"required": @YES,
                                @"sources": @[
                                    @{@"stdin": stdinMediaType},
                                    @{@"position": @0}
                                ],
                                @"arg_description": @"Path to the document file"
                            }
                        ]
                    }
                ]
            }
        ]
    };

    NSError *error;
    CSCapManifest *manifest = [CSCapManifest manifestWithDictionary:manifestDict error:&error];

    XCTAssertNil(error, @"Manifest dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(manifest, @"Manifest should be created from dictionary");
    XCTAssertEqualObjects(manifest.name, @"TestComponent");
    XCTAssertEqualObjects(manifest.version, @"0.1.0");
    XCTAssertEqualObjects(manifest.manifestDescription, @"A test component for validation");
    XCTAssertEqualObjects(manifest.author, @"Test Author");
    XCTAssertEqualObjects(manifest.pageUrl, @"https://github.com/example/test");
    XCTAssertEqual([manifest allCaps].count, 1);

    CSCap *cap = [manifest allCaps].firstObject;
    XCTAssertEqualObjects([cap urnString], @"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata");
    XCTAssertNotNil([cap getStdinMediaUrn], @"stdinType should be set from arg with stdin source");
    XCTAssertEqualObjects([cap getStdinMediaUrn], stdinMediaType);
}

// TEST6566: Cap manifest required fields
- (void)test6566_CapManifestRequiredFields {
    // Test that deserialization fails when required fields are missing
    NSDictionary *invalidDict = @{@"name": @"TestComponent"};

    NSError *error;
    CSCapManifest *manifest = [CSCapManifest manifestWithDictionary:invalidDict error:&error];

    XCTAssertNil(manifest, @"Manifest creation should fail with missing required fields");
    XCTAssertNotNil(error, @"Error should be set when required fields are missing");
    XCTAssertEqualObjects(error.domain, @"CSCapManifestError");
    XCTAssertEqual(error.code, 1007);
}

// TEST6569: Cap manifest with multiple caps
- (void)test6569_CapManifestWithMultipleCaps {
    NSError *error;
    CSCapUrn *key1 = [CSCapUrn fromString:@"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata" error:&error];
    XCTAssertNotNil(key1, @"Failed to create cap URN: %@", error);

    CSCapUrn *key2 = [CSCapUrn fromString:@"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=outline" error:&error];
    XCTAssertNotNil(key2, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];

    CSCap *cap1 = [CSCap capWithUrn:key1
                             title:@"Extract Metadata"
                           aliases:@[@"extract-metadata"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCap *cap2 = [CSCap capWithUrn:key2
                             title:@"Extract Outline"
                           aliases:@[@"extract-outline"]
                       description:nil
                     documentation:nil
                          metadata:@{@"supports_outline": @"true"}
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"MultiCapComponent"
                                                       version:@"1.0.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"Component with multiple caps"
                                                     capGroups:@[[[CSCapGroup alloc] initWithName:@"default"
                                                                 caps:@[cap1, cap2]
                                                          adapterUrns:@[]]]];

    XCTAssertEqual([manifest allCaps].count, 2);
    XCTAssertEqualObjects([[manifest allCaps][0] urnString], @"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=metadata");
    XCTAssertEqualObjects([[manifest allCaps][1] urnString], @"cap:extract;in=media:void;out=\"media:enc=utf-8;record\";target=outline");
    XCTAssertEqualObjects(cap2.metadata[@"supports_outline"], @"true");
}

// TEST6571: Cap manifest empty caps
- (void)test6571_CapManifestEmptyCaps {
    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"EmptyComponent"
                                                       version:@"1.0.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"Component with no caps"
                                                     capGroups:@[]];

    XCTAssertEqual([manifest allCaps].count, 0);

    // Test dictionary serialization preserves empty array
    NSDictionary *manifestDict = @{
        @"name": @"EmptyComponent",
        @"version": @"1.0.0",
        @"channel": @"release",
        @"registry_url": [NSNull null],
        @"description": @"Component with no caps",
        @"cap_groups": @[]
    };

    NSError *error;
    CSCapManifest *deserializedManifest = [CSCapManifest manifestWithDictionary:manifestDict error:&error];

    XCTAssertNil(error, @"Empty cap_groups manifest should deserialize successfully");
    XCTAssertNotNil(deserializedManifest);
    XCTAssertEqual([deserializedManifest allCaps].count, 0);
}

// TEST6573: Cap manifest optional author field
- (void)test6573_CapManifestOptionalAuthorField {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;validate;out=\"media:enc=utf-8;record\";file" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Validate"
                           aliases:@[@"validate"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifestWithoutAuthor = [CSCapManifest manifestWithName:@"ValidatorComponent"
                                                       version:@"1.0.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"File validation component"
                                                     capGroups:@[[[CSCapGroup alloc] initWithName:@"default"
                                                                 caps:@[cap]
                                                          adapterUrns:@[]]]];

    // Manifest without author should not include author field in dictionary representation
    NSDictionary *manifestDict = @{
        @"name": @"ValidatorComponent",
        @"version": @"1.0.0",
        @"channel": @"release",
        @"registry_url": [NSNull null],
        @"description": @"File validation component",
        @"cap_groups": @[
            @{
                @"name": @"default",
                @"caps": @[
                    @{
                        @"urn": @"cap:in=media:void;validate;out=\"media:enc=utf-8;record\";file",
                        @"title": @"Validate",
                        @"aliases": @[@"validate"],
                        @"arguments": @{
                            @"required": @[],
                            @"optional": @[]
                        }
                    }
                ]
            }
        ]
    };

    CSCapManifest *deserializedManifest = [CSCapManifest manifestWithDictionary:manifestDict error:&error];

    XCTAssertNil(error, @"Manifest without author should deserialize successfully");
    XCTAssertNotNil(deserializedManifest);
    XCTAssertNil(deserializedManifest.author, @"Author should be nil when not provided");
}

// TEST6371: Cap manifest compatibility
- (void)test6371_CapManifestCompatibility {
    // Test that manifest format is compatible between different component types
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;process;out=\"media:enc=utf-8;record\"" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Process"
                           aliases:@[@"process"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                         args:args
                            output:nil
                      metadataJSON:nil];

    // Create manifest similar to what a cartridge would have
    CSCapManifest *cartridgeStyleManifest = [CSCapManifest manifestWithName:@"CartridgeComponent"
                                                       version:@"0.1.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"Cartridge-style component"
                                                     capGroups:@[[[CSCapGroup alloc] initWithName:@"default"
                                                                 caps:@[cap]
                                                          adapterUrns:@[]]]];

    // Create manifest similar to what a candidate would have
    CSCapManifest *candidateStyleManifest = [CSCapManifest manifestWithName:@"CandidateComponent"
                                                       version:@"0.1.0"
                                                       channel:CSCartridgeChannelRelease
                                                   registryURL:nil
                                                   description:@"Candidate-style component"
                                                     capGroups:@[[[CSCapGroup alloc] initWithName:@"default"
                                                                 caps:@[cap]
                                                          adapterUrns:@[]]]];

    // Both should have the same structure
    XCTAssertNotNil(cartridgeStyleManifest.name);
    XCTAssertNotNil(cartridgeStyleManifest.version);
    XCTAssertNotNil(cartridgeStyleManifest.manifestDescription);
    XCTAssertNotNil(cartridgeStyleManifest.capGroups);

    XCTAssertNotNil(candidateStyleManifest.name);
    XCTAssertNotNil(candidateStyleManifest.version);
    XCTAssertNotNil(candidateStyleManifest.manifestDescription);
    XCTAssertNotNil(candidateStyleManifest.capGroups);

    // Same cap structure
    XCTAssertEqual([cartridgeStyleManifest allCaps].count, [candidateStyleManifest allCaps].count);
    XCTAssertEqualObjects([[cartridgeStyleManifest allCaps].firstObject urnString],
                         [[candidateStyleManifest allCaps].firstObject urnString]);
}

// TEST6578: Argument creation with new a p i
- (void)test6578_ArgumentCreationWithNewAPI {
    // Test creating arguments with the new CSCapArg API
    CSArgSource *positionSource = [CSArgSource positionSource:0];
    CSArgSource *cliFlagSource = [CSArgSource cliFlagSource:@"--input"];
    CSCapArg *stringArg = [CSCapArg argWithMediaUrn:CSMediaString
                                           required:YES
                                            sources:@[positionSource, cliFlagSource]
                                     argDescription:@"Input text"
                                       defaultValue:nil];

    XCTAssertNotNil(stringArg);
    XCTAssertEqualObjects(stringArg.mediaUrn, CSMediaString);
    XCTAssertEqualObjects([stringArg getCliFlag], @"--input");
    XCTAssertEqualObjects([stringArg getPosition], @0);

    // Test with integer spec
    CSCapArg *intArg = [CSCapArg argWithMediaUrn:CSMediaInteger
                                        required:NO
                                         sources:@[[CSArgSource cliFlagSource:@"--count"]]
                                  argDescription:@"Count value"
                                    defaultValue:@10];

    XCTAssertNotNil(intArg);
    XCTAssertEqualObjects(intArg.mediaUrn, CSMediaInteger);
    XCTAssertEqualObjects(intArg.defaultValue, @10);

    // Test with object spec
    CSCapArg *objArg = [CSCapArg argWithMediaUrn:CSMediaObject
                                        required:YES
                                         sources:@[[CSArgSource cliFlagSource:@"--data"]]
                                  argDescription:@"JSON data"
                                    defaultValue:nil];

    XCTAssertNotNil(objArg);
    XCTAssertEqualObjects(objArg.mediaUrn, CSMediaObject);
}

// TEST115: Test CapArg serialization and deserialization with multiple sources
- (void)test115_capArgSerialization {
    CSArgSource *cliFlagSource = [CSArgSource cliFlagSource:@"--name"];
    CSArgSource *positionSource = [CSArgSource positionSource:0];
    NSDictionary *metadata = @{
        @"kind": @"example",
        @"flags": @[@YES, @NO]
    };

    CSCapArg *arg = [CSCapArg argWithMediaUrn:CSMediaString
                                     required:YES
                                      sources:@[cliFlagSource, positionSource]
                               argDescription:@"The name argument"
                                 defaultValue:@400];
    [arg setMetadata:metadata];

    NSDictionary *serialized = [arg toDictionary];
    XCTAssertEqualObjects(serialized[@"media_urn"], CSMediaString);
    XCTAssertEqualObjects(serialized[@"required"], @YES);
    XCTAssertEqualObjects(serialized[@"default_value"], @400);
    XCTAssertEqualObjects(serialized[@"metadata"], metadata);

    NSError *error = nil;
    CSCapArg *deserialized = [CSCapArg argWithDictionary:serialized error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(deserialized);
    XCTAssertEqualObjects(deserialized.mediaUrn, arg.mediaUrn);
    XCTAssertEqual(deserialized.required, arg.required);
    XCTAssertEqualObjects(deserialized.argDescription, arg.argDescription);
    XCTAssertEqualObjects(deserialized.defaultValue, arg.defaultValue);
    XCTAssertEqualObjects(deserialized.metadata, arg.metadata);
    XCTAssertEqual(deserialized.sources.count, 2);
}

// TEST116: Test CapArg constructor methods basic and with_description create args correctly
- (void)test116_capArgConstructors {
    CSCapArg *basicArg = [CSCapArg argWithMediaUrn:CSMediaString
                                          required:YES
                                           sources:@[[CSArgSource cliFlagSource:@"--name"]]];
    XCTAssertEqualObjects(basicArg.mediaUrn, CSMediaString);
    XCTAssertTrue(basicArg.required);
    XCTAssertEqual(basicArg.sources.count, 1u);
    XCTAssertNil(basicArg.argDescription);
    XCTAssertNil(basicArg.defaultValue);

    CSCapArg *describedArg = [CSCapArg argWithMediaUrn:CSMediaInteger
                                              required:NO
                                               sources:@[[CSArgSource positionSource:0]]
                                        argDescription:@"The count argument"
                                          defaultValue:@10];
    XCTAssertEqualObjects(describedArg.mediaUrn, CSMediaInteger);
    XCTAssertFalse(describedArg.required);
    XCTAssertEqualObjects(describedArg.argDescription, @"The count argument");
    XCTAssertEqualObjects(describedArg.defaultValue, @10);
}

// TEST597: CapArg::with_full_definition stores all fields including optional ones
- (void)test597_capArgWithFullDefinition {
    NSDictionary *defaultValue = @{
        @"chunk_size": @400,
        @"timestamps": @NO
    };
    NSDictionary *metadata = @{@"hint": @"enter name"};
    CSCapArg *arg = [CSCapArg argWithMediaUrn:CSMediaString
                                     required:YES
                                      sources:@[[CSArgSource cliFlagSource:@"--name"]]
                               argDescription:@"User name"
                                 defaultValue:defaultValue];
    [arg setMetadata:metadata];

    XCTAssertEqualObjects(arg.mediaUrn, CSMediaString);
    XCTAssertTrue(arg.required);
    XCTAssertEqualObjects(arg.argDescription, @"User name");
    XCTAssertEqualObjects(arg.defaultValue, defaultValue);
    XCTAssertEqualObjects(arg.metadata, metadata);

    CSCapArg *copy = [arg copy];
    [copy clearMetadata];
    XCTAssertNil(copy.metadata);
    [copy setMetadata:@"new"];
    XCTAssertEqualObjects(copy.metadata, @"new");
}

// TEST6580: Output creation with new a p i
- (void)test6580_OutputCreationWithNewAPI {
    // Test creating output with the new mediaUrn API
    CSCapOutput *output = [CSCapOutput outputWithMediaUrn:CSMediaObject
                                        outputDescription:@"JSON output"];

    XCTAssertNotNil(output);
    XCTAssertEqualObjects(output.mediaUrn, CSMediaObject);
    XCTAssertEqualObjects(output.outputDescription, @"JSON output");

    // Test with custom spec ID
    CSCapOutput *customOutput = [CSCapOutput outputWithMediaUrn:@"media:custom-output"
                                              outputDescription:@"Custom output"];

    XCTAssertNotNil(customOutput);
    XCTAssertEqualObjects(customOutput.mediaUrn, @"media:custom-output");
}

// Mirrors TEST920 in capdag/src/cap/definition.rs and the JS
// testJS_capDocumentationRoundTrip test. The body is non-trivial — multi-line,
// embedded backticks and double quotes, Unicode dingbat (\u2605) — so any
// escaping mismatch between dictionary serialization here and the Rust /
// JS counterparts surfaces as a failed round-trip.
- (void)test6583_CapDocumentationRoundTrip {
    NSError *error;
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:in=media:void;documented;out=\"media:enc=utf-8;record\"" error:&error];
    XCTAssertNotNil(urn);

    NSString *body = @"# Documented Cap\r\n\nDoes the thing.\n\n```bash\necho \"hi\"\n```\n\nSee also: \u2605\n";

    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Documented Cap"
                           aliases:@[@"documented"]
                       description:@"short"
                     documentation:body
                          metadata:@{}
                              args:@[]
                            output:nil
                      metadataJSON:nil];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects(cap.documentation, body, @"Constructor must store documentation verbatim");

    NSDictionary *dict = [cap toDictionary];
    XCTAssertEqualObjects(dict[@"documentation"], body, @"toDictionary must include documentation when set");

    NSError *parseError;
    CSCap *restored = [CSCap capWithDictionary:dict error:&parseError];
    XCTAssertNotNil(restored, @"capWithDictionary must succeed: %@", parseError);
    XCTAssertEqualObjects(restored.documentation, body, @"capWithDictionary must restore documentation body verbatim");
    XCTAssertEqualObjects(restored, cap, @"Round-tripped cap must equal the original");

    // Independent identity through copy and the equality contract.
    CSCap *copied = [cap copy];
    XCTAssertEqualObjects(copied.documentation, body);
    XCTAssertEqualObjects(copied, cap);
}

// When documentation is nil, toDictionary must omit the field entirely. This
// matches the Rust serializer's skip-when-None semantics and the JS toJSON
// behaviour. A regression where nil is emitted as `documentation: NSNull` (or
// simply not omitted) would break the symmetric round-trip with Rust.
- (void)test0369_CapDocumentationOmittedWhenNil {
    NSError *error;
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:in=media:void;undocumented;out=\"media:enc=utf-8;record\"" error:&error];
    XCTAssertNotNil(urn);

    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Undocumented Cap"
                           aliases:@[@"undocumented"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                              args:@[]
                            output:nil
                      metadataJSON:nil];
    XCTAssertNotNil(cap);
    XCTAssertNil(cap.documentation);

    NSDictionary *dict = [cap toDictionary];
    XCTAssertNil(dict[@"documentation"], @"toDictionary must omit documentation when nil");
    XCTAssertFalse([dict.allKeys containsObject:@"documentation"], @"documentation key must be absent, not nil-valued");

    // Empty-string documentation in the source dictionary must round-trip
    // to nil — the parser collapses empty strings to absence so callers
    // never see the difference between "" and missing.
    NSMutableDictionary *withEmpty = [dict mutableCopy];
    withEmpty[@"documentation"] = @"";
    NSError *parseError;
    CSCap *parsed = [CSCap capWithDictionary:withEmpty error:&parseError];
    XCTAssertNotNil(parsed, @"capWithDictionary must succeed: %@", parseError);
    XCTAssertNil(parsed.documentation, @"Empty string in documentation must collapse to nil");
}

// Documentation propagates from a mediaDefs definition through
// CSResolveMediaUrn into the resolved CSMediaDef. Mirrors TEST924 on the
// Rust side and testJS_mediaDefDocumentationPropagatesThroughResolve on
// the JS side.
- (void)test0370_MediaDefDocumentationPropagatesThroughResolve {
    NSString *body = @"## Markdown body\n\nWith `code` and a [link](https://example.com).";

    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": @"media:enc=utf-8;doc-test",
            @"media_type": @"text/plain",
            @"title": @"Documented",
            @"description": @"short desc",
            @"documentation": body
        }
    ];

    NSError *error;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:enc=utf-8;doc-test", registryWithSpecs(mediaDefs), &error);
    XCTAssertNotNil(resolved, @"Resolution must succeed: %@", error);
    XCTAssertEqualObjects(resolved.documentation, body, @"documentation must propagate into CSMediaDef");
    // The short description must remain distinct from the long markdown
    // body — they are different fields with different semantics.
    XCTAssertEqualObjects(resolved.descriptionText, @"short desc");

    // Missing documentation must collapse to nil, not @"" or NSNull.
    NSArray<NSDictionary *> *noDocSpecs = @[
        @{ @"urn": @"media:enc=utf-8;doc-test", @"media_type": @"text/plain", @"title": @"No Doc" }
    ];
    CSMediaDef *noDoc = CSResolveMediaUrn(@"media:enc=utf-8;doc-test", registryWithSpecs(noDocSpecs), &error);
    XCTAssertNotNil(noDoc);
    XCTAssertNil(noDoc.documentation, @"Missing documentation must resolve to nil");

    // Empty-string documentation must collapse to nil.
    NSArray<NSDictionary *> *emptyDocSpecs = @[
        @{ @"urn": @"media:enc=utf-8;doc-test", @"media_type": @"text/plain", @"title": @"Empty", @"documentation": @"" }
    ];
    CSMediaDef *emptyDoc = CSResolveMediaUrn(@"media:enc=utf-8;doc-test", registryWithSpecs(emptyDocSpecs), &error);
    XCTAssertNotNil(emptyDoc);
    XCTAssertNil(emptyDoc.documentation, @"Empty string in documentation must collapse to nil");
}

// TEST0371: Cap version zero round trip
- (void)test0371_CapVersionZeroRoundTrip {
    // version=0 (default) must not appear in serialized dict; absent dict key must deserialize as 0.
    NSError *error;
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:test-version-zero;in=media:void;out=media:void" error:&error];
    XCTAssertNotNil(urn, @"URN parse failed: %@", error);

    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Version Zero"
                           aliases:@[@"version-zero"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                              args:@[]
                            output:nil
                      metadataJSON:nil];
    XCTAssertEqual(cap.version, (uint32_t)0, @"Default version must be 0");

    NSDictionary *dict = [cap toDictionary];
    XCTAssertNil(dict[@"version"], @"version=0 must be omitted from serialized dict");

    // Deserialize from a dict that has no "version" key — must come back as 0.
    NSDictionary *dictWithoutVersion = @{
        @"urn": @"cap:test-version-zero;in=media:void;out=media:void",
        @"title": @"Version Zero",
        @"aliases": @[@"version-zero"],
        @"metadata": @{}
    };
    CSCap *roundTripped = [CSCap capWithDictionary:dictWithoutVersion error:&error];
    XCTAssertNotNil(roundTripped, @"Deserialization failed: %@", error);
    XCTAssertEqual(roundTripped.version, (uint32_t)0, @"Absent version key must deserialize as 0");
}

// TEST0372: Cap version non zero round trip
- (void)test0372_CapVersionNonZeroRoundTrip {
    // version=3 must survive serialize → dict → deserialize with value preserved.
    NSError *error;
    NSDictionary *dictWithVersion = @{
        @"urn": @"cap:test-version-three;in=media:void;out=media:void",
        @"title": @"Version Three",
        @"aliases": @[@"version-three"],
        @"metadata": @{},
        @"version": @3
    };
    CSCap *cap = [CSCap capWithDictionary:dictWithVersion error:&error];
    XCTAssertNotNil(cap, @"Deserialization with version=3 failed: %@", error);
    XCTAssertEqual(cap.version, (uint32_t)3, @"version must deserialize as 3");

    NSDictionary *serialized = [cap toDictionary];
    XCTAssertNotNil(serialized[@"version"], @"version=3 must be present in serialized dict");
    XCTAssertEqualObjects(serialized[@"version"], @3, @"Serialized version must equal 3");

    // Round-trip through dict again.
    CSCap *roundTripped = [CSCap capWithDictionary:serialized error:&error];
    XCTAssertNotNil(roundTripped, @"Second deserialization failed: %@", error);
    XCTAssertEqual(roundTripped.version, (uint32_t)3, @"version must survive full round-trip");
}

// ===========================================================================
// Shared parity tests 7100-7104: CSCapArg streamUrn / isMainInputForInSpec:.
// Same substantive assertions in every capdag mirror (rust, go, js, objc, py).
// ===========================================================================

// TEST7100: streamUrn returns the stdin source's URN when it differs from the declared slot media URN — the stdin URN, not the slot URN, is what the runtime demuxes the argument's input stream by.
- (void)test7100_StreamUrnReturnsStdinSourceUrnWhenItDiffersFromSlotUrn {
    CSCapArg *arg = [CSCapArg argWithMediaUrn:@"media:enc=utf-8;file-path"
                                     required:YES
                                      sources:@[[CSArgSource stdinSourceWithMediaUrn:@"media:ext=pdf;pdf-stream"]]];
    XCTAssertEqualObjects([arg streamUrn], @"media:ext=pdf;pdf-stream",
                          @"streamUrn must return the stdin source URN");
    XCTAssertNotEqualObjects([arg streamUrn], arg.mediaUrn,
                             @"stream URN must differ from the declared slot media URN here");
}

// TEST7101: streamUrn falls back to the declared slot media URN when the argument declares no stdin source — a producer-fed argument may be delivered by its declared URN without ever appearing on stdin.
- (void)test7101_StreamUrnFallsBackToDeclaredMediaUrnWithoutStdinSource {
    CSCapArg *arg = [CSCapArg argWithMediaUrn:@"media:enc=utf-8;system-prompt"
                                     required:YES
                                      sources:@[[CSArgSource cliFlagSource:@"--system-prompt"]]];
    XCTAssertEqualObjects([arg streamUrn], @"media:enc=utf-8;system-prompt",
                          @"streamUrn must fall back to the declared media URN");
}

// TEST7102: isMainInputForInSpec: is YES when the stdin URN is order-theoretically EQUIVALENT to the cap's in= spec even when the two strings list their tags in a different order — the comparison is the media-URN equivalence predicate, never a string comparison.
- (void)test7102_IsMainInputTrueOnTagOrderInsensitiveEquivalenceToInSpec {
    NSError *error;
    CSMediaUrn *inSpec = [CSMediaUrn fromString:@"media:ext=pdf;pdf-stream" error:&error];
    XCTAssertNotNil(inSpec, @"Failed to parse in= spec: %@", error);

    // Same tags, different order.
    CSCapArg *arg = [CSCapArg argWithMediaUrn:@"media:enc=utf-8;file-path"
                                     required:YES
                                      sources:@[[CSArgSource stdinSourceWithMediaUrn:@"media:pdf-stream;ext=pdf"]]];
    XCTAssertTrue([arg isMainInputForInSpec:inSpec],
                  @"tag-order-insensitive equivalent stdin URN must be the main input");
    // The raw strings genuinely differ — proves the match is equivalence,
    // not string equality.
    XCTAssertNotEqualObjects([inSpec toString], @"media:pdf-stream;ext=pdf",
                             @"raw spec strings must differ for this test to be meaningful");
}

// TEST7103: isMainInputForInSpec: is NO for cli_flag-only and position-only arguments (no stdin source means never the main input, whatever the declared slot URN says), and NO when the stdin URN is not equivalent to in=.
- (void)test7103_IsMainInputFalseWithoutEquivalentStdinSource {
    NSError *error;
    CSMediaUrn *inSpec = [CSMediaUrn fromString:@"media:ext=pdf;pdf-stream" error:&error];
    XCTAssertNotNil(inSpec, @"Failed to parse in= spec: %@", error);

    // Slot URN even matches in= — irrelevant without a stdin source.
    CSCapArg *cliFlagOnly = [CSCapArg argWithMediaUrn:@"media:ext=pdf;pdf-stream"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--input"]]];
    XCTAssertFalse([cliFlagOnly isMainInputForInSpec:inSpec],
                   @"cli_flag-only argument is never the main input");

    CSCapArg *positionOnly = [CSCapArg argWithMediaUrn:@"media:ext=pdf;pdf-stream"
                                              required:YES
                                               sources:@[[CSArgSource positionSource:0]]];
    XCTAssertFalse([positionOnly isMainInputForInSpec:inSpec],
                   @"position-only argument is never the main input");

    CSCapArg *nonEquivalentStdin = [CSCapArg argWithMediaUrn:@"media:enc=utf-8;system-prompt"
                                                    required:NO
                                                     sources:@[[CSArgSource stdinSourceWithMediaUrn:@"media:enc=utf-8;system-prompt"]]];
    XCTAssertFalse([nonEquivalentStdin isMainInputForInSpec:inSpec],
                   @"stdin URN not equivalent to in= must not be the main input");
}

// TEST7104: A realistic multi-arg cap (one stdin main input; one required, defaultless cli_flag arg; several defaulted cli_flag args): exactly one argument is the main input, and partitioning the remaining arguments by required-without-default vs has-default yields the expected sets.
- (void)test7104_MultiArgCapExactlyOneMainInputAndPartitionOfRest {
    NSError *error;
    CSMediaUrn *inSpec = [CSMediaUrn fromString:@"media:ext=pdf;pdf-stream" error:&error];
    XCTAssertNotNil(inSpec, @"Failed to parse in= spec: %@", error);

    // Main input may ALSO be delivered by cli-flag; stdin is the defining route.
    CSCapArg *mainArg = [CSCapArg argWithMediaUrn:@"media:enc=utf-8;file-path"
                                         required:YES
                                          sources:@[[CSArgSource stdinSourceWithMediaUrn:@"media:pdf-stream;ext=pdf"],
                                                    [CSArgSource cliFlagSource:@"--input"]]];
    CSCapArg *questionArg = [CSCapArg argWithMediaUrn:@"media:enc=utf-8;question"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--question"]]];
    CSCapArg *maxTokensArg = [CSCapArg argWithMediaUrn:@"media:max-tokens;numeric"
                                              required:NO
                                               sources:@[[CSArgSource cliFlagSource:@"--max-tokens"]]
                                        argDescription:nil
                                          defaultValue:@1024];
    CSCapArg *temperatureArg = [CSCapArg argWithMediaUrn:@"media:numeric;temperature"
                                                required:NO
                                                 sources:@[[CSArgSource cliFlagSource:@"--temperature"]]
                                          argDescription:nil
                                            defaultValue:@0.7];
    CSCapArg *systemPromptArg = [CSCapArg argWithMediaUrn:@"media:enc=utf-8;system-prompt"
                                                 required:NO
                                                  sources:@[[CSArgSource cliFlagSource:@"--system-prompt"]]
                                           argDescription:nil
                                             defaultValue:@"You are a helpful assistant."];
    NSArray<CSCapArg *> *args = @[mainArg, questionArg, maxTokensArg, temperatureArg, systemPromptArg];

    NSMutableArray<NSString *> *mainInputs = [NSMutableArray array];
    NSMutableArray<NSString *> *requiredWithoutDefault = [NSMutableArray array];
    NSMutableArray<NSString *> *withDefault = [NSMutableArray array];
    for (CSCapArg *arg in args) {
        if ([arg isMainInputForInSpec:inSpec]) {
            [mainInputs addObject:arg.mediaUrn];
            continue;
        }
        if (arg.required && arg.defaultValue == nil) {
            [requiredWithoutDefault addObject:arg.mediaUrn];
        } else if (arg.defaultValue != nil) {
            [withDefault addObject:arg.mediaUrn];
        }
    }

    XCTAssertEqualObjects(mainInputs, @[@"media:enc=utf-8;file-path"],
                          @"exactly one argument must be the main input");
    XCTAssertEqualObjects(requiredWithoutDefault, @[@"media:enc=utf-8;question"],
                          @"required-without-default partition");
    NSArray<NSString *> *expectedWithDefault = @[
        @"media:max-tokens;numeric",
        @"media:numeric;temperature",
        @"media:enc=utf-8;system-prompt"
    ];
    XCTAssertEqualObjects(withDefault, expectedWithDefault, @"has-default partition");
}

@end
