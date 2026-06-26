//
//  CSMediaDefTests.m
//  Tests for CSMediaDef metadata propagation
//

#import <XCTest/XCTest.h>
#import "CSMediaDef.h"
#import "CSFabricRegistry.h"

@interface CSMediaDefTests : XCTestCase
@end

static CSFabricRegistry *registryWithSpecs(NSArray<NSDictionary *> *specs) {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] init];
    for (NSDictionary *spec in specs) {
        [registry addMediaDef:spec];
    }
    return registry;
}


@implementation CSMediaDefTests

// TEST0145: Metadata propagation from object def
- (void)test0145_MetadataPropagationFromObjectDef {
    // Create a media definition with metadata
    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": @"media:custom-setting",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com/schema",
            @"title": @"Custom Setting",
            @"description": @"A custom setting",
            @"metadata": @{
                @"category_key": @"interface",
                @"ui_type": @"SETTING_UI_TYPE_CHECKBOX",
                @"subcategory_key": @"appearance",
                @"display_index": @5
            }
        }
    ];

    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:custom-setting", registryWithSpecs(mediaDefs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqualObjects(resolved.metadata[@"category_key"], @"interface", @"Should have category_key");
    XCTAssertEqualObjects(resolved.metadata[@"ui_type"], @"SETTING_UI_TYPE_CHECKBOX", @"Should have ui_type");
    XCTAssertEqualObjects(resolved.metadata[@"subcategory_key"], @"appearance", @"Should have subcategory_key");
    XCTAssertEqualObjects(resolved.metadata[@"display_index"], @5, @"Should have display_index");
}

// TEST0146: Metadata nil by default
- (void)test0146_MetadataNilByDefault {
    // Media defs without metadata field should have nil metadata
    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
            @"profile_uri": @"https://capdag.com/schema/string"
        }
    ];

    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(CSMediaString, registryWithSpecs(mediaDefs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNil(resolved.metadata, @"Should have nil metadata when not provided");
}

// TEST0147: Metadata with validation
- (void)test0147_MetadataWithValidation {
    // Ensure metadata and validation can coexist
    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": @"media:bounded-number;numeric",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com/schema",
            @"title": @"Bounded Number",
            @"validation": @{
                @"min": @0,
                @"max": @100
            },
            @"metadata": @{
                @"category_key": @"inference",
                @"ui_type": @"SETTING_UI_TYPE_SLIDER"
            }
        }
    ];

    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:bounded-number;numeric", registryWithSpecs(mediaDefs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");

    // Verify validation
    XCTAssertNotNil(resolved.validation, @"Should have validation");
    XCTAssertEqualObjects(resolved.validation.min, @0, @"Should have min validation");
    XCTAssertEqualObjects(resolved.validation.max, @100, @"Should have max validation");

    // Verify metadata
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqualObjects(resolved.metadata[@"category_key"], @"inference", @"Should have category_key");
    XCTAssertEqualObjects(resolved.metadata[@"ui_type"], @"SETTING_UI_TYPE_SLIDER", @"Should have ui_type");
}

// TEST0156: Resolve media urn not found
- (void)test0156_ResolveMediaUrnNotFound {
    // Should fail hard for unknown media URNs
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:unknown;type", registryWithSpecs(@[]), &error);

    XCTAssertNotNil(error, @"Should have error for unknown media URN");
    XCTAssertNil(resolved, @"Should not resolve unknown media URN");
    XCTAssertEqual(error.code, CSMediaDefErrorUnresolvableMediaUrn, @"Should be UNRESOLVABLE_MEDIA_URN error");
}

// Extensions field tests

- (void)test0157_ExtensionsPropagationFromObjectDef {
    // Create a media definition with extensions array
    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": @"media:ext=pdf",
            @"media_type": @"application/pdf",
            @"profile_uri": @"https://capdag.com/schema/pdf",
            @"title": @"PDF Document",
            @"description": @"A PDF document",
            @"extensions": @[@"pdf"]
        }
    ];

    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:ext=pdf", registryWithSpecs(mediaDefs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Should have extensions array");
    XCTAssertEqual(resolved.extensions.count, 1, @"Should have one extension");
    XCTAssertEqualObjects(resolved.extensions[0], @"pdf", @"Should have pdf extension");
}

// TEST0158: Extensions empty when not set
- (void)test0158_ExtensionsEmptyWhenNotSet {
    // Media defs without extensions field should have empty array
    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": @"media:enc=utf-8;text",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com"
        }
    ];

    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:enc=utf-8;text", registryWithSpecs(mediaDefs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Extensions should not be nil");
    XCTAssertEqual(resolved.extensions.count, 0, @"Should have empty extensions array when not provided");
}

// TEST0159: Extensions with metadata and validation
- (void)test0159_ExtensionsWithMetadataAndValidation {
    // Ensure extensions, metadata, and validation can coexist
    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": @"media:custom-output",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema",
            @"title": @"Custom Output",
            @"validation": @{
                @"min_length": @1,
                @"max_length": @1000
            },
            @"metadata": @{
                @"category": @"output"
            },
            @"extensions": @[@"json"]
        }
    ];

    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:custom-output", registryWithSpecs(mediaDefs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");

    // Verify all fields are present
    XCTAssertNotNil(resolved.validation, @"Should have validation");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqual(resolved.extensions.count, 1, @"Should have one extension");
    XCTAssertEqualObjects(resolved.extensions[0], @"json", @"Should have json extension");
}

