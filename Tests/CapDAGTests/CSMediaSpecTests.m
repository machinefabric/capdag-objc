//
//  CSMediaSpecTests.m
//  Tests for CSMediaSpec metadata propagation
//

#import <XCTest/XCTest.h>
#import "CSMediaSpec.h"
#import "CSFabricRegistry.h"

@interface CSMediaSpecTests : XCTestCase
@end

static CSFabricRegistry *registryWithSpecs(NSArray<NSDictionary *> *specs) {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] init];
    for (NSDictionary *spec in specs) {
        [registry addMediaSpec:spec];
    }
    return registry;
}


@implementation CSMediaSpecTests

- (void)testMetadataPropagationFromObjectDef {
    // Create a media spec definition with metadata
    NSArray<NSDictionary *> *mediaSpecs = @[
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
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:custom-setting", registryWithSpecs(mediaSpecs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqualObjects(resolved.metadata[@"category_key"], @"interface", @"Should have category_key");
    XCTAssertEqualObjects(resolved.metadata[@"ui_type"], @"SETTING_UI_TYPE_CHECKBOX", @"Should have ui_type");
    XCTAssertEqualObjects(resolved.metadata[@"subcategory_key"], @"appearance", @"Should have subcategory_key");
    XCTAssertEqualObjects(resolved.metadata[@"display_index"], @5, @"Should have display_index");
}

- (void)testMetadataNilByDefault {
    // Media specs without metadata field should have nil metadata
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
            @"profile_uri": @"https://capdag.com/schema/string"
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(CSMediaString, registryWithSpecs(mediaSpecs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNil(resolved.metadata, @"Should have nil metadata when not provided");
}

- (void)testMetadataWithValidation {
    // Ensure metadata and validation can coexist
    NSArray<NSDictionary *> *mediaSpecs = @[
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
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:bounded-number;numeric", registryWithSpecs(mediaSpecs), &error);

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

- (void)testResolveMediaUrnNotFound {
    // Should fail hard for unknown media URNs
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:unknown;type", registryWithSpecs(@[]), &error);

    XCTAssertNotNil(error, @"Should have error for unknown media URN");
    XCTAssertNil(resolved, @"Should not resolve unknown media URN");
    XCTAssertEqual(error.code, CSMediaSpecErrorUnresolvableMediaUrn, @"Should be UNRESOLVABLE_MEDIA_URN error");
}

// Extensions field tests

- (void)testExtensionsPropagationFromObjectDef {
    // Create a media spec definition with extensions array
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:pdf",
            @"media_type": @"application/pdf",
            @"profile_uri": @"https://capdag.com/schema/pdf",
            @"title": @"PDF Document",
            @"description": @"A PDF document",
            @"extensions": @[@"pdf"]
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:pdf", registryWithSpecs(mediaSpecs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Should have extensions array");
    XCTAssertEqual(resolved.extensions.count, 1, @"Should have one extension");
    XCTAssertEqualObjects(resolved.extensions[0], @"pdf", @"Should have pdf extension");
}

- (void)testExtensionsEmptyWhenNotSet {
    // Media specs without extensions field should have empty array
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:text;textable",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com"
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:text;textable", registryWithSpecs(mediaSpecs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Extensions should not be nil");
    XCTAssertEqual(resolved.extensions.count, 0, @"Should have empty extensions array when not provided");
}

- (void)testExtensionsWithMetadataAndValidation {
    // Ensure extensions, metadata, and validation can coexist
    NSArray<NSDictionary *> *mediaSpecs = @[
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
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:custom-output", registryWithSpecs(mediaSpecs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");

    // Verify all fields are present
    XCTAssertNotNil(resolved.validation, @"Should have validation");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqual(resolved.extensions.count, 1, @"Should have one extension");
    XCTAssertEqualObjects(resolved.extensions[0], @"json", @"Should have json extension");
}

- (void)testMultipleExtensions {
    // Test multiple extensions in a media spec
    NSArray<NSDictionary *> *mediaSpecs = @[
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
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:image;jpeg", registryWithSpecs(mediaSpecs), &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Should have extensions array");
    XCTAssertEqual(resolved.extensions.count, 2, @"Should have two extensions");
    XCTAssertEqualObjects(resolved.extensions[0], @"jpg", @"Should have jpg extension first");
    XCTAssertEqualObjects(resolved.extensions[1], @"jpeg", @"Should have jpeg extension second");
}

// Duplicate URN validation tests

- (void)testValidateNoMediaSpecDuplicatesPass {
    // No duplicates should pass
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{@"urn": @"media:text;textable", @"media_type": @"text/plain"},
        @{@"urn": @"media:json;textable", @"media_type": @"application/json"}
    ];

    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(mediaSpecs, &error);

    XCTAssertTrue(result, @"Should pass validation with no duplicates");
    XCTAssertNil(error, @"Should have no error");
}

- (void)testValidateNoMediaSpecDuplicatesFail {
    // Duplicates should fail
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{@"urn": @"media:text;textable", @"media_type": @"text/plain"},
        @{@"urn": @"media:json;textable", @"media_type": @"application/json"},
        @{@"urn": @"media:text;textable", @"media_type": @"text/html"}  // Duplicate URN
    ];

    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(mediaSpecs, &error);

    XCTAssertFalse(result, @"Should fail validation with duplicates");
    XCTAssertNotNil(error, @"Should have error");
    XCTAssertEqual(error.code, CSMediaSpecErrorDuplicateMediaUrn, @"Should be DUPLICATE_MEDIA_URN error");
    XCTAssertTrue([error.localizedDescription containsString:@"media:text;textable"], @"Error should mention the duplicate URN");
}

- (void)testValidateNoMediaSpecDuplicatesEmpty {
    // Empty array should pass
    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(@[], &error);

    XCTAssertTrue(result, @"Should pass validation with empty array");
    XCTAssertNil(error, @"Should have no error");
}

- (void)testValidateNoMediaSpecDuplicatesNil {
    // Nil array should pass
    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(nil, &error);

    XCTAssertTrue(result, @"Should pass validation with nil array");
    XCTAssertNil(error, @"Should have no error");
}

#pragma mark - ResolvedMediaSpec predicate tests

// TEST099: Test ResolvedMediaSpec is_binary returns true when textable tag is absent
- (void)test099_resolved_is_binary {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:",
        @"media_type": @"application/octet-stream",
        @"title": @"Binary"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isBinary]);
    XCTAssertFalse([resolved isRecord]);
    XCTAssertFalse([resolved isJSON]);
}

// TEST100: Test ResolvedMediaSpec is_record returns true when record marker is present
- (void)test100_resolved_is_record {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:record;textable",
        @"media_type": @"application/json",
        @"title": @"Object"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:record;textable", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isRecord]);
    XCTAssertFalse([resolved isBinary]);
    XCTAssertTrue([resolved isScalar], @"record without list marker is scalar");
    XCTAssertFalse([resolved isList]);
}

// TEST101: Test ResolvedMediaSpec is_scalar returns true when list marker is absent
- (void)test101_resolved_is_scalar {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:textable",
        @"media_type": @"text/plain",
        @"title": @"String"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:textable", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isScalar]);
    XCTAssertFalse([resolved isRecord]);
    XCTAssertFalse([resolved isList]);
}

// TEST102: Test ResolvedMediaSpec is_list returns true when list marker is present
- (void)test102_resolved_is_list {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:list;textable",
        @"media_type": @"application/json",
        @"title": @"String Array"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:list;textable", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isList]);
    XCTAssertFalse([resolved isRecord]);
    XCTAssertFalse([resolved isScalar]);
}

// TEST103: Test ResolvedMediaSpec is_json returns true when json tag is present
- (void)test103_resolved_is_json {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:json;record;textable",
        @"media_type": @"application/json",
        @"title": @"JSON"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:json;record;textable", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isJSON]);
    XCTAssertTrue([resolved isRecord]);
    XCTAssertFalse([resolved isBinary]);
}

// TEST104: Test ResolvedMediaSpec is_text returns true when textable tag is present
- (void)test104_resolved_is_text {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:textable",
        @"media_type": @"text/plain",
        @"title": @"Text"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:textable", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertTrue([resolved isText]);
    XCTAssertFalse([resolved isBinary]);
    XCTAssertFalse([resolved isJSON]);
}

#pragma mark - Resolve with local overrides

// TEST091: Test resolving custom media URN from local media_specs takes precedence over registry
- (void)test091_resolve_custom_media_spec {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:custom-spec;json",
        @"media_type": @"application/json",
        @"title": @"Custom Spec",
        @"profile_uri": @"https://example.com/schema"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:custom-spec;json", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertNil(error);
    XCTAssertEqualObjects(resolved.mediaUrn, @"media:custom-spec;json");
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertEqualObjects(resolved.profile, @"https://example.com/schema");
    XCTAssertNil(resolved.schema);
}

// TEST092: Test resolving custom record media spec with schema from local media_specs
- (void)test092_resolve_custom_with_schema {
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string"}
        }
    };
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:json;output-spec;record",
        @"media_type": @"application/json",
        @"title": @"Output Spec",
        @"profile_uri": @"https://example.com/schema/output",
        @"schema": schema
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:json;output-spec;record", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertEqualObjects(resolved.mediaUrn, @"media:json;output-spec;record");
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertEqualObjects(resolved.profile, @"https://example.com/schema/output");
    XCTAssertNotNil(resolved.schema);
    XCTAssertEqualObjects(resolved.schema[@"type"], @"object");
}

// TEST094: Test local media_specs definition overrides registry definition for same URN
- (void)test094_local_overrides_registry {
    NSArray<NSDictionary *> *specs = @[@{
        @"urn": @"media:textable",
        @"media_type": @"application/json",
        @"title": @"Custom String",
        @"profile_uri": @"https://custom.example.com/str"
    }];
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:textable", registryWithSpecs(specs), &error);
    XCTAssertNotNil(resolved);
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertEqualObjects(resolved.profile, @"https://custom.example.com/str");
}

@end