// TEST0160: Multiple extensions
- (void)test0160_MultipleExtensions {
    // Test multiple extensions in a media def
    NSArray<NSDictionary *> *mediaDefs = @[
        @{
            @"urn": @"media:image;jpeg",
            @"media_type": @"image/jpeg",
            @"profile_uri": @"https://capdag.com/schema/jpeg",
            @"title": @"JPEG Image",
            @"description": @"JPEG image data",
            @"extensions": @[@"jpg", @"jpeg"]
        }
    ];

    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:image;jpeg", registryWithSpecs(mediaDefs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Should have extensions array");
    XCTAssertEqual(resolved.extensions.count, 2, @"Should have two extensions");
    XCTAssertEqualObjects(resolved.extensions[0], @"jpg", @"Should have jpg extension first");
    XCTAssertEqualObjects(resolved.extensions[1], @"jpeg", @"Should have jpeg extension second");
}

// Duplicate URN validation tests

// `CSValidateNoMediaDefDuplicates` was removed when inline cap
// `media_defs` arrays were dropped. The function validated an
// inline-array invariant that no longer arises — caps reference
// media URNs and the unified `CSFabricRegistry` is the source of
// truth. The four duplicate-array tests that lived here are
// intentionally absent.

#pragma mark - ResolvedMediaDef predicate tests

// TEST099: The identity media (`media:`) carries no encoding, no record
// marker, and no format. The old isBinary delegate is gone (binary/text is
// no longer a distinction); a media is text-representable iff it declares enc=.
- (void)test099_resolved_is_binary {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:",
        @"media_type": @"application/octet-stream",
        @"title": @"Binary"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertFalse(CSMediaUrnHasEncoding(resolved.mediaUrn), @"media: has no enc=");
    XCTAssertFalse([resolved isRecord]);
    XCTAssertFalse([resolved isJSON]);
}

// TEST100: Test ResolvedMediaDef is_record returns true when record marker is present
- (void)test100_resolved_is_record {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:enc=utf-8;record",
        @"media_type": @"application/json",
        @"title": @"Object"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:enc=utf-8;record", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isRecord]);
    XCTAssertTrue([resolved isScalar], @"record without list marker is scalar");
    XCTAssertFalse([resolved isList]);
}

// TEST101: Test ResolvedMediaDef is_scalar returns true when list marker is absent
- (void)test101_resolved_is_scalar {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:enc=utf-8",
        @"media_type": @"text/plain",
        @"title": @"String"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:enc=utf-8", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isScalar]);
    XCTAssertFalse([resolved isRecord]);
    XCTAssertFalse([resolved isList]);
}

// TEST102: Test ResolvedMediaDef is_list returns true when list marker is present
- (void)test102_resolved_is_list {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:enc=utf-8;list",
        @"media_type": @"application/json",
        @"title": @"String Array"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:enc=utf-8;list", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isList]);
    XCTAssertFalse([resolved isRecord]);
    XCTAssertFalse([resolved isScalar]);
}

// TEST103: Test ResolvedMediaDef is_json returns true when fmt=json tag is present
- (void)test103_resolved_is_json {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:fmt=json;record",
        @"media_type": @"application/json",
        @"title": @"JSON"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:fmt=json;record", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isJSON]);
    XCTAssertTrue([resolved isRecord]);
}

// TEST104: Text-representability is now carried by the orthogonal `enc=` tag.
// The old isText/isBinary delegates on the resolved media def are gone; a media
// is text iff its URN declares an encoding. `media:enc=utf-8` is plain UTF-8
// text — has enc, is not JSON.
- (void)test104_resolved_is_text {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:enc=utf-8",
        @"media_type": @"text/plain",
        @"title": @"Text"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:enc=utf-8", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue(CSMediaUrnHasEncoding(resolved.mediaUrn), @"media:enc=utf-8 is text-representable");
    XCTAssertFalse([resolved isJSON]);
}

#pragma mark - Resolve with local overrides

// TEST091: Test resolving custom media URN from local media_defs takes precedence over registry
- (void)test091_resolve_custom_media_def {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:custom-spec;fmt=json",
        @"media_type": @"application/json",
        @"title": @"Custom Spec",
        @"profile_uri": @"https://example.com/schema"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:custom-spec;fmt=json", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertNil(error);
    XCTAssertEqualObjects(resolved.mediaUrn, @"media:custom-spec;fmt=json");
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertEqualObjects(resolved.profile, @"https://example.com/schema");
    XCTAssertNil(resolved.schema);
}

// TEST092: Test resolving custom record media def with schema from local media_defs
- (void)test092_resolve_custom_with_schema {
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string"}
        }
    };
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:fmt=json;output-spec;record",
        @"media_type": @"application/json",
        @"title": @"Output Spec",
        @"profile_uri": @"https://example.com/schema/output",
        @"schema": schema
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:fmt=json;output-spec;record", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertEqualObjects(resolved.mediaUrn, @"media:fmt=json;output-spec;record");
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertEqualObjects(resolved.profile, @"https://example.com/schema/output");
    XCTAssertNotNil(resolved.schema);
    XCTAssertEqualObjects(resolved.schema[@"type"], @"object");
}

// TEST094: Test local media_defs definition overrides registry definition for same URN
- (void)test094_local_overrides_registry {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:enc=utf-8",
        @"media_type": @"application/json",
        @"title": @"Custom String",
        @"profile_uri": @"https://custom.example.com/str"
    }];
    NSError *error = nil;
    CSMediaDef *resolved = CSResolveMediaUrn(@"media:enc=utf-8", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertEqualObjects(resolved.profile, @"https://custom.example.com/str");
}

@end
