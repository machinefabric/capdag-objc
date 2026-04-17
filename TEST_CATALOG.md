# CapDag-ObjC/Swift Test Catalog

**Total Tests:** 1092

**Numbered Tests:** 618

**Unnumbered Tests:** 474

All numbered test numbers are unique.

This catalog lists all tests in the CapDag-ObjC/Swift codebase.

| Test # | Function Name | Description | File |
|--------|---------------|-------------|------|
| test001 | `test001_capUrnCreation` | TEST001: Test that cap URN is created with tags parsed correctly and direction specs accessible | Tests/CapDAGTests/CSCapUrnTests.m:31 |
| test002 | `test002_directionSpecsDefaultToWildcard` | TEST002: Test that missing 'in' or 'out' defaults to media: wildcard | Tests/CapDAGTests/CSCapUrnTests.m:146 |
| test003 | `test003_directionMatching` | TEST003: Test that direction specs must match exactly, different in/out types don't match, wildcard matches any | Tests/CapDAGTests/CSCapUrnTests.m:200 |
| test004 | `test004_unquotedValuesLowercased` | TEST004: Test that unquoted keys and values are normalized to lowercase | Tests/CapDAGTests/CSCapUrnTests.m:596 |
| test005 | `test005_quotedValuesPreserveCase` | TEST005: Test that quoted values preserve case while unquoted are lowercased | Tests/CapDAGTests/CSCapUrnTests.m:621 |
| test006 | `test006_quotedValueSpecialChars` | TEST006: Test that quoted values can contain special characters (semicolons, equals, spaces) | Tests/CapDAGTests/CSCapUrnTests.m:650 |
| test007 | `test007_quotedValueEscapeSequences` | TEST007: Test that escape sequences in quoted values (\" and \\) are parsed correctly | Tests/CapDAGTests/CSCapUrnTests.m:674 |
| test008 | `test008_mixedQuotedUnquoted` | TEST008: Test that mixed quoted and unquoted values in same URN parse correctly | Tests/CapDAGTests/CSCapUrnTests.m:691 |
| test009 | `test009_unterminatedQuoteError` | TEST009: Test that unterminated quote produces UnterminatedQuote error | Tests/CapDAGTests/CSCapUrnTests.m:701 |
| test010 | `test010_invalidEscapeSequenceError` | TEST010: Test that invalid escape sequences (like \n, \x) produce InvalidEscapeSequence error | Tests/CapDAGTests/CSCapUrnTests.m:710 |
| test011 | `test011_serializationSmartQuoting` | TEST011: Test that serialization uses smart quoting (no quotes for simple lowercase, quotes for special chars/uppercase) | Tests/CapDAGTests/CSCapUrnTests.m:50 |
| test012 | `test012_roundTripSimple` | TEST012: Test that simple cap URN round-trips (parse -> serialize -> parse equals original) | Tests/CapDAGTests/CSCapUrnTests.m:719 |
| test013 | `test013_roundTripQuoted` | TEST013: Test that quoted values round-trip preserving case and spaces | Tests/CapDAGTests/CSCapUrnTests.m:731 |
| test014 | `test014_roundTripEscapes` | TEST014: Test that escape sequences round-trip correctly | Tests/CapDAGTests/CSCapUrnTests.m:1262 |
| test015 | `test015_capPrefixRequired` | TEST015: Test that cap: prefix is required and case-insensitive | Tests/CapDAGTests/CSCapUrnTests.m:63 |
| test016 | `test016_trailingSemicolonEquivalence` | TEST016: Test that trailing semicolon is equivalent (same hash, same string, matches) | Tests/CapDAGTests/CSCapUrnTests.m:80 |
| test017 | `test017_tagMatching` | TEST017: Test tag matching: exact match, routing direction, wildcard match, value mismatch | Tests/CapDAGTests/CSCapUrnTests.m:238 |
| test018 | `test018_matchingCaseSensitiveValues` | TEST018: Test that quoted values with different case do NOT match (case-sensitive) | Tests/CapDAGTests/CSCapUrnTests.m:1274 |
| test019 | `test019_missingTagHandling` | TEST019: Missing tag in instance causes rejection — pattern's tags are constraints | Tests/CapDAGTests/CSCapUrnTests.m:265 |
| test020 | `test020_specificity` | TEST020: Test specificity calculation (in/out base, wildcards don't count) | Tests/CapDAGTests/CSCapUrnTests.m:284 |
| test021 | `test021_builder` | TEST021: Test builder creates cap URN with correct tags and direction specs | Tests/CapDAGTests/CSCapUrnTests.m:1289 |
| test022 | `test022_builderRequiresDirection` | TEST022: Test builder requires both in_spec and out_spec | Tests/CapDAGTests/CSCapUrnTests.m:1307 |
| test023 | `test023_builderPreservesCase` | TEST023: Test builder lowercases keys but preserves value case | Tests/CapDAGTests/CSCapUrnTests.m:1335 |
| test024 | `test024_directionalAccepts` | TEST024: Directional accepts — pattern's tags are constraints, instance must satisfy | Tests/CapDAGTests/CSCapUrnTests.m:303 |
| test025 | `test025_bestMatch` | TEST025: Test find_best_match returns most specific matching cap | Tests/CapDAGTests/CSCapUrnTests.m:1349 |
| test026 | `test026_mergeAndSubset` | TEST026: Test merge combines tags from both caps, subset keeps only specified tags | Tests/CapDAGTests/CSCapUrnTests.m:447 |
| test027 | `test027_wildcardTag` | TEST027: Test with_wildcard_tag sets tag to wildcard, including in/out | Tests/CapDAGTests/CSCapUrnTests.m:419 |
| test028 | `test028_emptyCapUrnDefaultsToWildcard` | TEST028: Test empty cap URN defaults to media: wildcard | Tests/CapDAGTests/CSCapUrnTests.m:168 |
| test029 | `test029_minimalCapUrn` | TEST029: Test minimal valid cap URN has just in and out, empty tags | Tests/CapDAGTests/CSCapUrnTests.m:188 |
| test030 | `test030_extendedCharacterSupport` | TEST030: Test extended characters (forward slashes, colons) in tag values | Tests/CapDAGTests/CSCapUrnTests.m:523 |
| test031 | `test031_wildcardRestrictions` | TEST031: Test wildcard rejected in keys but accepted in values | Tests/CapDAGTests/CSCapUrnTests.m:534 |
| test032 | `test032_duplicateKeyRejection` | TEST032: Test duplicate keys are rejected with DuplicateKey error | Tests/CapDAGTests/CSCapUrnTests.m:553 |
| test033 | `test033_numericKeyRestriction` | TEST033: Test pure numeric keys rejected, mixed alphanumeric allowed, numeric values allowed | Tests/CapDAGTests/CSCapUrnTests.m:563 |
| test034 | `test034_emptyValueError` | TEST034: Test empty values are rejected | Tests/CapDAGTests/CSCapUrnTests.m:1368 |
| test035 | `test035_hasTagCaseSensitive` | TEST035: Test has_tag is case-sensitive for values, case-insensitive for keys, works for in/out | Tests/CapDAGTests/CSCapUrnTests.m:744 |
| test036 | `test036_withTagPreservesValue` | TEST036: Test with_tag preserves value case | Tests/CapDAGTests/CSCapUrnTests.m:348 |
| test037 | `test037_withTagRejectsEmptyValue` | TEST037: Test with_tag rejects empty value | Tests/CapDAGTests/CSCapUrnTests.m:1379 |
| test038 | `test038_semanticEquivalence` | TEST038: Test semantic equivalence of unquoted and quoted simple lowercase values | Tests/CapDAGTests/CSCapUrnTests.m:767 |
| test039 | `test039_getTagReturnsDirectionSpecs` | TEST039: Test get_tag returns direction specs (in/out) with case-insensitive lookup | Tests/CapDAGTests/CSCapUrnTests.m:334 |
| test040 | `test040_matchingSemantics_exactMatch` | TEST040: Matching semantics - exact match succeeds | Tests/CapDAGTests/CSCapUrnTests.m:789 |
| test041 | `test041_matchingSemantics_capMissingTag` | TEST041: Matching semantics - cap missing tag matches (implicit wildcard) | Tests/CapDAGTests/CSCapUrnTests.m:802 |
| test042 | `test042_matchingSemantics_capHasExtraTag` | TEST042: Pattern rejects instance missing required tags | Tests/CapDAGTests/CSCapUrnTests.m:815 |
| test043 | `test043_matchingSemantics_requestHasWildcard` | TEST043: Matching semantics - request wildcard matches specific cap value | Tests/CapDAGTests/CSCapUrnTests.m:826 |
| test044 | `test044_matchingSemantics_capHasWildcard` | TEST044: Matching semantics - cap wildcard matches specific request value | Tests/CapDAGTests/CSCapUrnTests.m:839 |
| test045 | `test045_matchingSemantics_valueMismatch` | TEST045: Matching semantics - value mismatch does not match | Tests/CapDAGTests/CSCapUrnTests.m:852 |
| test046 | `test046_matchingSemantics_fallbackPattern` | TEST046: Matching semantics - fallback pattern (cap missing tag = implicit wildcard) | Tests/CapDAGTests/CSCapUrnTests.m:865 |
| test047 | `test047_matchingSemantics_thumbnailVoidInput` | TEST047: Matching semantics - thumbnail fallback with void input | Tests/CapDAGTests/CSCapUrnTests.m:1389 |
| test048 | `test048_matchingSemantics_wildcardDirectionMatchesAnything` | TEST048: Matching semantics - wildcard direction matches anything | Tests/CapDAGTests/CSCapUrnTests.m:878 |
| test049 | `test049_matchingSemantics_crossDimensionIndependence` | TEST049: Non-overlapping tags — neither direction accepts | Tests/CapDAGTests/CSCapUrnTests.m:892 |
| test050 | `test050_matchingSemantics_directionMismatch` | TEST050: Matching semantics - direction mismatch prevents matching | Tests/CapDAGTests/CSCapUrnTests.m:902 |
| test051 | `test051_inputValidationSuccess` | TEST051: Test input validation succeeds with valid positional argument | Tests/CapDAGTests/CSSchemaValidationTests.m:46 |
| test052 | `test052_inputValidationMissingRequired` | TEST052: Test input validation fails with MissingRequiredArgument when required arg missing | Tests/CapDAGTests/CSSchemaValidationTests.m:87 |
| test053 | `test053_inputValidationWrongType` | TEST053: Test input validation fails with InvalidArgumentType when wrong type provided | Tests/CapDAGTests/CSSchemaValidationTests.m:131 |
| test054 | `test054_xv5InlineSpecRedefinitionDetected` | TEST054: XV5 - Test inline media spec redefinition of existing registry spec is detected and rejected | Tests/CapDAGTests/CSSchemaValidationTests.m:774 |
| test055 | `test055_xv5NewInlineSpecAllowed` | TEST055: XV5 - Test new inline media spec (not in registry) is allowed | Tests/CapDAGTests/CSSchemaValidationTests.m:801 |
| test056 | `test056_xv5EmptyMediaSpecsAllowed` | TEST056: XV5 - Test empty media_specs (no inline specs) passes XV5 validation | Tests/CapDAGTests/CSSchemaValidationTests.m:825 |
| test060 | `test060_wrong_prefix_fails` | TEST060: Wrong prefix fails | Tests/CapDAGTests/CSMediaUrnTests.m:119 |
| test061 | `test061_is_binary` | TEST061: is_binary | Tests/CapDAGTests/CSMediaUrnTests.m:130 |
| test062 | `test062_is_record` | TEST062: is_record | Tests/CapDAGTests/CSMediaUrnTests.m:146 |
| test063 | `test063_is_scalar` | TEST063: is_scalar | Tests/CapDAGTests/CSMediaUrnTests.m:158 |
| test064 | `test064_is_list` | TEST064: is_list | Tests/CapDAGTests/CSMediaUrnTests.m:172 |
| test065 | `test065_is_opaque` | TEST065: is_opaque | Tests/CapDAGTests/CSMediaUrnTests.m:184 |
| test066 | `test066_is_json` | TEST066: is_json | Tests/CapDAGTests/CSMediaUrnTests.m:197 |
| test067 | `test067_is_text` | TEST067: is_text | Tests/CapDAGTests/CSMediaUrnTests.m:207 |
| test068 | `test068_is_void` | TEST068: is_void | Tests/CapDAGTests/CSMediaUrnTests.m:218 |
| test071 | `test071_to_string_roundtrip` | TEST071: to_string roundtrip | Tests/CapDAGTests/CSMediaUrnTests.m:362 |
| test072 | `test072_constants_parse` | TEST072: constants parse | Tests/CapDAGTests/CSMediaUrnTests.m:373 |
| test074 | `test074_media_urn_matching` | TEST074: media URN conforms_to matching | Tests/CapDAGTests/CSMediaUrnTests.m:405 |
| test075 | `test075_matching` | TEST075: accepts matching | Tests/CapDAGTests/CSMediaUrnTests.m:421 |
| test076 | `test076_specificity` | TEST076: specificity | Tests/CapDAGTests/CSMediaUrnTests.m:432 |
| test078 | `test078_object_does_not_conform_to_string` | TEST078: object does not conform to string | Tests/CapDAGTests/CSMediaUrnTests.m:447 |
| test091 | `test091_resolve_custom_media_spec` | TEST091: Resolve custom media URN from local media_specs | Tests/CapDAGTests/CSMediaSpecTests.m:355 |
| test092 | `test092_resolve_custom_with_schema` | TEST092: Resolve custom record media spec with schema | Tests/CapDAGTests/CSMediaSpecTests.m:373 |
| test094 | `test094_local_overrides_registry` | TEST094: Local media_specs overrides registry definition | Tests/CapDAGTests/CSMediaSpecTests.m:398 |
| test099 | `test099_resolved_is_binary` | TEST099: ResolvedMediaSpec is_binary (textable absent) | Tests/CapDAGTests/CSMediaSpecTests.m:262 |
| test100 | `test100_resolved_is_record` | TEST100: ResolvedMediaSpec is_record (record marker present) | Tests/CapDAGTests/CSMediaSpecTests.m:277 |
| test101 | `test101_resolved_is_scalar` | TEST101: ResolvedMediaSpec is_scalar (list marker absent) | Tests/CapDAGTests/CSMediaSpecTests.m:293 |
| test102 | `test102_resolved_is_list` | TEST102: ResolvedMediaSpec is_list (list marker present) | Tests/CapDAGTests/CSMediaSpecTests.m:308 |
| test103 | `test103_resolved_is_json` | TEST103: ResolvedMediaSpec is_json (json tag present) | Tests/CapDAGTests/CSMediaSpecTests.m:323 |
| test104 | `test104_resolved_is_text` | TEST104: ResolvedMediaSpec is_text (textable present) | Tests/CapDAGTests/CSMediaSpecTests.m:338 |
| test124 | `test124_cap_block_no_match` | TEST124: CapBlock no match returns error | Tests/CapDAGTests/CSCapMatrixTests.m:428 |
| test127 | `test127_cap_graph_basic_construction` | TEST127: CapGraph basic construction | Tests/CapDAGTests/CSCapMatrixTests.m:277 |
| test128 | `test128_cap_graph_outgoing_incoming` | TEST128: CapGraph outgoing/incoming edges | Tests/CapDAGTests/CSCapMatrixTests.m:287 |
| test129 | `test129_cap_graph_can_convert` | TEST129: CapGraph can_convert (direct, indirect, no-path) | Tests/CapDAGTests/CSCapMatrixTests.m:305 |
| test130 | `test130_cap_graph_find_path` | TEST130: CapGraph find_path (shortest path) | Tests/CapDAGTests/CSCapMatrixTests.m:320 |
| test131 | `test131_cap_graph_find_all_paths` | TEST131: CapGraph find_all_paths sorted by length | Tests/CapDAGTests/CSCapMatrixTests.m:347 |
| test132 | `test132_cap_graph_get_direct_edges_sorted` | TEST132: CapGraph get_direct_edges sorted by specificity | Tests/CapDAGTests/CSCapMatrixTests.m:363 |
| test134 | `test134_cap_graph_stats` | TEST134: CapGraph stats | Tests/CapDAGTests/CSCapMatrixTests.m:377 |
| test148 | `test148_capManifestCreation` | TEST148: Test creating cap manifest with name, version, description, and caps | Tests/BifaciTests/ManifestTests.swift:17 |
| test149 | `test149_capManifestWithAuthor` | TEST149: Test cap manifest with author field (via CSCapManifest which has author) | Tests/BifaciTests/ManifestTests.swift:34 |
| test150 | `test150_capManifestJsonRoundtrip` | TEST150: Test cap manifest JSON serialization and deserialization roundtrip | Tests/BifaciTests/ManifestTests.swift:46 |
| test151 | `test151_capManifestRequiredFields` | TEST151: Test cap manifest deserialization fails when required fields are missing | Tests/BifaciTests/ManifestTests.swift:72 |
| test152 | `test152_capManifestWithMultipleCaps` | TEST152: Test cap manifest with multiple caps stores and retrieves all capabilities | Tests/BifaciTests/ManifestTests.swift:104 |
| test153 | `test153_capManifestEmptyCaps` | TEST153: Test cap manifest with empty caps list serializes and deserializes correctly | Tests/BifaciTests/ManifestTests.swift:132 |
| test154 | `test154_capManifestOptionalAuthorField` | TEST154: Test cap manifest optional author field (using CSCapManifest) | Tests/BifaciTests/ManifestTests.swift:152 |
| test155 | `test155_componentMetadataAccessors` | TEST155: Test ComponentMetadata provides manifest and caps accessor methods | Tests/BifaciTests/ManifestTests.swift:168 |
| test171 | `test171_frameTypeRoundtrip` | TEST171: All FrameType discriminants roundtrip through raw value conversion preserving identity | Tests/BifaciTests/FrameTests.swift:22 |
| test172 | `test172_invalidFrameType` | TEST172: FrameType init returns nil for values outside the valid discriminant range (updated for new max) | Tests/BifaciTests/FrameTests.swift:32 |
| test173 | `test173_frameTypeDiscriminantValues` | TEST173: FrameType discriminant values match the wire protocol specification exactly | Tests/BifaciTests/FrameTests.swift:42 |
| test174 | `test174_messageIdUUID` | TEST174: MessageId.newUUID generates valid UUID that roundtrips through string conversion | Tests/BifaciTests/FrameTests.swift:60 |
| test175 | `test175_messageIdUUIDUniqueness` | TEST175: Two MessageId.newUUID calls produce distinct IDs (no collisions) | Tests/BifaciTests/FrameTests.swift:67 |
| test176 | `test176_messageIdUintHasNoUUIDString` | TEST176: MessageId.uint does not produce a UUID string | Tests/BifaciTests/FrameTests.swift:74 |
| test177 | `test177_messageIdFromInvalidUUIDStr` | TEST177: MessageId init from invalid UUID string returns nil | Tests/BifaciTests/FrameTests.swift:81 |
| test178 | `test178_messageIdAsBytes` | TEST178: MessageId.asBytes produces correct byte representations for Uuid and Uint variants | Tests/BifaciTests/FrameTests.swift:1256 |
| test179 | `test179_messageIdNewUUIDIsUUID` | TEST179: MessageId.newUUID creates a UUID variant (not Uint) | Tests/BifaciTests/FrameTests.swift:1275 |
| test180 | `test180_helloFrame` | TEST180: Frame.hello without manifest produces correct HELLO frame for host side | Tests/BifaciTests/FrameTests.swift:115 |
| test181 | `test181_helloFrameWithManifest` | TEST181: Frame.helloWithManifest produces HELLO with manifest bytes for cartridge side | Tests/BifaciTests/FrameTests.swift:126 |
| test182 | `test182_reqFrame` | TEST182: Frame.req stores cap URN, payload, and content_type correctly | Tests/BifaciTests/FrameTests.swift:142 |
| test184 | `test184_chunkFrame` | TEST184: Frame.chunk stores seq, streamId, payload, chunkIndex, and checksum for multiplexed streaming | Tests/BifaciTests/FrameTests.swift:160 |
| test185 | `test185_errFrame` | TEST185: Frame.err stores error code and message in metadata | Tests/BifaciTests/FrameTests.swift:174 |
| test186 | `test186_logFrame` | TEST186: Frame.log stores level and message in metadata | Tests/BifaciTests/FrameTests.swift:183 |
| test187 | `test187_endFrameWithPayload` | TEST187: Frame.end with payload sets eof and optional final payload | Tests/BifaciTests/FrameTests.swift:192 |
| test188 | `test188_endFrameWithoutPayload` | TEST188: Frame.end without payload still sets eof marker | Tests/BifaciTests/FrameTests.swift:201 |
| test189 | `test189_chunkWithOffset` | TEST189: chunk_with_offset sets offset on all chunks but len only on seq=0 (with streamId) | Tests/BifaciTests/FrameTests.swift:210 |
| test190 | `test190_heartbeatFrame` | TEST190: Frame.heartbeat creates minimal frame with no payload or metadata | Tests/BifaciTests/FrameTests.swift:255 |
| test191 | `test191_errorAccessorsOnNonErrFrame` | TEST191: error_code and error_message return nil for non-Err frame types | Tests/BifaciTests/FrameTests.swift:265 |
| test192 | `test192_logAccessorsOnNonLogFrame` | TEST192: log_level and log_message return nil for non-Log frame types | Tests/BifaciTests/FrameTests.swift:272 |
| test193 | `test193_helloAccessorsOnNonHelloFrame` | TEST193: hello_max_frame and hello_max_chunk return nil for non-Hello frame types | Tests/BifaciTests/FrameTests.swift:279 |
| test194 | `test194_frameNewDefaults` | TEST194: Frame init sets version and defaults correctly, optional fields are None | Tests/BifaciTests/FrameTests.swift:1286 |
| test195 | `test195_frameDefaultType` | TEST195: Frame default initializer creates frame with specified type (Swift equivalent of Rust Default) | Tests/BifaciTests/FrameTests.swift:1311 |
| test196 | `test196_isEofWhenNil` | TEST196: is_eof returns false when eof field is nil (unset) | Tests/BifaciTests/FrameTests.swift:287 |
| test197 | `test197_isEofWhenFalse` | TEST197: is_eof returns false when eof field is explicitly false | Tests/BifaciTests/FrameTests.swift:294 |
| test198 | `test198_limitsDefault` | TEST198: Limits default provides the documented default values | Tests/BifaciTests/FrameTests.swift:301 |
| test199 | `test199_protocolVersionConstant` | TEST199: PROTOCOL_VERSION is 2 | Tests/BifaciTests/FrameTests.swift:318 |
| test200 | `test200_keyConstants` | TEST200: Integer key constants match the protocol specification | Tests/BifaciTests/FrameTests.swift:323 |
| test201 | `test201_helloManifestBinaryData` | TEST201: hello_with_manifest preserves binary manifest data (not just JSON text) | Tests/BifaciTests/FrameTests.swift:340 |
| test202 | `test202_messageIdEqualityAndHash` | TEST202: MessageId Eq/Hash semantics: equal UUIDs are equal, different ones are not | Tests/BifaciTests/FrameTests.swift:88 |
| test203 | `test203_messageIdCrossVariantInequality` | TEST203: Uuid and Uint variants of MessageId are never equal | Tests/BifaciTests/FrameTests.swift:106 |
| test204 | `test204_reqFrameEmptyPayload` | TEST204: Frame.req with empty payload stores Data() not nil | Tests/BifaciTests/FrameTests.swift:352 |
| test205 | `test205_encodeDecodeRoundtrip` | TEST205: REQ frame encode/decode roundtrip preserves all fields | Tests/BifaciTests/FrameTests.swift:361 |
| test206 | `test206_helloFrameRoundtrip` | TEST206: HELLO frame encode/decode roundtrip preserves max_frame, max_chunk, and max_reorder_buffer | Tests/BifaciTests/FrameTests.swift:382 |
| test207 | `test207_errFrameRoundtrip` | TEST207: ERR frame encode/decode roundtrip preserves error code and message | Tests/BifaciTests/FrameTests.swift:395 |
| test208 | `test208_logFrameRoundtrip` | TEST208: LOG frame encode/decode roundtrip preserves level and message | Tests/BifaciTests/FrameTests.swift:407 |
| test210 | `test210_endFrameRoundtrip` | TEST210: END frame encode/decode roundtrip preserves eof marker and optional payload | Tests/BifaciTests/FrameTests.swift:421 |
| test211 | `test211_helloWithManifestRoundtrip` | TEST211: HELLO with manifest encode/decode roundtrip preserves manifest bytes | Tests/BifaciTests/FrameTests.swift:434 |
| test212 | `test212_chunkWithOffsetRoundtrip` | TEST212: chunk_with_offset encode/decode roundtrip preserves offset, len, eof, streamId | Tests/BifaciTests/FrameTests.swift:453 |
| test213 | `test213_heartbeatRoundtrip` | TEST213: Heartbeat frame encode/decode roundtrip preserves ID with no extra fields | Tests/BifaciTests/FrameTests.swift:510 |
| test214 | `test214_frameIORoundtrip` |  | Tests/BifaciTests/FrameTests.swift:525 |
| test215 | `test215_multipleFrames` |  | Tests/BifaciTests/FrameTests.swift:547 |
| test216 | `test216_frameTooLarge` |  | Tests/BifaciTests/FrameTests.swift:589 |
| test217 | `test217_readFrameTooLarge` |  | Tests/BifaciTests/FrameTests.swift:608 |
| test218 | `test218_writeChunked` |  | Tests/BifaciTests/FrameTests.swift:634 |
| test219 | `test219_writeChunkedEmptyData` |  | Tests/BifaciTests/FrameTests.swift:685 |
| test220 | `test220_writeChunkedExactFit` |  | Tests/BifaciTests/FrameTests.swift:705 |
| test221 | `test221_eofHandling` | TEST221: read_frame returns nil on clean EOF (empty stream) | Tests/BifaciTests/FrameTests.swift:729 |
| test222 | `test222_truncatedLengthPrefix` |  | Tests/BifaciTests/FrameTests.swift:739 |
| test223 | `test223_truncatedFrameBody` |  | Tests/BifaciTests/FrameTests.swift:759 |
| test224 | `test224_messageIdUintRoundtrip` | TEST224: MessageId.uint roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:784 |
| test225 | `test225_decodeNonMapValue` | TEST225: decode_frame rejects non-map CBOR values (e.g., array, integer, string) | Tests/BifaciTests/FrameTests.swift:793 |
| test226 | `test226_decodeMissingVersion` | TEST226: decode_frame rejects CBOR map missing required version field | Tests/BifaciTests/FrameTests.swift:808 |
| test227 | `test227_decodeInvalidFrameTypeValue` | TEST227: decode_frame rejects CBOR map with invalid frame_type value | Tests/BifaciTests/FrameTests.swift:826 |
| test228 | `test228_decodeMissingId` | TEST228: decode_frame rejects CBOR map missing required id field | Tests/BifaciTests/FrameTests.swift:844 |
| test229 | `test229_frameReaderWriterSetLimits` |  | Tests/BifaciTests/FrameTests.swift:863 |
| test230 | `test230_syncHandshake` | TEST230: sync_handshake exchanges HELLO frames and negotiates minimum limits | Tests/BifaciTests/IntegrationTests.swift:449 |
| test231 | `test231_attachCartridgeFailsOnWrongFrameType` | TEST231: attachCartridge fails when peer sends non-HELLO frame | Tests/BifaciTests/RuntimeTests.swift:233 |
| test232 | `test232_attachCartridgeFailsOnMissingManifest` | TEST232: attachCartridge fails when cartridge HELLO is missing required manifest | Tests/BifaciTests/RuntimeTests.swift:199 |
| test233 | `test233_binaryPayloadAllByteValues` | TEST233: Binary payload with all 256 byte values roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:879 |
| test234 | `test234_decodeGarbageBytes` | TEST234: decode_frame handles garbage CBOR bytes gracefully with an error | Tests/BifaciTests/FrameTests.swift:895 |
| test235 | `test235_responseChunk` | TEST235: ResponseChunk stores payload, seq, offset, len, and eof fields correctly | Tests/BifaciTests/FrameTests.swift:934 |
| test236 | `test236_responseChunkWithAllFields` | TEST236: ResponseChunk with all fields populated preserves offset, len, and eof | Tests/BifaciTests/FrameTests.swift:947 |
| test237 | `test237_cartridgeResponseSingle` | TEST237: CartridgeResponse.single final_payload returns the single payload | Tests/BifaciTests/FrameTests.swift:959 |
| test238 | `test238_cartridgeResponseSingleEmpty` | TEST238: CartridgeResponse.single with empty payload returns empty data | Tests/BifaciTests/FrameTests.swift:966 |
| test239 | `test239_cartridgeResponseStreaming` | TEST239: CartridgeResponse.streaming concatenated joins all chunk payloads in order | Tests/BifaciTests/FrameTests.swift:973 |
| test240 | `test240_cartridgeResponseStreamingFinalPayload` | TEST240: CartridgeResponse.streaming finalPayload returns the last chunk's payload | Tests/BifaciTests/FrameTests.swift:984 |
| test241 | `test241_cartridgeResponseStreamingEmptyChunks` | TEST241: CartridgeResponse.streaming with empty chunks vec returns empty concatenation | Tests/BifaciTests/FrameTests.swift:994 |
| test242 | `test242_cartridgeResponseStreamingLargePayload` | TEST242: CartridgeResponse.streaming concatenated with large payload | Tests/BifaciTests/FrameTests.swift:1001 |
| test243 | `test243_cartridgeHostErrorDisplay` |  | Tests/BifaciTests/FrameTests.swift:1016 |
| test244 | `test244_cartridgeHostErrorFromFrameError` | TEST244: CartridgeHostError from FrameError converts correctly | Tests/BifaciTests/RuntimeTests.swift:1225 |
| test245 | `test245_cartridgeHostErrorDetails` | TEST245: CartridgeHostError stores and retrieves error details | Tests/BifaciTests/RuntimeTests.swift:1241 |
| test246 | `test246_cartridgeHostErrorVariants` | TEST246: CartridgeHostError variants are distinct | Tests/BifaciTests/RuntimeTests.swift:1249 |
| test247 | `test247_responseChunkStorage` | TEST247: ResponseChunk stores and retrieves data correctly | Tests/BifaciTests/RuntimeTests.swift:1276 |
| test248 | `test248_registerAndFindHandler` | TEST248: Test register_op and find_handler by exact cap URN | Tests/BifaciTests/CartridgeRuntimeTests.swift:117 |
| test249 | `test249_rawHandler` | TEST249: Test register_op handler echoes bytes directly | Tests/BifaciTests/CartridgeRuntimeTests.swift:129 |
| test250 | `test250_typedHandlerRegistration` | TEST250: Op handler can be registered and invoked | Tests/BifaciTests/CartridgeRuntimeTests.swift:434 |
| test251 | `test251_typedHandlerErrorPropagation` | TEST251: Op handler errors propagate through RuntimeError::Handler | Tests/BifaciTests/CartridgeRuntimeTests.swift:452 |
| test252 | `test252_findHandlerUnknownCap` | TEST252: find_handler returns None for unregistered cap URNs | Tests/BifaciTests/CartridgeRuntimeTests.swift:152 |
| test253 | `test253_handlerIsSendable` | TEST253: Op handler can be used across threads (Send + Sync equivalent) | Tests/BifaciTests/CartridgeRuntimeTests.swift:464 |
| test254 | `test254_noPeerInvoker` | TEST254: NoPeerInvoker always returns error regardless of arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:208 |
| test255 | `test255_noPeerInvokerWithArguments` | TEST255: NoPeerInvoker returns error even with valid arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:223 |
| test256 | `test256_withManifestJson` | TEST256: CartridgeRuntime with manifest JSON stores manifest data and parses when valid | Tests/BifaciTests/CartridgeRuntimeTests.swift:233 |
| test257 | `test257_newWithInvalidJson` | TEST257: CartridgeRuntime with invalid JSON still creates runtime | Tests/BifaciTests/CartridgeRuntimeTests.swift:240 |
| test258 | `test258_withManifestStruct` | TEST258: CartridgeRuntime with valid manifest data creates runtime with parsed manifest | Tests/BifaciTests/CartridgeRuntimeTests.swift:247 |
| test259 | `test259_extractEffectivePayloadNonCbor` | TEST259: extract_effective_payload with non-CBOR content_type returns raw payload unchanged | Tests/BifaciTests/CartridgeRuntimeTests.swift:257 |
| test260 | `test260_extractEffectivePayloadNoContentType` | TEST260: extract_effective_payload with None content_type returns raw payload unchanged | Tests/BifaciTests/CartridgeRuntimeTests.swift:264 |
| test261 | `test261_extractEffectivePayloadCborMatch` | TEST261: extract_effective_payload with CBOR content extracts matching argument value | Tests/BifaciTests/CartridgeRuntimeTests.swift:271 |
| test262 | `test262_extractEffectivePayloadCborNoMatch` | TEST262: extract_effective_payload with CBOR content fails when no argument matches | Tests/BifaciTests/CartridgeRuntimeTests.swift:290 |
| test263 | `test263_extractEffectivePayloadInvalidCbor` | TEST263: extract_effective_payload with invalid CBOR bytes returns deserialization error | Tests/BifaciTests/CartridgeRuntimeTests.swift:312 |
| test264 | `test264_extractEffectivePayloadCborNotArray` | TEST264: extract_effective_payload with CBOR non-array returns error | Tests/BifaciTests/CartridgeRuntimeTests.swift:321 |
| test265 | `test265_extractEffectivePayloadInvalidCapUrn` | TEST265: extract_effective_payload with invalid cap URN returns CapUrn error | Tests/BifaciTests/CartridgeRuntimeTests.swift:338 |
| test266 | `test266_cliFrameSenderConstruction` | TEST266: CliFrameSender construction with ndjson mode (matching Rust) | Tests/BifaciTests/CartridgeRuntimeTests.swift:480 |
| test268 | `test268_runtimeErrorDisplay` | TEST268: RuntimeError variants display correct messages | Tests/BifaciTests/CartridgeRuntimeTests.swift:411 |
| test270 | `test270_multipleHandlers` | TEST270: Test registering multiple Op handlers for different caps and finding each independently | Tests/BifaciTests/CartridgeRuntimeTests.swift:159 |
| test271 | `test271_handlerReplacement` | TEST271: Test Op handler replacing an existing registration for the same cap URN | Tests/BifaciTests/CartridgeRuntimeTests.swift:190 |
| test272 | `test272_extractEffectivePayloadMultipleArgs` | TEST272: extract_effective_payload CBOR with multiple arguments selects the correct one | Tests/BifaciTests/CartridgeRuntimeTests.swift:362 |
| test273 | `test273_extractEffectivePayloadBinaryValue` | TEST273: extract_effective_payload with binary data in CBOR value | Tests/BifaciTests/CartridgeRuntimeTests.swift:384 |
| test274 | `test274_capArgumentValueNew` | TEST274: CapArgumentValue stores media_urn and raw byte value | Tests/BifaciTests/CartridgeRuntimeTests.swift:506 |
| test275 | `test275_capArgumentValueFromStr` | TEST275: CapArgumentValue.fromString converts string to UTF-8 bytes | Tests/BifaciTests/CartridgeRuntimeTests.swift:516 |
| test276 | `test276_capArgumentValueAsStrValid` | TEST276: CapArgumentValue.valueAsString succeeds for UTF-8 data | Tests/BifaciTests/CartridgeRuntimeTests.swift:523 |
| test277 | `test277_capArgumentValueAsStrInvalidUtf8` | TEST277: CapArgumentValue.valueAsString fails for non-UTF-8 binary data | Tests/BifaciTests/CartridgeRuntimeTests.swift:529 |
| test278 | `test278_capArgumentValueEmpty` | TEST278: CapArgumentValue with empty value stores empty Data | Tests/BifaciTests/CartridgeRuntimeTests.swift:535 |
| test282 | `test282_capArgumentValueUnicode` | TEST282: CapArgumentValue.fromString with Unicode string preserves all characters | Tests/BifaciTests/CartridgeRuntimeTests.swift:542 |
| test283 | `test283_capArgumentValueLargeBinary` | TEST283: CapArgumentValue with large binary payload preserves all bytes | Tests/BifaciTests/CartridgeRuntimeTests.swift:548 |
| test284 | `test284_handshakeHostCartridge` | TEST284: Handshake exchanges HELLO frames, negotiates limits | Tests/BifaciTests/IntegrationTests.swift:49 |
| test285 | `test285_requestResponseSimple` | TEST285: Simple request-response flow (REQ → END with payload) | Tests/BifaciTests/IntegrationTests.swift:89 |
| test286 | `test286_streamingChunks` | TEST286: Streaming response with multiple CHUNK frames | Tests/BifaciTests/IntegrationTests.swift:139 |
| test287 | `test287_heartbeatFromHost` | TEST287: Host-initiated heartbeat handling | Tests/BifaciTests/IntegrationTests.swift:205 |
| test290 | `test290_limitsNegotiation` | TEST290: Limit negotiation picks minimum values | Tests/BifaciTests/IntegrationTests.swift:251 |
| test291 | `test291_binaryPayloadRoundtrip` | TEST291: Binary payload roundtrip (all 256 byte values) | Tests/BifaciTests/IntegrationTests.swift:286 |
| test292 | `test292_messageIdUniqueness` | TEST292: Sequential requests get distinct MessageIds | Tests/BifaciTests/IntegrationTests.swift:345 |
| test293 | `test293_cartridgeRuntimeHandlerRegistration` | TEST293: Test CartridgeRuntime Op registration and lookup by exact and non-existent cap URN | Tests/BifaciTests/RuntimeTests.swift:633 |
| test299 | `test299_emptyPayloadRoundtrip` | TEST299: Empty payload request/response roundtrip | Tests/BifaciTests/IntegrationTests.swift:398 |
| test304 | `test304_media_availability_output_constant` | TEST304: MEDIA_AVAILABILITY_OUTPUT constant | Tests/CapDAGTests/CSMediaUrnTests.m:459 |
| test305 | `test305_media_path_output_constant` | TEST305: MEDIA_PATH_OUTPUT constant | Tests/CapDAGTests/CSMediaUrnTests.m:471 |
| test306 | `test306_availability_and_path_output_distinct` | TEST306: availability and path output are distinct | Tests/CapDAGTests/CSMediaUrnTests.m:483 |
| test316 | `test316_concatenatedVsFinalPayloadDivergence` | TEST316: concatenated() returns full payload while finalPayload returns only last chunk | Tests/BifaciTests/RuntimeTests.swift:1048 |
| test336 | `test336_file_path_reads_file_passes_bytes` | TEST336: Single file-path arg with stdin source reads file and passes bytes to handler | Tests/BifaciTests/CartridgeRuntimeTests.swift:622 |
| test337 | `test337_file_path_without_stdin_passes_string` | TEST337: file-path arg without stdin source passes path as string (no conversion) | Tests/BifaciTests/CartridgeRuntimeTests.swift:676 |
| test338 | `test338_file_path_via_cli_flag` | TEST338: file-path arg reads file via --file CLI flag | Tests/BifaciTests/CartridgeRuntimeTests.swift:711 |
| test339 | `test339_file_path_array_glob_expansion` | TEST339: file-path-array reads multiple files with glob pattern | Tests/BifaciTests/CartridgeRuntimeTests.swift:751 |
| test340 | `test340_file_not_found_clear_error` | TEST340: File not found error provides clear message | Tests/BifaciTests/CartridgeRuntimeTests.swift:816 |
| test341 | `test341_stdin_precedence_over_file_path` | TEST341: stdin takes precedence over file-path in source order | Tests/BifaciTests/CartridgeRuntimeTests.swift:844 |
| test342 | `test342_file_path_position_zero_reads_first_arg` | TEST342: file-path with position 0 reads first positional arg as file | Tests/BifaciTests/CartridgeRuntimeTests.swift:884 |
| test343 | `test343_non_file_path_args_unaffected` | TEST343: Non-file-path args are not affected by file reading | Tests/BifaciTests/CartridgeRuntimeTests.swift:917 |
| test344 | `test344_file_path_array_invalid_json_fails` | TEST344: file-path-array with invalid JSON fails clearly | Tests/BifaciTests/CartridgeRuntimeTests.swift:948 |
| test345 | `test345_file_path_array_one_file_missing_fails_hard` | TEST345: file-path-array with one file failing stops and reports error | Tests/BifaciTests/CartridgeRuntimeTests.swift:977 |
| test346 | `test346_large_file_reads_successfully` | TEST346: Large file (1MB) reads successfully | Tests/BifaciTests/CartridgeRuntimeTests.swift:1016 |
| test347 | `test347_empty_file_reads_as_empty_bytes` | TEST347: Empty file reads as empty bytes | Tests/BifaciTests/CartridgeRuntimeTests.swift:1055 |
| test348 | `test348_file_path_conversion_respects_source_order` | TEST348: file-path conversion respects source order | Tests/BifaciTests/CartridgeRuntimeTests.swift:1087 |
| test349 | `test349_file_path_multiple_sources_fallback` | TEST349: file-path arg with multiple sources tries all in order | Tests/BifaciTests/CartridgeRuntimeTests.swift:1121 |
| test350 | `test350_full_cli_mode_with_file_path_integration` | TEST350: Integration test - full CLI mode invocation with file-path | Tests/BifaciTests/CartridgeRuntimeTests.swift:1155 |
| test351 | `test351_file_path_array_empty_array` | TEST351: file-path-array with empty array succeeds | Tests/BifaciTests/CartridgeRuntimeTests.swift:1226 |
| test352 | `test352_file_permission_denied_clear_error` |  | Tests/BifaciTests/CartridgeRuntimeTests.swift:1264 |
| test353 | `test353_cbor_payload_format_consistency` | TEST353: CBOR payload format matches between CLI and CBOR mode | Tests/BifaciTests/CartridgeRuntimeTests.swift:1303 |
| test354 | `test354_glob_pattern_no_matches_empty_array` | TEST354: Glob pattern with no matches produces empty array | Tests/BifaciTests/CartridgeRuntimeTests.swift:1365 |
| test355 | `test355_glob_pattern_skips_directories` | TEST355: Glob pattern skips directories | Tests/BifaciTests/CartridgeRuntimeTests.swift:1409 |
| test356 | `test356_multiple_glob_patterns_combined` | TEST356: Multiple glob patterns combined | Tests/BifaciTests/CartridgeRuntimeTests.swift:1469 |
| test357 | `test357_symlinks_followed` |  | Tests/BifaciTests/CartridgeRuntimeTests.swift:1535 |
| test358 | `test358_binary_file_non_utf8` | TEST358: Binary file with non-UTF8 data reads correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1572 |
| test359 | `test359_invalid_glob_pattern_fails` | TEST359: Invalid glob pattern fails with clear error | Tests/BifaciTests/CartridgeRuntimeTests.swift:1607 |
| test360 | `test360_extract_effective_payload_with_file_data` | TEST360: Extract effective payload handles file-path data correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1643 |
| test361 | `test361_cli_mode_file_path` | TEST361: CLI mode with file path - pass file path as command-line argument | Tests/BifaciTests/CartridgeRuntimeTests.swift:1832 |
| test362 | `test362_cli_mode_piped_binary` | TEST362: CLI mode with binary piped in - pipe binary data via stdin  This test simulates real-world conditions: - Pure binary data piped to stdin (NOT CBOR) - CLI mode detected (command arg present) - Cap accepts stdin source - Binary is chunked on-the-fly and accumulated - Handler receives complete CBOR payload | Tests/BifaciTests/CartridgeRuntimeTests.swift:1877 |
| test363 | `test363_cbor_mode_chunked_content` | TEST363: CBOR mode with chunked content - send file content streaming as chunks | Tests/BifaciTests/CartridgeRuntimeTests.swift:1945 |
| test364 | `test364_cbor_mode_file_path` | TEST364: CBOR mode with file path - send file path in CBOR arguments (auto-conversion) | Tests/BifaciTests/CartridgeRuntimeTests.swift:2014 |
| test365 | `test365_streamStartFrame` | TEST365: Frame.stream_start stores reqId, streamId, and mediaUrn correctly | Tests/BifaciTests/FrameTests.swift:1034 |
| test366 | `test366_streamEndFrame` | TEST366: Frame.stream_end stores reqId and streamId correctly | Tests/BifaciTests/FrameTests.swift:1047 |
| test367 | `test367_streamStartWithEmptyStreamId` | TEST367: Frame.stream_start with empty streamId still constructs successfully | Tests/BifaciTests/FrameTests.swift:1060 |
| test368 | `test368_streamStartWithEmptyMediaUrn` | TEST368: Frame.stream_start with empty mediaUrn still constructs successfully | Tests/BifaciTests/FrameTests.swift:1072 |
| test389 | `test389_streamStartRoundtrip` | TEST389: StreamStart encode/decode roundtrip preserves stream_id and media_urn | Tests/BifaciTests/FrameTests.swift:1084 |
| test390 | `test390_streamEndRoundtrip` | TEST390: StreamEnd encode/decode roundtrip preserves stream_id, no media_urn | Tests/BifaciTests/FrameTests.swift:1120 |
| test395 | `test395_build_payload_small` | TEST395: Small payload (< max_chunk) produces correct CBOR arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:1685 |
| test396 | `test396_build_payload_large` | TEST396: Large payload (> max_chunk) accumulates across chunks correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1723 |
| test397 | `test397_build_payload_empty` | TEST397: Empty reader produces valid empty CBOR arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:1753 |
| test398 | `test398_build_payload_io_error` | TEST398: IO error from reader propagates as error | Tests/BifaciTests/CartridgeRuntimeTests.swift:1811 |
| test399 | `test399_relayNotifyDiscriminantRoundtrip` | TEST399: RelayNotify discriminant roundtrips through rawValue conversion (value 10) | Tests/BifaciTests/FrameTests.swift:1138 |
| test400 | `test400_relayStateDiscriminantRoundtrip` | TEST400: RelayState discriminant roundtrips through rawValue conversion (value 11) | Tests/BifaciTests/FrameTests.swift:1146 |
| test401 | `test401_relayNotifyFactoryAndAccessors` | TEST401: relay_notify factory stores manifest and limits, accessors extract them correctly | Tests/BifaciTests/FrameTests.swift:1154 |
| test402 | `test402_relayStateFactoryAndPayload` | TEST402: relay_state factory stores resource payload in payload field | Tests/BifaciTests/FrameTests.swift:1180 |
| test403 | `test403_frameTypeOnePastRelayState` | TEST403: FrameType from value 12 is nil (one past RelayState) | Tests/BifaciTests/FrameTests.swift:1190 |
| test404 | `test404_slaveSendsRelayNotifyOnConnect` | TEST404: Slave sends RelayNotify on connect (initial_notify parameter) | Tests/BifaciTests/RelayTests.swift:19 |
| test405 | `test405_masterReadsRelayNotify` | TEST405: Master reads RelayNotify and extracts manifest + limits | Tests/BifaciTests/RelayTests.swift:50 |
| test406 | `test406_slaveStoresRelayState` | TEST406: Slave stores RelayState from master | Tests/BifaciTests/RelayTests.swift:76 |
| test407 | `test407_protocolFramesPassThrough` | TEST407: Protocol frames pass through slave transparently (both directions) | Tests/BifaciTests/RelayTests.swift:104 |
| test408 | `test408_relayFramesNotForwarded` | TEST408: RelayNotify/RelayState are NOT forwarded through relay | Tests/BifaciTests/RelayTests.swift:163 |
| test409 | `test409_slaveInjectsRelayNotifyMidstream` | TEST409: Slave can inject RelayNotify mid-stream (cap change) | Tests/BifaciTests/RelayTests.swift:197 |
| test410 | `test410_masterReceivesUpdatedRelayNotify` | TEST410: Master receives updated RelayNotify (cap change callback via readFrame) | Tests/BifaciTests/RelayTests.swift:235 |
| test411 | `test411_socketCloseDetection` | TEST411: Socket close detection (both directions) | Tests/BifaciTests/RelayTests.swift:284 |
| test412 | `test412_bidirectionalConcurrentFlow` | TEST412: Bidirectional concurrent frame flow through relay | Tests/BifaciTests/RelayTests.swift:310 |
| test413 | `test413_registerCartridgeAddsToCaptable` | TEST413: registerCartridge adds to cap_table and findCartridgeForCap resolves it | Tests/BifaciTests/RuntimeTests.swift:268 |
| test414 | `test414_capabilitiesEmptyInitially` | TEST414: capabilities returns empty initially | Tests/BifaciTests/RuntimeTests.swift:276 |
| test415 | `test415_reqTriggersSpawnError` | TEST415: REQ for known cap triggers spawn (expect error for non-existent binary) | Tests/BifaciTests/RuntimeTests.swift:647 |
| test416 | `test416_attachCartridgeUpdatesCaps` | TEST416: attachCartridge extracts manifest and updates capabilities | Tests/BifaciTests/RuntimeTests.swift:295 |
| test417 | `test417_fullPathRequestResponse` | TEST417 + TEST426: Full path - engine REQ -> relay -> host -> cartridge -> response -> relay -> engine | Tests/BifaciTests/RuntimeTests.swift:325 |
| test418 | `test418_routeContinuationByReqId` | TEST418: Route STREAM_START/CHUNK/STREAM_END/END by req_id | Tests/BifaciTests/RuntimeTests.swift:678 |
| test419 | `test419_heartbeatHandledLocally` | TEST419: Cartridge HEARTBEAT handled locally (not forwarded to relay) | Tests/BifaciTests/RuntimeTests.swift:401 |
| test420 | `test420_cartridgeFramesForwardedToRelay` | TEST420: Cartridge non-HELLO/non-HB frames forwarded to relay | Tests/BifaciTests/RuntimeTests.swift:764 |
| test421 | `test421_cartridgeDeathUpdatesCaps` | TEST421: Cartridge death updates capability list (removes dead cartridge's caps) | Tests/BifaciTests/RuntimeTests.swift:838 |
| test422 | `test422_cartridgeDeathSendsErr` | TEST422: Cartridge death sends ERR for all pending requests | Tests/BifaciTests/RuntimeTests.swift:890 |
| test423 | `test423_multipleCartridgesRouteIndependently` | TEST423: Multiple cartridges registered with distinct caps route independently | Tests/BifaciTests/RuntimeTests.swift:478 |
| test424 | `test424_concurrentRequestsSameCartridge` | TEST424: Concurrent requests to same cartridge handled independently | Tests/BifaciTests/RuntimeTests.swift:957 |
| test425 | `test425_findCartridgeForCapUnknown` | TEST425: findCartridgeForCap returns nil for unknown cap | Tests/BifaciTests/RuntimeTests.swift:285 |
| test426 | `test426_single_master_req_response` | TEST426: Single master REQ/response routing | Tests/BifaciTests/RelaySwitchTests.swift:58 |
| test427 | `test427_multi_master_cap_routing` | TEST427: Multi-master cap routing | Tests/BifaciTests/RelaySwitchTests.swift:117 |
| test428 | `test428_unknown_cap_returns_error` | TEST428: Unknown cap returns error | Tests/BifaciTests/RelaySwitchTests.swift:212 |
| test429 | `test429_find_master_for_cap` | TEST429: Cap routing logic (find_master_for_cap) | Tests/BifaciTests/RelaySwitchTests.swift:253 |
| test430 | `test430_tie_breaking_same_cap_multiple_masters` | TEST430: Tie-breaking (same cap on multiple masters - first match wins, routing is consistent) | Tests/BifaciTests/RelaySwitchTests.swift:298 |
| test431 | `test431_continuation_frame_routing` | TEST431: Continuation frame routing (CHUNK, END follow REQ) | Tests/BifaciTests/RelaySwitchTests.swift:379 |
| test432 | `test432_empty_masters_allowed` | TEST432: Empty masters list creates empty switch (matching Rust behavior) | Tests/BifaciTests/RelaySwitchTests.swift:444 |
| test433 | `test433_capability_aggregation_deduplicates` | TEST433: Capability aggregation deduplicates caps | Tests/BifaciTests/RelaySwitchTests.swift:461 |
| test434 | `test434_limits_negotiation_minimum` | TEST434: Limits negotiation takes minimum | Tests/BifaciTests/RelaySwitchTests.swift:516 |
| test435 | `test435_urn_matching_exact_and_accepts` | TEST435: URN matching (exact vs accepts()) | Tests/BifaciTests/RelaySwitchTests.swift:562 |
| test436 | `test436_computeChecksum` | TEST436: compute_checksum produces consistent FNV-1a results | Tests/BifaciTests/FrameTests.swift:1318 |
| test437 | `test437_preferredCapRoutesToExactMatch` | TEST437: find_master_for_cap with preferred_cap routes to exact match NOTE: The Swift implementation requires exact cap URN match or conforms check | Tests/BifaciTests/RelaySwitchTests.swift:623 |
| test438 | `test438_preferredCapExactMatch` | TEST438: find_master_for_cap with exact match works | Tests/BifaciTests/RelaySwitchTests.swift:663 |
| test439 | `test439_specificRequestNoMatchingHandler` | TEST439: Specific request without matching handler returns noHandler | Tests/BifaciTests/RelaySwitchTests.swift:703 |
| test440 | `test440_chunkIndexChecksumRoundtrip` | TEST440: CHUNK frame with chunk_index and checksum roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:1342 |
| test441 | `test441_streamEndChunkCountRoundtrip` | TEST441: STREAM_END frame with chunk_count roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:1360 |
| test442 | `test442_seqAssignerMonotonicSameRid` | TEST442: SeqAssigner assigns seq 0,1,2,3 for consecutive frames with same RID | Tests/BifaciTests/FlowOrderingTests.swift:11 |
| test443 | `test443_seqAssignerIndependentRids` | TEST443: SeqAssigner maintains independent counters for different RIDs | Tests/BifaciTests/FlowOrderingTests.swift:32 |
| test444 | `test444_seqAssignerSkipsNonFlow` | TEST444: SeqAssigner skips non-flow frames (Heartbeat, RelayNotify, RelayState, Hello) | Tests/BifaciTests/FlowOrderingTests.swift:57 |
| test445 | `test445_seqAssignerRemoveByFlowKey` | TEST445: SeqAssigner.remove with FlowKey(rid, nil) resets that flow; FlowKey(rid, Some(xid)) is unaffected | Tests/BifaciTests/FlowOrderingTests.swift:77 |
| test446 | `test446_seqAssignerMixedTypes` | TEST446: SeqAssigner handles mixed frame types (REQ, CHUNK, LOG, END) for same RID | Tests/BifaciTests/FlowOrderingTests.swift:146 |
| test447 | `test447_flowKeyWithXid` | TEST447: FlowKey::from_frame extracts (rid, Some(xid)) when routing_id present | Tests/BifaciTests/FlowOrderingTests.swift:169 |
| test448 | `test448_flowKeyWithoutXid` | TEST448: FlowKey::from_frame extracts (rid, None) when routing_id absent | Tests/BifaciTests/FlowOrderingTests.swift:181 |
| test449 | `test449_flowKeyEquality` | TEST449: FlowKey equality: same rid+xid equal, different xid different key | Tests/BifaciTests/FlowOrderingTests.swift:191 |
| test450 | `test450_flowKeyHash` | TEST450: FlowKey hash: same keys hash equal (HashMap lookup) | Tests/BifaciTests/FlowOrderingTests.swift:207 |
| test451 | `test451_reorderBufferInOrder` | TEST451: ReorderBuffer in-order delivery: seq 0,1,2 delivered immediately | Tests/BifaciTests/FlowOrderingTests.swift:226 |
| test452 | `test452_reorderBufferOutOfOrder` | TEST452: ReorderBuffer out-of-order: seq 1 then 0 delivers both in order | Tests/BifaciTests/FlowOrderingTests.swift:248 |
| test453 | `test453_reorderBufferGapFill` | TEST453: ReorderBuffer gap fill: seq 0,2,1 delivers 0, buffers 2, then delivers 1+2 | Tests/BifaciTests/FlowOrderingTests.swift:266 |
| test454 | `test454_reorderBufferStaleSeq` | TEST454: ReorderBuffer stale seq is hard error | Tests/BifaciTests/FlowOrderingTests.swift:289 |
| test455 | `test455_reorderBufferOverflow` | TEST455: ReorderBuffer overflow triggers protocol error | Tests/BifaciTests/FlowOrderingTests.swift:307 |
| test456 | `test456_reorderBufferMultipleFlows` | TEST456: Multiple concurrent flows reorder independently | Tests/BifaciTests/FlowOrderingTests.swift:328 |
| test457 | `test457_reorderBufferCleanupFlow` | TEST457: cleanup_flow removes state; new frames start at seq 0 | Tests/BifaciTests/FlowOrderingTests.swift:357 |
| test458 | `test458_reorderBufferNonFlowBypass` | TEST458: Non-flow frames bypass reorder entirely | Tests/BifaciTests/FlowOrderingTests.swift:377 |
| test459 | `test459_reorderBufferTerminalEnd` | TEST459: Terminal END frame flows through correctly | Tests/BifaciTests/FlowOrderingTests.swift:390 |
| test460 | `test460_reorderBufferTerminalErr` | TEST460: Terminal ERR frame flows through correctly | Tests/BifaciTests/FlowOrderingTests.swift:408 |
| test461 | `test461_writeChunkedSeqZero` |  | Tests/BifaciTests/FlowOrderingTests.swift:427 |
| test472 | `test472_handshakeNegotiatesReorderBuffer` |  | Tests/BifaciTests/FlowOrderingTests.swift:457 |
| test473 | `test473_capDiscardParsesAsValidCapUrn` | TEST473: CAP_DISCARD parses as valid CapUrn | Tests/BifaciTests/StandardCapsTests.swift:14 |
| test474 | `test474_capDiscardAcceptsVoidOutputCaps` | TEST474: CAP_DISCARD accepts specific void-output caps | Tests/BifaciTests/StandardCapsTests.swift:23 |
| test475 | `test475_manifestValidatePassesWithIdentity` | TEST475: Manifest.validate() passes with CAP_IDENTITY present | Tests/BifaciTests/StandardCapsTests.swift:41 |
| test476 | `test476_manifestValidateFailsWithoutIdentity` | TEST476: Manifest.validate() fails without CAP_IDENTITY | Tests/BifaciTests/StandardCapsTests.swift:53 |
| test477 | `test477_manifestEnsureIdentityIdempotent` | TEST477: Manifest.ensureIdentity() adds if missing, idempotent if present | Tests/BifaciTests/StandardCapsTests.swift:65 |
| test478 | `test478_cartridgeRuntimeAutoRegistersIdentity` | TEST478: CartridgeRuntime auto-registers CAP_IDENTITY handler | Tests/BifaciTests/StandardCapsTests.swift:86 |
| test479 | `test479_identityHandlerEchoesInput` | TEST479: CAP_IDENTITY handler echoes input unchanged | Tests/BifaciTests/StandardCapsTests.swift:101 |
| test480 | `test480_discardHandlerConsumesInput` | TEST480: CAP_DISCARD handler consumes input and produces void | Tests/BifaciTests/StandardCapsTests.swift:169 |
| test481 | `test481_verifyIdentitySucceeds` | TEST481: verify_identity succeeds with standard identity echo handler | Tests/BifaciTests/IntegrationTests.swift:496 |
| test482 | `test482_verifyIdentityFailsOnErr` | TEST482: verify_identity fails when cartridge returns ERR | Tests/BifaciTests/IntegrationTests.swift:583 |
| test483 | `test483_verifyIdentityFailsOnClose` | TEST483: verify_identity fails when connection closes | Tests/BifaciTests/IntegrationTests.swift:926 |
| test485 | `test485_attachCartridgeIdentityVerificationSucceeds` | TEST485: attach_cartridge completes identity verification with working cartridge | Tests/BifaciTests/RuntimeTests.swift:1296 |
| test486 | `test486_attachCartridgeIdentityVerificationFails` | TEST486: attach_cartridge rejects cartridge that fails identity verification | Tests/BifaciTests/RuntimeTests.swift:1369 |
| test487 | `test487_relaySwitchIdentityVerificationSucceeds` | TEST487: RelaySwitch construction verifies identity through relay chain | Tests/BifaciTests/RelaySwitchTests.swift:741 |
| test488 | `test488_relaySwitchIdentityVerificationFails` | TEST488: RelaySwitch construction fails when master's identity verification fails | Tests/BifaciTests/RelaySwitchTests.swift:770 |
| test489 | `test489_addMasterDynamic` | TEST489: add_master dynamically connects new host to running switch | Tests/BifaciTests/RelaySwitchTests.swift:804 |
| test490 | `test490_identityVerificationMultipleCartridges` | TEST490: Identity verification with multiple cartridges through single relay | Tests/BifaciTests/RuntimeTests.swift:1423 |
| test491 | `test491_chunkRequiresChunkIndexAndChecksum` | TEST491: Frame.chunk constructor requires and sets chunk_index and checksum | Tests/BifaciTests/FrameTests.swift:1374 |
| test492 | `test492_streamEndRequiresChunkCount` | TEST492: Frame.streamEnd constructor requires and sets chunk_count | Tests/BifaciTests/FrameTests.swift:1386 |
| test493 | `test493_computeChecksumFnv1aTestVectors` | TEST493: compute_checksum produces correct FNV-1a hash for known test vectors | Tests/BifaciTests/FrameTests.swift:1395 |
| test494 | `test494_computeChecksumDeterministic` | TEST494: compute_checksum is deterministic | Tests/BifaciTests/FrameTests.swift:1413 |
| test495 | `test495_cborRejectsChunkWithoutChunkIndex` | TEST495: CBOR decode REJECTS CHUNK frame missing chunk_index field | Tests/BifaciTests/FrameTests.swift:1425 |
| test496 | `test496_cborRejectsChunkWithoutChecksum` | TEST496: CBOR decode REJECTS CHUNK frame missing checksum field | Tests/BifaciTests/FrameTests.swift:1449 |
| test497 | `test497_chunkCorruptedPayloadRejected` | TEST497: Verify CHUNK frame with corrupted payload is rejected by checksum verification | Tests/BifaciTests/FrameTests.swift:1473 |
| test498 | `test498_routingIdCborRoundtrip` | TEST498: routing_id field roundtrips through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1489 |
| test499 | `test499_chunkIndexChecksumCborRoundtrip` | TEST499: chunk_index and checksum roundtrip through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1503 |
| test500 | `test500_chunkCountCborRoundtrip` | TEST500: chunk_count roundtrips through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1518 |
| test501 | `test501_frameNewInitializesOptionalFieldsNone` | TEST501: Frame init initializes new fields to None | Tests/BifaciTests/FrameTests.swift:1530 |
| test502 | `test502_keysModuleNewFieldConstants` | TEST502: Keys module has constants for new fields | Tests/BifaciTests/FrameTests.swift:1540 |
| test503 | `test503_computeChecksumEmptyData` | TEST503: compute_checksum handles empty data correctly | Tests/BifaciTests/FrameTests.swift:1548 |
| test504 | `test504_computeChecksumLargePayload` | TEST504: compute_checksum handles large payloads without overflow | Tests/BifaciTests/FrameTests.swift:1556 |
| test505 | `test505_chunkWithOffsetSetsChunkIndex` | TEST505: chunk_with_offset sets chunk_index correctly | Tests/BifaciTests/FrameTests.swift:1567 |
| test506 | `test506_computeChecksumDifferentDataDifferentHash` | TEST506: Different data produces different checksums | Tests/BifaciTests/FrameTests.swift:1590 |
| test507 | `test507_reorderBufferXidIsolation` | TEST507: ReorderBuffer isolates flows by XID (routing_id) - same RID different XIDs | Tests/BifaciTests/FlowOrderingTests.swift:502 |
| test508 | `test508_reorderBufferDuplicateBufferedSeq` | TEST508: ReorderBuffer rejects duplicate seq already in buffer | Tests/BifaciTests/FlowOrderingTests.swift:525 |
| test509 | `test509_reorderBufferLargeGapRejected` | TEST509: ReorderBuffer handles large seq gaps without DOS | Tests/BifaciTests/FlowOrderingTests.swift:546 |
| test510 | `test510_reorderBufferMultipleGaps` | TEST510: ReorderBuffer with multiple interleaved gaps fills correctly | Tests/BifaciTests/FlowOrderingTests.swift:571 |
| test511 | `test511_reorderBufferRejectsStaleSeq` | TEST511: ReorderBuffer rejects seq < expected (stale frame) | Tests/BifaciTests/FlowOrderingTests.swift:597 |
| test512 | `test512_reorderBufferNonFlowFramesBypass` | TEST512: ReorderBuffer non-flow frames bypass reordering | Tests/BifaciTests/FlowOrderingTests.swift:620 |
| test513 | `test513_reorderBufferCleanup` | TEST513: ReorderBuffer cleanup removes flow state | Tests/BifaciTests/FlowOrderingTests.swift:641 |
| test514 | `test514_reorderBufferRespectsMaxBuffer` | TEST514: ReorderBuffer respects maxBufferPerFlow | Tests/BifaciTests/FlowOrderingTests.swift:659 |
| test515 | `test515_seqAssignerRemoveByFlowKey` | TEST515: SeqAssigner removes flow by FlowKey | Tests/BifaciTests/FlowOrderingTests.swift:684 |
| test516 | `test516_seqAssignerIndependentFlowsByXid` | TEST516: SeqAssigner independent flows by XID | Tests/BifaciTests/FlowOrderingTests.swift:707 |
| test517 | `test517_flowKeyNilXidSeparate` | TEST517: FlowKey with nil XID is separate from FlowKey with XID | Tests/BifaciTests/FlowOrderingTests.swift:739 |
| test518 | `test518_reorderBufferFlowCleanupAfterEnd` | TEST518: ReorderBuffer flow cleanup after END | Tests/BifaciTests/FlowOrderingTests.swift:770 |
| test519 | `test519_reorderBufferMultipleRids` | TEST519: ReorderBuffer handles frames from multiple RIDs | Tests/BifaciTests/FlowOrderingTests.swift:792 |
| test520 | `test520_reorderBufferDrainsBufferedFrames` | TEST520: ReorderBuffer drains buffered frames when gap is filled | Tests/BifaciTests/FlowOrderingTests.swift:814 |
| test521 | `test521_relayNotifyCborRoundtrip` | TEST521: RelayNotify CBOR roundtrip preserves manifest and limits | Tests/BifaciTests/FrameTests.swift:1195 |
| test522 | `test522_relayStateCborRoundtrip` | TEST522: RelayState CBOR roundtrip preserves payload | Tests/BifaciTests/FrameTests.swift:1216 |
| test523 | `test523_relayNotifyNotFlowFrame` | TEST523: is_flow_frame returns false for RelayNotify | Tests/BifaciTests/FrameTests.swift:1605 |
| test524 | `test524_relayStateNotFlowFrame` | TEST524: is_flow_frame returns false for RelayState | Tests/BifaciTests/FrameTests.swift:1611 |
| test525 | `test525_relayNotifyEmptyManifest` | TEST525: RelayNotify with empty manifest is valid | Tests/BifaciTests/FrameTests.swift:1617 |
| test526 | `test526_relayStateEmptyPayload` | TEST526: RelayState with empty payload is valid | Tests/BifaciTests/FrameTests.swift:1628 |
| test527 | `test527_relayNotifyLargeManifest` | TEST527: RelayNotify with large manifest roundtrips correctly | Tests/BifaciTests/FrameTests.swift:1639 |
| test528 | `test528_relayFramesUseUintZeroId` | TEST528: RelayNotify and RelayState use MessageId::Uint(0) | Tests/BifaciTests/FrameTests.swift:1651 |
| test529 | `test529_inputStreamIteratorOrder` | TEST529: InputStream iterator yields chunks in order | Tests/BifaciTests/StreamingAPITests.swift:20 |
| test530 | `test530_inputStreamCollectBytes` | TEST530: InputStream::collect_bytes concatenates byte chunks | Tests/BifaciTests/StreamingAPITests.swift:57 |
| test531 | `test531_inputStreamCollectBytesText` | TEST531: InputStream::collect_bytes handles text chunks | Tests/BifaciTests/StreamingAPITests.swift:79 |
| test532 | `test532_inputStreamEmpty` | TEST532: InputStream empty stream produces empty bytes | Tests/BifaciTests/StreamingAPITests.swift:101 |
| test533 | `test533_inputStreamErrorPropagation` | TEST533: InputStream propagates errors | Tests/BifaciTests/StreamingAPITests.swift:119 |
| test534 | `test534_inputStreamMediaUrn` | TEST534: InputStream::media_urn returns correct URN | Tests/BifaciTests/StreamingAPITests.swift:146 |
| test535 | `test535_inputPackageIteration` | TEST535: InputPackage iterator yields streams | Tests/BifaciTests/StreamingAPITests.swift:156 |
| test536 | `test536_inputPackageCollectAllBytes` | TEST536: InputPackage::collect_all_bytes aggregates all streams | Tests/BifaciTests/StreamingAPITests.swift:202 |
| test537 | `test537_inputPackageEmpty` | TEST537: InputPackage empty package produces empty bytes | Tests/BifaciTests/StreamingAPITests.swift:243 |
| test538 | `test538_inputPackageErrorPropagation` | TEST538: InputPackage propagates stream errors | Tests/BifaciTests/StreamingAPITests.swift:261 |
| test539 | `test539_outputStreamSendsStreamStart` | TEST539: OutputStream.start() sends STREAM_START with isSequence | Tests/BifaciTests/StreamingAPITests.swift:289 |
| test540 | `test540_outputStreamCloseSendsStreamEnd` | TEST540: OutputStream::close sends STREAM_END with correct chunk_count | Tests/BifaciTests/StreamingAPITests.swift:319 |
| test541 | `test541_outputStreamChunksLargeData` | TEST541: OutputStream chunks large data correctly | Tests/BifaciTests/StreamingAPITests.swift:350 |
| test542 | `test542_outputStreamCloseWithoutStartIsNoop` | TEST542: OutputStream close without start is a no-op (no frames sent) | Tests/BifaciTests/StreamingAPITests.swift:385 |
| test543 | `test543_peerCallArgCreatesStream` | TEST543: PeerCall::arg creates OutputStream with correct stream_id | Tests/BifaciTests/StreamingAPITests.swift:490 |
| test544 | `test544_peerCallFinishSendsEnd` | TEST544: PeerCall::finish sends END frame | Tests/BifaciTests/StreamingAPITests.swift:519 |
| test545 | `test545_peerCallFinishReturnsPeerResponse` | TEST545: PeerCall::finish returns PeerResponse with data | Tests/BifaciTests/StreamingAPITests.swift:541 |
| test546 | `test546_is_image` | TEST546: is_image | Tests/CapDAGTests/CSMediaUrnTests.m:225 |
| test547 | `test547_is_audio` | TEST547: is_audio | Tests/CapDAGTests/CSMediaUrnTests.m:237 |
| test548 | `test548_is_video` | TEST548: is_video | Tests/CapDAGTests/CSMediaUrnTests.m:248 |
| test549 | `test549_is_numeric` | TEST549: is_numeric | Tests/CapDAGTests/CSMediaUrnTests.m:258 |
| test550 | `test550_is_bool` | TEST550: is_bool | Tests/CapDAGTests/CSMediaUrnTests.m:270 |
| test551 | `test551_is_file_path` | TEST551: is_file_path | Tests/CapDAGTests/CSMediaUrnTests.m:282 |
| test552 | `test552_is_file_path_array` | TEST552: is_file_path_array | Tests/CapDAGTests/CSMediaUrnTests.m:292 |
| test553 | `test553_is_any_file_path` | TEST553: is_any_file_path | Tests/CapDAGTests/CSMediaUrnTests.m:300 |
| test555 | `test555_with_tag_and_without_tag` | TEST555: with_tag and without_tag | Tests/CapDAGTests/CSMediaUrnTests.m:309 |
| test558 | `test558_predicate_constant_consistency` | TEST558: predicate/constant consistency | Tests/CapDAGTests/CSMediaUrnTests.m:327 |
| test571 | `test571_get_all_capabilities` | TEST571: getAllCapabilities returns caps from all hosts | Tests/CapDAGTests/CSCapMatrixTests.m:264 |
| test574 | `test574_cap_block_remove_registry` | TEST574: CapBlock remove_registry | Tests/CapDAGTests/CSCapMatrixTests.m:440 |
| test575 | `test575_cap_block_get_registry` | TEST575: CapBlock get_registry | Tests/CapDAGTests/CSCapMatrixTests.m:456 |
| test576 | `test576_cap_block_get_registry_names` | TEST576: CapBlock get_registry_names in insertion order | Tests/CapDAGTests/CSCapMatrixTests.m:465 |
| test577 | `test577_cap_graph_input_output_specs` | TEST577: CapGraph input/output specs | Tests/CapDAGTests/CSCapMatrixTests.m:412 |
| test638 | `test638_noPeerRouterRejectsAll` | TEST638: NoPeerRouter rejects all requests with PeerInvokeNotSupported | Tests/BifaciTests/RouterTests.swift:14 |
| test654 | `test654_routesReqToHandler` | MARK: - TEST654: InProcessCartridgeHost routes REQ to matching handler and returns response | Tests/BifaciTests/InProcessCartridgeHostTests.swift:115 |
| test655 | `test655_identityVerification` | MARK: - TEST655: InProcessCartridgeHost handles identity verification (echo nonce) | Tests/BifaciTests/InProcessCartridgeHostTests.swift:191 |
| test656 | `test656_noHandlerReturnsErr` | MARK: - TEST656: InProcessCartridgeHost returns NO_HANDLER for unregistered cap | Tests/BifaciTests/InProcessCartridgeHostTests.swift:250 |
| test657 | `test657_manifestIncludesAllCaps` | MARK: - TEST657: InProcessCartridgeHost manifest includes identity cap and handler caps | Tests/BifaciTests/InProcessCartridgeHostTests.swift:290 |
| test658 | `test658_heartbeatResponse` | MARK: - TEST658: InProcessCartridgeHost handles heartbeat by echoing same ID | Tests/BifaciTests/InProcessCartridgeHostTests.swift:306 |
| test659 | `test659_handlerErrorReturnsErrFrame` | MARK: - TEST659: InProcessCartridgeHost handler error returns ERR frame | Tests/BifaciTests/InProcessCartridgeHostTests.swift:338 |
| test660 | `test660_closestSpecificityRouting` | MARK: - TEST660: InProcessCartridgeHost closest-specificity routing prefers specific over generic | Tests/BifaciTests/InProcessCartridgeHostTests.swift:382 |
| test661 | `test661_cartridgeDeathKeepsKnownCapsAdvertised` | TEST661: Cartridge death keeps known_caps advertised for on-demand respawn | Tests/BifaciTests/RuntimeTests.swift:1065 |
| test662 | `test662_rebuildCapabilitiesIncludesNonRunningCartridges` | TEST662: rebuild_capabilities includes non-running cartridges' known_caps | Tests/BifaciTests/RuntimeTests.swift:1082 |
| test663 | `test663_helloFailedCartridgeRemovedFromCapabilities` | TEST663: Cartridge with hello_failed is permanently removed from capabilities | Tests/BifaciTests/RuntimeTests.swift:1098 |
| test664 | `test664_runningCartridgeUsesManifestCaps` | TEST664: Running cartridge uses manifest caps, not known_caps | Tests/BifaciTests/RuntimeTests.swift:1137 |
| test665 | `test665_capTableMixedRunningAndNonRunning` | TEST665: Cap table uses manifest caps for running, known_caps for non-running | Tests/BifaciTests/RuntimeTests.swift:1176 |
| test667 | `test667_verifyChunkChecksumDetectsCorruption` | TEST667: verify_chunk_checksum detects corrupted payload | Tests/BifaciTests/FrameTests.swift:1228 |
| test678 | `test678_findStreamEquivalentUrnDifferentTagOrder` | TEST678: find_stream with exact equivalent URN (same tags, different order) succeeds | Tests/BifaciTests/StreamingAPITests.swift:578 |
| test679 | `test679_findStreamBaseUrnDoesNotMatchFullUrn` | TEST679: find_stream with base URN vs full URN fails — is_equivalent is strict | Tests/BifaciTests/StreamingAPITests.swift:591 |
| test680 | `test680_requireStreamMissingUrnReturnsError` | TEST680: require_stream with missing URN returns hard StreamError | Tests/BifaciTests/StreamingAPITests.swift:602 |
| test681 | `test681_findStreamMultipleStreamsReturnsCorrect` | TEST681: find_stream with multiple streams returns the correct one | Tests/BifaciTests/StreamingAPITests.swift:617 |
| test682 | `test682_requireStreamStrReturnsUtf8` | TEST682: require_stream_str returns UTF-8 string for text data | Tests/BifaciTests/StreamingAPITests.swift:635 |
| test683 | `test683_findStreamInvalidUrnReturnsNone` | TEST683: find_stream returns nil for invalid media URN string (not a parse error — just nil) | Tests/BifaciTests/StreamingAPITests.swift:645 |
| test684 | `test684_from_media_urn_single` | TEST684: Tests InputCardinality correctly identifies single-value media URNs Verifies that URNs without list marker are parsed as Single cardinality | Tests/CapDAGTests/CSCardinalityTests.m:20 |
| test685 | `test685_from_media_urn_vector` | TEST685: Tests InputCardinality correctly identifies list/vector media URNs Verifies that URNs with list marker tag are parsed as Sequence cardinality | Tests/CapDAGTests/CSCardinalityTests.m:30 |
| test686 | `test686_from_media_urn_vector_tag_position` | TEST686: Tests that list marker tag position doesn't affect vector detection Verifies cardinality parsing is independent of tag order in URN | Tests/CapDAGTests/CSCardinalityTests.m:40 |
| test687 | `test687_from_media_urn_no_false_positives` | TEST687: Tests that URN content doesn't cause false positive vector detection Verifies that "list" in media type name doesn't trigger Sequence cardinality | Tests/CapDAGTests/CSCardinalityTests.m:47 |
| test688 | `test688_is_multiple` | TEST688: Tests is_multiple method correctly identifies multi-value cardinalities Verifies Single returns false while Sequence and AtLeastOne return true | Tests/CapDAGTests/CSCardinalityTests.m:55 |
| test689 | `test689_accepts_single` | TEST689: Tests accepts_single method identifies cardinalities that accept single values Verifies Single and AtLeastOne accept singles while Sequence does not | Tests/CapDAGTests/CSCardinalityTests.m:63 |
| test690 | `test690_compatibility_single_to_single` | TEST690: Tests cardinality compatibility for single-to-single data flow Verifies Direct compatibility when both input and output are Single | Tests/CapDAGTests/CSCardinalityTests.m:73 |
| test691 | `test691_compatibility_single_to_vector` | TEST691: Tests cardinality compatibility when wrapping single value into array Verifies WrapInArray compatibility when Sequence expects Single input | Tests/CapDAGTests/CSCardinalityTests.m:80 |
| test692 | `test692_compatibility_vector_to_single` | TEST692: Tests cardinality compatibility when unwrapping array to singles Verifies RequiresFanOut compatibility when Single expects Sequence input | Tests/CapDAGTests/CSCardinalityTests.m:87 |
| test693 | `test693_compatibility_vector_to_vector` | TEST693: Tests cardinality compatibility for sequence-to-sequence data flow Verifies Direct compatibility when both input and output are Sequence | Tests/CapDAGTests/CSCardinalityTests.m:94 |
| test694 | `test694_apply_to_urn_add_vector` | TEST694: Tests applying Sequence cardinality adds list marker to URN Verifies that apply_to_urn correctly modifies URN to indicate list | Tests/CapDAGTests/CSCardinalityTests.m:103 |
| test695 | `test695_apply_to_urn_remove_vector` | TEST695: Tests applying Single cardinality removes list marker from URN Verifies that apply_to_urn correctly strips list marker | Tests/CapDAGTests/CSCardinalityTests.m:111 |
| test696 | `test696_apply_to_urn_no_change_needed` | TEST696: Tests apply_to_urn is idempotent when URN already matches cardinality Verifies that URN remains unchanged when cardinality already matches desired | Tests/CapDAGTests/CSCardinalityTests.m:118 |
| test697 | `test697_cap_shape_info_one_to_one` | TEST697: Tests CapCardinalityInfo correctly identifies one-to-one pattern Verifies Single input and Single output result in OneToOne pattern | Tests/CapDAGTests/CSCardinalityTests.m:127 |
| test698 | `test698_cap_shape_info_one_to_many` | TEST698: Tests CapCardinalityInfo correctly identifies one-to-many pattern Verifies Single input and Sequence output result in OneToMany pattern | Tests/CapDAGTests/CSCardinalityTests.m:136 |
| test699 | `test699_cap_shape_info_many_to_one` | TEST699: Tests CapCardinalityInfo correctly identifies many-to-one pattern Verifies Sequence input and Single output result in ManyToOne pattern | Tests/CapDAGTests/CSCardinalityTests.m:145 |
| test709 | `test709_pattern_produces_vector` | TEST709: Tests CardinalityPattern correctly identifies patterns that produce vectors Verifies OneToMany and ManyToMany return true, others return false | Tests/CapDAGTests/CSCardinalityTests.m:156 |
| test710 | `test710_pattern_requires_vector` | TEST710: Tests CardinalityPattern correctly identifies patterns that require vectors Verifies ManyToOne and ManyToMany return true, others return false | Tests/CapDAGTests/CSCardinalityTests.m:165 |
| test711 | `test711_strand_shape_analysis_simple_linear` | TEST711: Tests shape chain analysis for simple linear one-to-one capability chains Verifies chains with no fan-out are valid and require no transformation | Tests/CapDAGTests/CSCardinalityTests.m:176 |
| test712 | `test712_strand_shape_analysis_with_fan_out` | TEST712: Tests shape chain analysis detects fan-out points in capability chains Verifies chains with one-to-many transitions are marked for transformation | Tests/CapDAGTests/CSCardinalityTests.m:189 |
| test713 | `test713_strand_shape_analysis_empty` | TEST713: Tests shape chain analysis handles empty capability chains correctly Verifies empty chains are valid and require no transformation | Tests/CapDAGTests/CSCardinalityTests.m:202 |
| test714 | `test714_cardinality_enum_values` | TEST714: Tests InputCardinality enum values are distinct and stable | Tests/CapDAGTests/CSCardinalityTests.m:213 |
| test715 | `test715_pattern_enum_values` | TEST715: Tests CardinalityPattern enum values are distinct and stable | Tests/CapDAGTests/CSCardinalityTests.m:220 |
| test720 | `test720_from_media_urn_opaque` | TEST720: Tests InputStructure correctly identifies opaque media URNs Verifies that URNs without record marker are parsed as Opaque | Tests/CapDAGTests/CSCardinalityTests.m:230 |
| test721 | `test721_from_media_urn_record` | TEST721: Tests InputStructure correctly identifies record media URNs Verifies that URNs with record marker tag are parsed as Record | Tests/CapDAGTests/CSCardinalityTests.m:240 |
| test722 | `test722_structure_compatibility_opaque_to_opaque` | TEST722: Tests structure compatibility for opaque-to-opaque data flow | Tests/CapDAGTests/CSCardinalityTests.m:249 |
| test723 | `test723_structure_compatibility_record_to_record` | TEST723: Tests structure compatibility for record-to-record data flow | Tests/CapDAGTests/CSCardinalityTests.m:255 |
| test724 | `test724_structure_incompatibility_opaque_to_record` | TEST724: Tests structure incompatibility for opaque-to-record flow | Tests/CapDAGTests/CSCardinalityTests.m:261 |
| test725 | `test725_structure_incompatibility_record_to_opaque` | TEST725: Tests structure incompatibility for record-to-opaque flow | Tests/CapDAGTests/CSCardinalityTests.m:267 |
| test726 | `test726_apply_structure_add_record` | TEST726: Tests applying Record structure adds record marker to URN | Tests/CapDAGTests/CSCardinalityTests.m:273 |
| test727 | `test727_apply_structure_remove_record` | TEST727: Tests applying Opaque structure removes record marker from URN | Tests/CapDAGTests/CSCardinalityTests.m:279 |
| test730 | `test730_media_shape_from_urn_all_combinations` | TEST730: Tests MediaShape correctly parses all four combinations | Tests/CapDAGTests/CSCardinalityTests.m:287 |
| test731 | `test731_media_shape_compatible_direct` | TEST731: Tests MediaShape compatibility for matching shapes | Tests/CapDAGTests/CSCardinalityTests.m:310 |
| test732 | `test732_media_shape_cardinality_changes` | TEST732: Tests MediaShape compatibility for cardinality changes with matching structure | Tests/CapDAGTests/CSCardinalityTests.m:324 |
| test733 | `test733_media_shape_structure_mismatch` | TEST733: Tests MediaShape incompatibility when structures don't match | Tests/CapDAGTests/CSCardinalityTests.m:340 |
| test740 | `test740_cap_shape_info_from_specs` | TEST740: Tests CapShapeInfo correctly parses cap specs | Tests/CapDAGTests/CSCardinalityTests.m:360 |
| test741 | `test741_cap_shape_info_pattern` | TEST741: Tests CapShapeInfo pattern detection | Tests/CapDAGTests/CSCardinalityTests.m:371 |
| test750 | `test750_strand_shape_valid` | TEST750: Tests shape chain analysis for valid chain with matching structures | Tests/CapDAGTests/CSCardinalityTests.m:381 |
| test751 | `test751_strand_shape_structure_mismatch` | TEST751: Tests shape chain analysis detects structure mismatch | Tests/CapDAGTests/CSCardinalityTests.m:392 |
| test752 | `test752_strand_shape_with_fanout` | TEST752: Tests shape chain analysis with fan-out (matching structures) | Tests/CapDAGTests/CSCardinalityTests.m:405 |
| test753 | `test753_strand_shape_list_record_to_list_record` | TEST753: Tests shape chain analysis correctly handles list-to-list record flow | Tests/CapDAGTests/CSCardinalityTests.m:417 |
| test780 | `test780_splitIntegerArray` | TEST780: splitCborArray splits integer array | Tests/BifaciTests/CborSequenceTests.swift:236 |
| test782 | `test782_splitNonArray` | TEST782: splitCborArray rejects non-array input | Tests/BifaciTests/CborSequenceTests.swift:266 |
| test783 | `test783_splitEmptyArray` | TEST783: splitCborArray rejects empty array | Tests/BifaciTests/CborSequenceTests.swift:284 |
| test784 | `test784_splitInvalidCbor` | TEST784: splitCborArray rejects invalid CBOR bytes | Tests/BifaciTests/CborSequenceTests.swift:302 |
| test785 | `test785_assembleIntegerArray` | TEST785: assembleCborArray creates array from individual items | Tests/BifaciTests/CborSequenceTests.swift:321 |
| test786 | `test786_roundtripSplitAssemble` | TEST786: split then assemble roundtrip preserves data | Tests/BifaciTests/CborSequenceTests.swift:342 |
| test810 | `test810_splitSequenceBytes` | TEST810: splitCborSequence splits concatenated CBOR Bytes values | Tests/BifaciTests/CborSequenceTests.swift:26 |
| test811 | `test811_splitSequenceText` | TEST811: splitCborSequence splits concatenated CBOR Text values | Tests/BifaciTests/CborSequenceTests.swift:50 |
| test812 | `test812_splitSequenceMixed` | TEST812: splitCborSequence handles mixed types | Tests/BifaciTests/CborSequenceTests.swift:66 |
| test813 | `test813_splitSequenceSingle` | TEST813: splitCborSequence single-item sequence | Tests/BifaciTests/CborSequenceTests.swift:84 |
| test814 | `test814_roundtripAssembleSplitSequence` | TEST814: roundtrip — assemble then split preserves items | Tests/BifaciTests/CborSequenceTests.swift:96 |
| test815 | `test815_roundtripSplitAssembleSequence` | TEST815: roundtrip — split then assemble preserves byte-for-byte | Tests/BifaciTests/CborSequenceTests.swift:114 |
| test816 | `test816_splitSequenceEmpty` | TEST816: splitCborSequence rejects empty data | Tests/BifaciTests/CborSequenceTests.swift:127 |
| test817 | `test817_splitSequenceTruncated` | TEST817: splitCborSequence rejects truncated CBOR | Tests/BifaciTests/CborSequenceTests.swift:142 |
| test818 | `test818_assembleSequenceInvalidItem` | TEST818: assembleCborSequence rejects invalid CBOR item | Tests/BifaciTests/CborSequenceTests.swift:165 |
| test819 | `test819_assembleSequenceEmpty` | TEST819: assembleCborSequence with empty items list produces empty bytes | Tests/BifaciTests/CborSequenceTests.swift:186 |
| test820 | `test820_singleValueSequence` | TEST820: single CBOR value is a valid sequence of 1 item | Tests/BifaciTests/CborSequenceTests.swift:192 |
| test821 | `test821_inputStreamCollectCborSequence` | TEST821: collectCborSequence on InputStream preserves CBOR structure | Tests/BifaciTests/CborSequenceTests.swift:202 |
| test822 | `test822_collectBytesVsSequence` | TEST822: collectBytes vs collectCborSequence produce different results for same input | Tests/BifaciTests/CborSequenceTests.swift:593 |
| test823 | `test823_isDispatchable_exactMatch` | TEST823: is_dispatchable — exact match provider dispatches request | Tests/CapDAGTests/CSCapUrnTests.m:1097 |
| test824 | `test824_isDispatchable_broaderInputHandlesSpecific` | TEST824: is_dispatchable — provider with broader input handles specific request (contravariance) | Tests/CapDAGTests/CSCapUrnTests.m:1107 |
| test825 | `test825_isDispatchable_unconstrainedInput` | TEST825: is_dispatchable — request with unconstrained input dispatches to specific provider media: on the request input axis means "unconstrained" — vacuously true | Tests/CapDAGTests/CSCapUrnTests.m:1118 |
| test826 | `test826_isDispatchable_providerOutputSatisfiesRequest` | TEST826: is_dispatchable — provider output must satisfy request output (covariance) | Tests/CapDAGTests/CSCapUrnTests.m:1128 |
| test827 | `test827_isDispatchable_genericOutputCannotSatisfySpecific` | TEST827: is_dispatchable — provider with generic output cannot satisfy specific request | Tests/CapDAGTests/CSCapUrnTests.m:1138 |
| test828 | `test828_isDispatchable_wildcardRequestProviderMissingTag` | TEST828: is_dispatchable — wildcard * tag in request, provider missing tag → reject | Tests/CapDAGTests/CSCapUrnTests.m:1148 |
| test829 | `test829_isDispatchable_wildcardRequestProviderHasTag` | TEST829: is_dispatchable — wildcard * tag in request, provider has tag → accept | Tests/CapDAGTests/CSCapUrnTests.m:1158 |
| test830 | `test830_isDispatchable_providerExtraTags` | TEST830: is_dispatchable — provider extra tags are refinement, always OK | Tests/CapDAGTests/CSCapUrnTests.m:1168 |
| test831 | `test831_isDispatchable_crossBackendMismatch` | TEST831: is_dispatchable — cross-backend mismatch prevented | Tests/CapDAGTests/CSCapUrnTests.m:1178 |
| test832 | `test832_isDispatchable_asymmetric` | TEST832: is_dispatchable is NOT symmetric | Tests/CapDAGTests/CSCapUrnTests.m:1188 |
| test833 | `test833_isComparable_symmetric` | TEST833: is_comparable — both directions checked | Tests/CapDAGTests/CSCapUrnTests.m:1199 |
| test834 | `test834_isComparable_unrelated` | TEST834: is_comparable — unrelated caps are NOT comparable | Tests/CapDAGTests/CSCapUrnTests.m:1210 |
| test835 | `test835_isEquivalent_identical` | TEST835: is_equivalent — identical caps | Tests/CapDAGTests/CSCapUrnTests.m:1221 |
| test836 | `test836_isEquivalent_nonEquivalent` | TEST836: is_equivalent — non-equivalent comparable caps | Tests/CapDAGTests/CSCapUrnTests.m:1231 |
| test837 | `test837_isDispatchable_opTagMismatch` | TEST837: is_dispatchable — op tag mismatch rejects | Tests/CapDAGTests/CSCapUrnTests.m:1242 |
| test838 | `test838_isDispatchable_requestWildcardOutput` | TEST838: is_dispatchable — request with wildcard output accepts any provider output | Tests/CapDAGTests/CSCapUrnTests.m:1252 |
| test839 | `test839_peerResponseDeliversLogsBeforeStreamStart` | TEST839: LOG frames arriving BEFORE StreamStart are delivered immediately | Tests/BifaciTests/StreamingAPITests.swift:662 |
| test840 | `test840_peerResponseCollectBytesDiscardsLogs` | TEST840: PeerResponse.collectBytes() discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:733 |
| test841 | `test841_peerResponseCollectValueDiscardsLogs` | TEST841: PeerResponse.collectValue() discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:763 |
| test842 | `test842_runWithKeepaliveReturnsResult` | TEST842: runWithKeepalive returns closure result (fast operation, no keepalive frames) | Tests/BifaciTests/StreamingAPITests.swift:794 |
| test843 | `test843_runWithKeepaliveReturnsResultType` | TEST843: runWithKeepalive returns Ok/Err from closure | Tests/BifaciTests/StreamingAPITests.swift:817 |
| test844 | `test844_runWithKeepalivePropagatesError` | TEST844: runWithKeepalive propagates error from closure | Tests/BifaciTests/StreamingAPITests.swift:835 |
| test845 | `test845_progressSenderEmitsFrames` | TEST845: ProgressSender emits progress and log frames independently of OutputStream | Tests/BifaciTests/StreamingAPITests.swift:863 |
| test846 | `test846_progressFrameRoundtrip` | TEST846: Progress LOG frame encode/decode roundtrip preserves progress float | Tests/BifaciTests/FrameTests.swift:1715 |
| test847 | `test847_progressDoubleRoundtrip` | TEST847: Double roundtrip (encode→decode→modify→encode→decode) preserves progress float | Tests/BifaciTests/FrameTests.swift:1752 |
| test852 | `test852_lub_identical` | TEST852: LUB of identical URNs returns the same URN | Tests/CapDAGTests/CSMediaUrnTests.m:18 |
| test853 | `test853_lub_no_common_tags` | TEST853: LUB of URNs with no common tags returns media: (universal) | Tests/CapDAGTests/CSMediaUrnTests.m:27 |
| test854 | `test854_lub_partial_overlap` | TEST854: LUB keeps common tags, drops differing ones | Tests/CapDAGTests/CSMediaUrnTests.m:41 |
| test855 | `test855_lub_list_vs_scalar` | TEST855: LUB of list and non-list drops list tag | Tests/CapDAGTests/CSMediaUrnTests.m:55 |
| test856 | `test856_lub_empty` | TEST856: LUB of empty input returns universal type | Tests/CapDAGTests/CSMediaUrnTests.m:69 |
| test857 | `test857_lub_single` | TEST857: LUB of single input returns that input | Tests/CapDAGTests/CSMediaUrnTests.m:78 |
| test858 | `test858_lub_three_inputs` | TEST858: LUB with three+ inputs narrows correctly | Tests/CapDAGTests/CSMediaUrnTests.m:87 |
| test859 | `test859_lub_valued_tags` | TEST859: LUB with valued tags (non-marker) that differ | Tests/CapDAGTests/CSMediaUrnTests.m:103 |
| test860 | `test860_seqAssignerSameRidDifferentXidsIndependent` | TEST860: Same RID with different XIDs get independent seq counters | Tests/BifaciTests/FlowOrderingTests.swift:115 |
| test896 | `test896_fullPathEngineReqToCartridgeResponse` | TEST896: Full path: engine REQ → runtime → cartridge → response back through relay | Tests/BifaciTests/IntegrationTests.swift:635 |
| test897 | `test897_cartridgeErrorFlowsToEngine` | TEST897: Cartridge ERR frame flows back to engine through relay | Tests/BifaciTests/IntegrationTests.swift:702 |
| test898 | `test898_binaryIntegrityThroughRelay` | TEST898: Binary data integrity through full relay path | Tests/BifaciTests/IntegrationTests.swift:744 |
| test899 | `test899_streamingChunksThroughRelay` | TEST899: Streaming chunks flow through relay without accumulation | Tests/BifaciTests/IntegrationTests.swift:802 |
| test900 | `test900_twoCartridgesRoutedIndependently` | TEST900: Two cartridges routed independently by cap_urn | Tests/BifaciTests/IntegrationTests.swift:859 |
| test901 | `test901_reqForUnknownCapReturnsErr` | TEST901: REQ for unknown cap returns ERR (NoHandler) — not fatal, just per-request error | Tests/BifaciTests/RuntimeTests.swift:580 |
| test902 | `test902_computeChecksumEmpty` | TEST902: Verify FNV-1a checksum handles empty data | Tests/BifaciTests/FrameTests.swift:1660 |
| test903 | `test903_chunkWithChunkIndexAndChecksum` | TEST903: Verify CHUNK frame can store chunk_index and checksum fields | Tests/BifaciTests/FrameTests.swift:1667 |
| test904 | `test904_streamEndWithChunkCount` | TEST904: Verify STREAM_END frame can store chunk_count field | Tests/BifaciTests/FrameTests.swift:1680 |
| test907 | `test907_cborRejectsStreamEndWithoutChunkCount` | TEST907: CBOR decode REJECTS STREAM_END frame missing chunk_count field | Tests/BifaciTests/FrameTests.swift:1690 |
| test908 | `test908_map_progress_basic_mapping` | TEST908: map_progress basic mapping — identity, subdivision, clamping | Tests/CapDAGTests/CSProgressMapperTests.m:17 |
| test909 | `test909_map_progress_deterministic` | TEST909: map_progress is deterministic — identical inputs produce identical outputs | Tests/CapDAGTests/CSProgressMapperTests.m:34 |
| test910 | `test910_map_progress_monotonic` | TEST910: map_progress output is monotonic for monotonically increasing input | Tests/CapDAGTests/CSProgressMapperTests.m:44 |
| test911 | `test911_map_progress_bounded` | TEST911: map_progress output is bounded within [base, base+weight] | Tests/CapDAGTests/CSProgressMapperTests.m:56 |
| test912 | `test912_progress_mapper_reports_through_parent` | TEST912: ProgressMapper correctly maps through parent callback | Tests/CapDAGTests/CSProgressMapperTests.m:70 |
| test913 | `test913_progress_mapper_as_cap_progress_fn` | TEST913: ProgressMapper conversion to CapProgressFn preserves mapping | Tests/CapDAGTests/CSProgressMapperTests.m:89 |
| test914 | `test914_progress_mapper_sub_mapper` | TEST914: ProgressMapper sub_mapper chains correctly | Tests/CapDAGTests/CSProgressMapperTests.m:110 |
| test915 | `test915_per_group_subdivision_monotonic_bounded` | TEST915: Per-group subdivision is monotonic and bounded for N groups | Tests/CapDAGTests/CSProgressMapperTests.m:132 |
| test917 | `test917_high_frequency_progress_bounded` | TEST917: High-frequency progress updates stay bounded | Tests/CapDAGTests/CSProgressMapperTests.m:170 |
| test935 | `test935_parseSimpleTestcartridgeGraph` | TEST935: Parse simple DOT graph with test-edge1 | Tests/BifaciTests/OrchestratorTests.swift:82 |
| test936 | `test936_parseSingleEdgeDag` | TEST936: Parse single-edge DAG (test-edge1) | Tests/BifaciTests/OrchestratorTests.swift:100 |
| test937 | `test937_parseEdge1ToEdge2Chain` | TEST937: Parse two-edge chain (test-edge1 -> test-edge2) | Tests/BifaciTests/OrchestratorTests.swift:118 |
| test940 | `test940_parseFanInPattern` | TEST940: Parse fan-in pattern | Tests/BifaciTests/OrchestratorTests.swift:138 |
| test941 | `test941_rejectCycles` | TEST941: Validate that cycles are rejected | Tests/BifaciTests/OrchestratorTests.swift:163 |
| test942 | `test942_emptyGraph` | TEST942: Empty graph (no edges) | Tests/BifaciTests/OrchestratorTests.swift:188 |
| test943 | `test943_invalidCapUrn` | TEST943: Invalid cap URN in label | Tests/BifaciTests/OrchestratorTests.swift:206 |
| test944 | `test944_capNotFound` | TEST944: Cap not found in registry | Tests/BifaciTests/OrchestratorTests.swift:224 |
| test945 | `test945_fourMachine` | TEST945: 4-machine: edge1 -> edge2 -> edge7 -> edge8 | Tests/BifaciTests/OrchestratorTests.swift:250 |
| test946 | `test946_fiveMachine` | TEST946: 5-machine: edge1 -> edge2 -> edge7 -> edge8 -> edge9 | Tests/BifaciTests/OrchestratorTests.swift:274 |
| test947 | `test947_sixMachine` | TEST947: 6-machine: edge1 -> edge2 -> edge7 -> edge8 -> edge9 -> edge10 | Tests/BifaciTests/OrchestratorTests.swift:300 |
| test955 | `test955_splitMapArray` | TEST955: splitCborArray with nested maps | Tests/BifaciTests/CborSequenceTests.swift:250 |
| test956 | `test956_roundtripAssembleSplit` | TEST956: assemble then split roundtrip preserves data | Tests/BifaciTests/CborSequenceTests.swift:360 |
| test961 | `test961_assembleEmpty` | TEST961: assembleCborArray with empty list produces empty CBOR array | Tests/BifaciTests/CborSequenceTests.swift:377 |
| test962 | `test962_assembleInvalidItem` | TEST962: assembleCborArray rejects invalid CBOR item Mirrors Rust: valid item first, then garbage — exactly as Rust does Uses truncated CBOR: 0x5A = byte string with 4-byte length, but only 1 byte of content | Tests/BifaciTests/CborSequenceTests.swift:389 |
| test963 | `test963_splitBinaryItems` | TEST963: splitCborArray preserves CBOR byte strings (binary data) | Tests/BifaciTests/CborSequenceTests.swift:405 |
| test964 | `test964_splitSequenceBytes` | TEST964: splitCborSequence on concatenated Bytes values | Tests/BifaciTests/CborSequenceTests.swift:423 |
| test965 | `test965_splitSequenceText` | TEST965: splitCborSequence on concatenated Text values | Tests/BifaciTests/CborSequenceTests.swift:438 |
| test966 | `test966_splitSequenceMixed` | TEST966: splitCborSequence handles mixed types | Tests/BifaciTests/CborSequenceTests.swift:453 |
| test967 | `test967_splitSequenceSingle` | TEST967: splitCborSequence on single-item sequence | Tests/BifaciTests/CborSequenceTests.swift:472 |
| test968 | `test968_roundtripAssembleSplitSequence` | TEST968: assemble then split roundtrip preserves items (sequence) | Tests/BifaciTests/CborSequenceTests.swift:483 |
| test969 | `test969_roundtripSplitAssembleSequence` | TEST969: split then assemble roundtrip preserves bytes exactly (sequence) | Tests/BifaciTests/CborSequenceTests.swift:500 |
| test970 | `test970_splitSequenceEmpty` | TEST970: splitCborSequence rejects empty data | Tests/BifaciTests/CborSequenceTests.swift:514 |
| test971 | `test971_splitSequenceTruncated` | TEST971: splitCborSequence rejects truncated CBOR | Tests/BifaciTests/CborSequenceTests.swift:528 |
| test972 | `test972_assembleSequenceInvalidItem` | TEST972: assembleCborSequence rejects invalid item Mirrors Rust: valid item first, then garbage — exactly as Rust does Uses truncated CBOR: 0x5A = byte string with 4-byte length, but only 1 byte of content | Tests/BifaciTests/CborSequenceTests.swift:541 |
| test973 | `test973_assembleSequenceEmpty` | TEST973: assembleCborSequence with empty items produces empty bytes | Tests/BifaciTests/CborSequenceTests.swift:552 |
| test974 | `test974_sequenceIsNotArray` | TEST974: CBOR sequence is NOT a CBOR array — splitCborArray rejects it | Tests/BifaciTests/CborSequenceTests.swift:558 |
| test975 | `test975_singleValueSequence` | TEST975: single CBOR value is both valid sequence and valid value | Tests/BifaciTests/CborSequenceTests.swift:575 |
| test976 | `test976_cap_graph_find_best_path` | TEST976: CapGraph find_best_path (highest specificity over shortest) | Tests/CapDAGTests/CSCapMatrixTests.m:392 |
| test1000 | `test1000_single_existing_file` |  | Tests/CapDAGTests/CSInputResolverTests.m:489 |
| test1001 | `test1001_single_nonexistent_file` |  | Tests/CapDAGTests/CSInputResolverTests.m:502 |
| test1002 | `test1002_empty_directory` |  | Tests/CapDAGTests/CSInputResolverTests.m:514 |
| test1003 | `test1003_directory_with_files` |  | Tests/CapDAGTests/CSInputResolverTests.m:526 |
| test1010 | `test1010_duplicate_paths` |  | Tests/CapDAGTests/CSInputResolverTests.m:541 |
| test1013 | `test1013_empty_input_array` |  | Tests/CapDAGTests/CSInputResolverTests.m:553 |
| test1020 | `test1020_macos_ds_store` |  | Tests/CapDAGTests/CSInputResolverTests.m:51 |
| test1021 | `test1021_windows_thumbs_db` |  | Tests/CapDAGTests/CSInputResolverTests.m:57 |
| test1022 | `test1022_macos_resource_fork` |  | Tests/CapDAGTests/CSInputResolverTests.m:63 |
| test1023 | `test1023_office_lock_file` |  | Tests/CapDAGTests/CSInputResolverTests.m:69 |
| test1024 | `test1024_git_directory` |  | Tests/CapDAGTests/CSInputResolverTests.m:75 |
| test1025 | `test1025_macosx_archive` |  | Tests/CapDAGTests/CSInputResolverTests.m:81 |
| test1026 | `test1026_temp_files` |  | Tests/CapDAGTests/CSInputResolverTests.m:87 |
| test1027 | `test1027_localized` |  | Tests/CapDAGTests/CSInputResolverTests.m:93 |
| test1028 | `test1028_desktop_ini` |  | Tests/CapDAGTests/CSInputResolverTests.m:98 |
| test1029 | `test1029_content_files_not_excluded` |  | Tests/CapDAGTests/CSInputResolverTests.m:103 |
| test1030 | `test1030_json_empty_object` |  | Tests/CapDAGTests/CSInputResolverTests.m:114 |
| test1031 | `test1031_json_simple_object` |  | Tests/CapDAGTests/CSInputResolverTests.m:127 |
| test1033 | `test1033_json_empty_array` |  | Tests/CapDAGTests/CSInputResolverTests.m:140 |
| test1034 | `test1034_json_array_of_primitives` |  | Tests/CapDAGTests/CSInputResolverTests.m:153 |
| test1035 | `test1035_json_array_of_strings` |  | Tests/CapDAGTests/CSInputResolverTests.m:166 |
| test1036 | `test1036_json_array_of_objects` |  | Tests/CapDAGTests/CSInputResolverTests.m:179 |
| test1038 | `test1038_json_string_primitive` |  | Tests/CapDAGTests/CSInputResolverTests.m:192 |
| test1039 | `test1039_json_number_primitive` |  | Tests/CapDAGTests/CSInputResolverTests.m:205 |
| test1040 | `test1040_json_boolean_true` |  | Tests/CapDAGTests/CSInputResolverTests.m:218 |
| test1042 | `test1042_json_null` |  | Tests/CapDAGTests/CSInputResolverTests.m:231 |
| test1045 | `test1045_ndjson_objects_only` |  | Tests/CapDAGTests/CSInputResolverTests.m:246 |
| test1046 | `test1046_ndjson_single_object` |  | Tests/CapDAGTests/CSInputResolverTests.m:259 |
| test1047 | `test1047_ndjson_primitives_only` |  | Tests/CapDAGTests/CSInputResolverTests.m:272 |
| test1055 | `test1055_csv_multi_column` |  | Tests/CapDAGTests/CSInputResolverTests.m:287 |
| test1056 | `test1056_csv_single_column` |  | Tests/CapDAGTests/CSInputResolverTests.m:300 |
| test1065 | `test1065_yaml_simple_mapping` |  | Tests/CapDAGTests/CSInputResolverTests.m:315 |
| test1067 | `test1067_yaml_sequence_of_scalars` |  | Tests/CapDAGTests/CSInputResolverTests.m:328 |
| test1068 | `test1068_yaml_sequence_of_mappings` |  | Tests/CapDAGTests/CSInputResolverTests.m:341 |
| test1080 | `test1080_pdf_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:356 |
| test1081 | `test1081_png_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:370 |
| test1082 | `test1082_mp3_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:383 |
| test1083 | `test1083_mp4_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:396 |
| test1084 | `test1084_rust_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:409 |
| test1085 | `test1085_python_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:422 |
| test1086 | `test1086_markdown_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:435 |
| test1087 | `test1087_toml_always_record` |  | Tests/CapDAGTests/CSInputResolverTests.m:448 |
| test1088 | `test1088_log_file_is_list` |  | Tests/CapDAGTests/CSInputResolverTests.m:461 |
| test1089 | `test1089_unknown_extension` |  | Tests/CapDAGTests/CSInputResolverTests.m:474 |
| test1090 | `test1090_single_file_scalar` |  | Tests/CapDAGTests/CSInputResolverTests.m:566 |
| test1091 | `test1091_single_file_list_content` |  | Tests/CapDAGTests/CSInputResolverTests.m:578 |
| test1092 | `test1092_two_files` |  | Tests/CapDAGTests/CSInputResolverTests.m:592 |
| test1093 | `test1093_dir_single_file` |  | Tests/CapDAGTests/CSInputResolverTests.m:607 |
| test1094 | `test1094_dir_multiple_files` |  | Tests/CapDAGTests/CSInputResolverTests.m:621 |
| test1098 | `test1098_common_media` |  | Tests/CapDAGTests/CSInputResolverTests.m:637 |
| test1099 | `test1099_heterogeneous` |  | Tests/CapDAGTests/CSInputResolverTests.m:652 |
| | | | |
| unnumbered | `test198b_limitsNegotiation` | TEST198 (continued): Limits negotiation picks minimum of both sides | Tests/BifaciTests/FrameTests.swift:308 |
| unnumbered | `test205b_allFrameTypesRoundtrip` | Covers all frame types in a single loop for comprehensive roundtrip verification | Tests/BifaciTests/FrameTests.swift:903 |
| unnumbered | `test389b_streamStartIsSequenceRoundtrip` | TEST389b: STREAM_START with isSequence roundtrips correctly | Tests/BifaciTests/FrameTests.swift:1100 |
| unnumbered | `test542b_outputStreamStartThenCloseEmpty` | TEST542b: OutputStream start + close sends STREAM_START + STREAM_END (empty stream) | Tests/BifaciTests/StreamingAPITests.swift:407 |
| unnumbered | `test542c_outputStreamWriteWithoutStartThrows` | TEST542c: OutputStream write without start() throws | Tests/BifaciTests/StreamingAPITests.swift:437 |
| unnumbered | `test542d_outputStreamDoubleStartThrows` | TEST542d: OutputStream start() twice throws | Tests/BifaciTests/StreamingAPITests.swift:453 |
| unnumbered | `test542e_outputStreamModeConflictThrows` | TEST542e: OutputStream mode conflict throws (start write, call emitListItem) | Tests/BifaciTests/StreamingAPITests.swift:470 |
| unnumbered | `test754ExtractPrefixNonexistent` | TEST754: extractPrefixTo with nonexistent node returns error | Tests/CapDAGTests/CSPlanDecompositionTests.m:135 |
| unnumbered | `test755ExtractForeachBody` | TEST755: extractForeachBody extracts body with synthetic I/O | Tests/CapDAGTests/CSPlanDecompositionTests.m:144 |
| unnumbered | `test756ExtractForeachBodyUnclosed` | TEST756: extractForeachBody for unclosed ForEach (single body cap) | Tests/CapDAGTests/CSPlanDecompositionTests.m:176 |
| unnumbered | `test757ExtractForeachBodyWrongType` | TEST757: extractForeachBody fails for non-ForEach node | Tests/CapDAGTests/CSPlanDecompositionTests.m:193 |
| unnumbered | `test758ExtractSuffixFrom` | TEST758: extractSuffixFrom extracts collect → cap_post → output | Tests/CapDAGTests/CSPlanDecompositionTests.m:204 |
| unnumbered | `test759ExtractSuffixNonexistent` | TEST759: extractSuffixFrom fails for nonexistent node | Tests/CapDAGTests/CSPlanDecompositionTests.m:225 |
| unnumbered | `test760DecompositionCoversAllCaps` | TEST760: Full decomposition covers all cap nodes | Tests/CapDAGTests/CSPlanDecompositionTests.m:234 |
| unnumbered | `test761PrefixIsDag` | TEST761: Prefix is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:273 |
| unnumbered | `test762BodyIsDag` | TEST762: Body is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:282 |
| unnumbered | `test763SuffixIsDag` | TEST763: Suffix is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:291 |
| unnumbered | `test764PrefixToInputSlot` | TEST764: extractPrefixTo with InputSlot as target (trivial prefix) | Tests/CapDAGTests/CSPlanDecompositionTests.m:300 |
| unnumbered | `test772FindPathsMultiStep` | TEST772: Multi-step path through intermediate node | Tests/CapDAGTests/CSLiveCapGraphTests.m:149 |
| unnumbered | `test773FindPathsEmptyWhenNoPath` | TEST773: Empty when target unreachable | Tests/CapDAGTests/CSLiveCapGraphTests.m:171 |
| unnumbered | `test774GetReachableTargetsAll` | TEST774: BFS finds multiple direct targets | Tests/CapDAGTests/CSLiveCapGraphTests.m:187 |
| unnumbered | `test777TypeMismatchPdfPng` | TEST777: PDF cap does not match PNG input | Tests/CapDAGTests/CSLiveCapGraphTests.m:210 |
| unnumbered | `test778TypeMismatchPngPdf` | TEST778: PNG cap does not match PDF input | Tests/CapDAGTests/CSLiveCapGraphTests.m:225 |
| unnumbered | `test779ReachableTargetsTypeMatching` | TEST779: BFS respects type matching | Tests/CapDAGTests/CSLiveCapGraphTests.m:240 |
| unnumbered | `test781FindPathsTypeChain` | TEST781: Multi-step type chain enforcement | Tests/CapDAGTests/CSLiveCapGraphTests.m:263 |
| unnumbered | `test787SortingShorterFirst` | TEST787: Sorting prefers shorter paths | Tests/CapDAGTests/CSLiveCapGraphTests.m:286 |
| unnumbered | `test788ForEachWithSequenceInput` | TEST788: ForEach synthesized when input is a sequence | Tests/CapDAGTests/CSLiveCapGraphTests.m:308 |
| unnumbered | `test790IdentityUrnSpecific` | TEST790: Identity URN is specific, not equivalent to everything | Tests/CapDAGTests/CSLiveCapGraphTests.m:349 |
| unnumbered | `test934FindFirstForeach` | MARK: - TEST934: findFirstForeach detects ForEach | Tests/CapDAGTests/CSPlanDecompositionTests.m:84 |
| unnumbered | `test935FindFirstForeachLinear` | TEST935: findFirstForeach returns nil for linear plans | Tests/CapDAGTests/CSPlanDecompositionTests.m:91 |
| unnumbered | `test936HasForeach` | TEST936: hasForeach | Tests/CapDAGTests/CSPlanDecompositionTests.m:100 |
| unnumbered | `test937ExtractPrefixTo` | TEST937: extractPrefixTo extracts input_slot → cap_0 as standalone plan | Tests/CapDAGTests/CSPlanDecompositionTests.m:112 |
| unnumbered | `testAddCapAndBasicTraversal` | MARK: - Basic Tests (unnumbered, match Rust unnumbered tests) | Tests/CapDAGTests/CSLiveCapGraphTests.m:32 |
| unnumbered | `testAnyRecursive` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:342 |
| unnumbered | `testAnyRecursive` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:342 |
| unnumbered | `testAnyRecursive` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:342 |
| unnumbered | `testArgumentCreationWithNewAPI` |  | Tests/CapDAGTests/CSCapTests.m:729 |
| unnumbered | `testArrays` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:157 |
| unnumbered | `testArrays` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:157 |
| unnumbered | `testArrays` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:157 |
| unnumbered | `testBadgeClearingAfterCompletion` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:432 |
| unnumbered | `testBadgeStateTransitions` | / Test badge state transitions | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:448 |
| unnumbered | `testBadgeStatusPolling_EmptyState` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:266 |
| unnumbered | `testBadgeStatusPolling_WithActiveTransform` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:293 |
| unnumbered | `testBestCapSetSelection` |  | Tests/CapDAGTests/CSCapMatrixTests.m:101 |
| unnumbered | `testBools` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:62 |
| unnumbered | `testBools` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:62 |
| unnumbered | `testBools` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:62 |
| unnumbered | `testBraces` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:68 |
| unnumbered | `testBraces` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:68 |
| unnumbered | `testBraces` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:68 |
| unnumbered | `testBuilderBasicConstruction` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:16 |
| unnumbered | `testBuilderComplex` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:173 |
| unnumbered | `testBuilderCustomTags` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:70 |
| unnumbered | `testBuilderDirectionAccess` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:53 |
| unnumbered | `testBuilderDirectionMismatchNoMatch` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:286 |
| unnumbered | `testBuilderEmptyBuildFailsWithMissingInSpec` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:131 |
| unnumbered | `testBuilderFluentAPI` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:32 |
| unnumbered | `testBuilderMatchingWithBuiltCap` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:240 |
| unnumbered | `testBuilderMinimalValid` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:158 |
| unnumbered | `testBuilderMissingInSpecFails` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:105 |
| unnumbered | `testBuilderMissingOutSpecFails` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:118 |
| unnumbered | `testBuilderStaticFactory` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:231 |
| unnumbered | `testBuilderTagIgnoresInOut` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:140 |
| unnumbered | `testBuilderTagOverrides` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:88 |
| unnumbered | `testBuilderWildcards` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:207 |
| unnumbered | `testBuiltinSpecIdsResolve` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:541 |
| unnumbered | `testCanHandle` |  | Tests/CapDAGTests/CSCapMatrixTests.m:156 |
| unnumbered | `testCanonicalArgumentsDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:215 |
| unnumbered | `testCanonicalDictionaryDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:168 |
| unnumbered | `testCanonicalOutputDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:239 |
| unnumbered | `testCanonicalValidationDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:255 |
| unnumbered | `testCapAndForEachAreNotStandaloneCollect` |  | Tests/CapDAGTests/CSPlanDecompositionTests.m:75 |
| unnumbered | `testCapBlockCanMethod` |  | Tests/CapDAGTests/CSCapBlockTests.m:244 |
| unnumbered | `testCapBlockFallbackScenario` |  | Tests/CapDAGTests/CSCapBlockTests.m:192 |
| unnumbered | `testCapBlockMoreSpecificWins` |  | Tests/CapDAGTests/CSCapBlockTests.m:65 |
| unnumbered | `testCapBlockNoMatch` |  | Tests/CapDAGTests/CSCapBlockTests.m:178 |
| unnumbered | `testCapBlockPollsAll` |  | Tests/CapDAGTests/CSCapBlockTests.m:138 |
| unnumbered | `testCapBlockRegistryManagement` |  | Tests/CapDAGTests/CSCapBlockTests.m:269 |
| unnumbered | `testCapBlockTieGoesToFirst` |  | Tests/CapDAGTests/CSCapBlockTests.m:106 |
| unnumbered | `testCapCreation` |  | Tests/CapDAGTests/CSCapTests.m:22 |
| unnumbered | `testCapDocumentationOmittedWhenNil` | When documentation is nil, toDictionary must omit the field entirely. This matches the Rust serializer's skip-when-None semantics and the JS toJSON behaviour. A regression where nil is emitted as `documentation: NSNull` (or simply not omitted) would break the symmetric round-trip with Rust. | Tests/CapDAGTests/CSCapTests.m:827 |
| unnumbered | `testCapDocumentationRoundTrip` | Mirrors TEST920 in capdag/src/cap/definition.rs and the JS testJS_capDocumentationRoundTrip test. The body is non-trivial — multi-line, embedded backticks and double quotes, Unicode dingbat (\u2605) — so any escaping mismatch between dictionary serialization here and the Rust / JS counterparts surfaces as a failed round-trip. | Tests/CapDAGTests/CSCapTests.m:788 |
| unnumbered | `testCapGraphBasicConstruction` |  | Tests/CapDAGTests/CSCapGraphTests.m:58 |
| unnumbered | `testCapGraphCanConvert` |  | Tests/CapDAGTests/CSCapGraphTests.m:118 |
| unnumbered | `testCapGraphFindAllPaths` |  | Tests/CapDAGTests/CSCapGraphTests.m:187 |
| unnumbered | `testCapGraphFindPath` |  | Tests/CapDAGTests/CSCapGraphTests.m:149 |
| unnumbered | `testCapGraphGetDirectEdges` |  | Tests/CapDAGTests/CSCapGraphTests.m:216 |
| unnumbered | `testCapGraphOutgoingIncoming` |  | Tests/CapDAGTests/CSCapGraphTests.m:89 |
| unnumbered | `testCapGraphStats` |  | Tests/CapDAGTests/CSCapGraphTests.m:258 |
| unnumbered | `testCapGraphWithCapBlock` |  | Tests/CapDAGTests/CSCapGraphTests.m:290 |
| unnumbered | `testCapManifestCompatibility` |  | Tests/CapDAGTests/CSCapTests.m:682 |
| unnumbered | `testCapManifestCreation` | MARK: - Cap Manifest Tests | Tests/CapDAGTests/CSCapTests.m:426 |
| unnumbered | `testCapManifestDictionaryDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:509 |
| unnumbered | `testCapManifestEmptyCaps` |  | Tests/CapDAGTests/CSCapTests.m:611 |
| unnumbered | `testCapManifestOptionalAuthorField` |  | Tests/CapDAGTests/CSCapTests.m:635 |
| unnumbered | `testCapManifestRequiredFields` |  | Tests/CapDAGTests/CSCapTests.m:555 |
| unnumbered | `testCapManifestWithAuthor` |  | Tests/CapDAGTests/CSCapTests.m:455 |
| unnumbered | `testCapManifestWithMultipleCaps` |  | Tests/CapDAGTests/CSCapTests.m:568 |
| unnumbered | `testCapManifestWithPageUrl` |  | Tests/CapDAGTests/CSCapTests.m:481 |
| unnumbered | `testCapMatching` |  | Tests/CapDAGTests/CSCapTests.m:113 |
| unnumbered | `testCapStdinSerialization` |  | Tests/CapDAGTests/CSCapTests.m:138 |
| unnumbered | `testCapStdinType` |  | Tests/CapDAGTests/CSCapTests.m:69 |
| unnumbered | `testCapWithDescription` |  | Tests/CapDAGTests/CSCapTests.m:47 |
| unnumbered | `testClear` |  | Tests/CapDAGTests/CSCapMatrixTests.m:475 |
| unnumbered | `testClear570` | TEST570: clear | Tests/CapDAGTests/CSCapMatrixTests.m:253 |
| unnumbered | `testCoding` | Obj-C specific: NSCoding support | Tests/CapDAGTests/CSCapUrnTests.m:487 |
| unnumbered | `testCompleteCapDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:275 |
| unnumbered | `testCompleteFinderSyncFlow` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:480 |
| unnumbered | `testComplexNestedSchema` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:404 |
| unnumbered | `testContextMenuPopulation_MultipleFiles` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:147 |
| unnumbered | `testContextMenuPopulation_NonExistentFile` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:244 |
| unnumbered | `testContextMenuPopulation_SinglePDF` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:101 |
| unnumbered | `testContextMenuPopulation_Timeout` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:175 |
| unnumbered | `testContextMenuPopulation_UnsupportedFileType` |  | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:214 |
| unnumbered | `testCopying` | Obj-C specific: NSCopying support | Tests/CapDAGTests/CSCapUrnTests.m:509 |
| unnumbered | `testDataSourceWithBinaryContent` |  | Tests/CapDAGTests/CSStdinSourceTests.m:61 |
| unnumbered | `testDataSourceWithEmptyData` |  | Tests/CapDAGTests/CSStdinSourceTests.m:51 |
| unnumbered | `testDecodeArrays` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:64 |
| unnumbered | `testDecodeArrays` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:92 |
| unnumbered | `testDecodeArrays` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:64 |
| unnumbered | `testDecodeArrays` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:92 |
| unnumbered | `testDecodeArrays` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:64 |
| unnumbered | `testDecodeArrays` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:92 |
| unnumbered | `testDecodeBools` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:10 |
| unnumbered | `testDecodeBools` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:10 |
| unnumbered | `testDecodeBools` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:10 |
| unnumbered | `testDecodeByteStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:29 |
| unnumbered | `testDecodeByteStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:85 |
| unnumbered | `testDecodeByteStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:29 |
| unnumbered | `testDecodeByteStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:85 |
| unnumbered | `testDecodeByteStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:29 |
| unnumbered | `testDecodeByteStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:85 |
| unnumbered | `testDecodeData` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:41 |
| unnumbered | `testDecodeData` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:41 |
| unnumbered | `testDecodeData` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:41 |
| unnumbered | `testDecodeDates` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:106 |
| unnumbered | `testDecodeDates` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:120 |
| unnumbered | `testDecodeDates` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:106 |
| unnumbered | `testDecodeDates` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:120 |
| unnumbered | `testDecodeDates` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:106 |
| unnumbered | `testDecodeDates` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:120 |
| unnumbered | `testDecodeFailsForExtremelyDeepStructures` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:172 |
| unnumbered | `testDecodeFailsForExtremelyDeepStructures` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:172 |
| unnumbered | `testDecodeFailsForExtremelyDeepStructures` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:172 |
| unnumbered | `testDecodeFailsForSillyMaximumDepths` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:183 |
| unnumbered | `testDecodeFailsForSillyMaximumDepths` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:183 |
| unnumbered | `testDecodeFailsForSillyMaximumDepths` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:183 |
| unnumbered | `testDecodeFloats` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:98 |
| unnumbered | `testDecodeFloats` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:98 |
| unnumbered | `testDecodeFloats` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:98 |
| unnumbered | `testDecodeFromIssue78` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:141 |
| unnumbered | `testDecodeFromIssue78` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:141 |
| unnumbered | `testDecodeFromIssue78` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:141 |
| unnumbered | `testDecodeInts` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:17 |
| unnumbered | `testDecodeInts` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:17 |
| unnumbered | `testDecodeInts` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:17 |
| unnumbered | `testDecodeMapFromIssue29` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:124 |
| unnumbered | `testDecodeMapFromIssue29` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:124 |
| unnumbered | `testDecodeMapFromIssue29` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:124 |
| unnumbered | `testDecodeMaps` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:73 |
| unnumbered | `testDecodeMaps` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:107 |
| unnumbered | `testDecodeMaps` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:73 |
| unnumbered | `testDecodeMaps` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:107 |
| unnumbered | `testDecodeMaps` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:73 |
| unnumbered | `testDecodeMaps` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:107 |
| unnumbered | `testDecodeNegativeInts` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:51 |
| unnumbered | `testDecodeNegativeInts` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:51 |
| unnumbered | `testDecodeNegativeInts` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:51 |
| unnumbered | `testDecodeNull` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:5 |
| unnumbered | `testDecodeNull` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:5 |
| unnumbered | `testDecodeNull` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:5 |
| unnumbered | `testDecodeNumbers` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:5 |
| unnumbered | `testDecodeNumbers` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:5 |
| unnumbered | `testDecodeNumbers` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:5 |
| unnumbered | `testDecodeOfStructContainingNestedIndefiniteMapsAndArrays` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:159 |
| unnumbered | `testDecodeOfStructContainingNestedIndefiniteMapsAndArrays` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:159 |
| unnumbered | `testDecodeOfStructContainingNestedIndefiniteMapsAndArrays` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:159 |
| unnumbered | `testDecodePerformance` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:113 |
| unnumbered | `testDecodePerformance` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:113 |
| unnumbered | `testDecodePerformance` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:113 |
| unnumbered | `testDecodeSimple` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:88 |
| unnumbered | `testDecodeSimple` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:88 |
| unnumbered | `testDecodeSimple` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:88 |
| unnumbered | `testDecodeStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:71 |
| unnumbered | `testDecodeStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:71 |
| unnumbered | `testDecodeStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:71 |
| unnumbered | `testDecodeSucceedsForAllowedDeepStructures` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:190 |
| unnumbered | `testDecodeSucceedsForAllowedDeepStructures` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:190 |
| unnumbered | `testDecodeSucceedsForAllowedDeepStructures` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:190 |
| unnumbered | `testDecodeTagged` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:81 |
| unnumbered | `testDecodeTagged` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:81 |
| unnumbered | `testDecodeTagged` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:81 |
| unnumbered | `testDecodeUtf8Strings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:53 |
| unnumbered | `testDecodeUtf8Strings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:53 |
| unnumbered | `testDecodeUtf8Strings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:53 |
| unnumbered | `testDeterministicOrdering` |  | Tests/CapDAGTests/CSLiveCapGraphTests.m:100 |
| unnumbered | `testDirectAccess` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:88 |
| unnumbered | `testDirectAccess` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:88 |
| unnumbered | `testDirectAccess` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:88 |
| unnumbered | `testDirectionSemanticMatching` | TEST051: Semantic direction matching - generic provider matches specific request | Tests/CapDAGTests/CSCapUrnTests.m:915 |
| unnumbered | `testDirectionSemanticSpecificity` | TEST052: Semantic direction specificity - more media URN tags = higher specificity | Tests/CapDAGTests/CSCapUrnTests.m:962 |
| unnumbered | `testDirectionWildcardMatches` | TEST003: Direction wildcard matching | Tests/CapDAGTests/CSCapUrnTests.m:218 |
| unnumbered | `testDotParserCapUrnLabel` | TEST: Parse cap URN label with escaped quotes | Tests/BifaciTests/OrchestratorTests.swift:413 |
| unnumbered | `testDotParserComments` | TEST: Parse graph with comments | Tests/BifaciTests/OrchestratorTests.swift:397 |
| unnumbered | `testDotParserEdgeWithLabel` | TEST: Parse edge with label attribute | Tests/BifaciTests/OrchestratorTests.swift:350 |
| unnumbered | `testDotParserNodeWithAttributes` | TEST: Parse node with attributes | Tests/BifaciTests/OrchestratorTests.swift:364 |
| unnumbered | `testDotParserQuotedIdentifiers` | TEST: Parse quoted identifiers | Tests/BifaciTests/OrchestratorTests.swift:381 |
| unnumbered | `testDotParserSimpleDigraph` | TEST: Parse simple digraph | Tests/BifaciTests/OrchestratorTests.swift:330 |
| unnumbered | `testDoubleGlobstarBashV3` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:142 |
| unnumbered | `testDoubleGlobstarBashV3` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:142 |
| unnumbered | `testDoubleGlobstarBashV3` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:142 |
| unnumbered | `testDoubleGlobstarBashV4` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:194 |
| unnumbered | `testDoubleGlobstarBashV4` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:194 |
| unnumbered | `testDoubleGlobstarBashV4` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:194 |
| unnumbered | `testDoubleGlobstarGradle` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:259 |
| unnumbered | `testDoubleGlobstarGradle` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:259 |
| unnumbered | `testDoubleGlobstarGradle` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:259 |
| unnumbered | `testEncodeAny` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:331 |
| unnumbered | `testEncodeAny` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:331 |
| unnumbered | `testEncodeAny` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:331 |
| unnumbered | `testEncodeArrays` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:72 |
| unnumbered | `testEncodeArrays` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:89 |
| unnumbered | `testEncodeArrays` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:72 |
| unnumbered | `testEncodeArrays` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:89 |
| unnumbered | `testEncodeArrays` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:72 |
| unnumbered | `testEncodeArrays` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:89 |
| unnumbered | `testEncodeBools` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:10 |
| unnumbered | `testEncodeBools` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:10 |
| unnumbered | `testEncodeBools` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:10 |
| unnumbered | `testEncodeByteStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:27 |
| unnumbered | `testEncodeByteStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:84 |
| unnumbered | `testEncodeByteStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:27 |
| unnumbered | `testEncodeByteStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:84 |
| unnumbered | `testEncodeByteStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:27 |
| unnumbered | `testEncodeByteStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:84 |
| unnumbered | `testEncodeData` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:41 |
| unnumbered | `testEncodeData` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:41 |
| unnumbered | `testEncodeData` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:41 |
| unnumbered | `testEncodeDates` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:277 |
| unnumbered | `testEncodeDates` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:277 |
| unnumbered | `testEncodeDates` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:277 |
| unnumbered | `testEncodeFloats` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:199 |
| unnumbered | `testEncodeFloats` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:199 |
| unnumbered | `testEncodeFloats` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:199 |
| unnumbered | `testEncodeIndefiniteArrays` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:229 |
| unnumbered | `testEncodeIndefiniteArrays` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:229 |
| unnumbered | `testEncodeIndefiniteArrays` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:229 |
| unnumbered | `testEncodeIndefiniteByteStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:265 |
| unnumbered | `testEncodeIndefiniteByteStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:265 |
| unnumbered | `testEncodeIndefiniteByteStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:265 |
| unnumbered | `testEncodeIndefiniteMaps` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:247 |
| unnumbered | `testEncodeIndefiniteMaps` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:247 |
| unnumbered | `testEncodeIndefiniteMaps` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:247 |
| unnumbered | `testEncodeIndefiniteStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:257 |
| unnumbered | `testEncodeIndefiniteStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:257 |
| unnumbered | `testEncodeIndefiniteStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:257 |
| unnumbered | `testEncodeInts` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:10 |
| unnumbered | `testEncodeInts` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:17 |
| unnumbered | `testEncodeInts` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:10 |
| unnumbered | `testEncodeInts` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:17 |
| unnumbered | `testEncodeInts` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:10 |
| unnumbered | `testEncodeInts` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:17 |
| unnumbered | `testEncodeMaps` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:88 |
| unnumbered | `testEncodeMaps` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:100 |
| unnumbered | `testEncodeMaps` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:88 |
| unnumbered | `testEncodeMaps` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:100 |
| unnumbered | `testEncodeMaps` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:88 |
| unnumbered | `testEncodeMaps` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:100 |
| unnumbered | `testEncodeNegativeInts` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:51 |
| unnumbered | `testEncodeNegativeInts` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:51 |
| unnumbered | `testEncodeNegativeInts` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:51 |
| unnumbered | `testEncodeNull` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:5 |
| unnumbered | `testEncodeNull` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:5 |
| unnumbered | `testEncodeNull` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:5 |
| unnumbered | `testEncodeSimple` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:188 |
| unnumbered | `testEncodeSimple` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:188 |
| unnumbered | `testEncodeSimple` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:188 |
| unnumbered | `testEncodeSimpleStructs` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:120 |
| unnumbered | `testEncodeSimpleStructs` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:120 |
| unnumbered | `testEncodeSimpleStructs` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:120 |
| unnumbered | `testEncodeSortedMaps` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:117 |
| unnumbered | `testEncodeSortedMaps` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:117 |
| unnumbered | `testEncodeSortedMaps` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:117 |
| unnumbered | `testEncodeStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:71 |
| unnumbered | `testEncodeStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:71 |
| unnumbered | `testEncodeStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:71 |
| unnumbered | `testEncodeTagged` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:181 |
| unnumbered | `testEncodeTagged` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:181 |
| unnumbered | `testEncodeTagged` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:181 |
| unnumbered | `testEncodeUtf8Strings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:55 |
| unnumbered | `testEncodeUtf8Strings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:55 |
| unnumbered | `testEncodeUtf8Strings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:55 |
| unnumbered | `testEquality` | TEST016: Test equality and hashing | Tests/CapDAGTests/CSCapUrnTests.m:473 |
| unnumbered | `testExactVsConformanceMatching` |  | Tests/CapDAGTests/CSLiveCapGraphTests.m:50 |
| unnumbered | `testExtensionsEmptyWhenNotSet` |  | Tests/CapDAGTests/CSMediaSpecTests.m:133 |
| unnumbered | `testExtensionsPropagationFromObjectDef` | Extensions field tests | Tests/CapDAGTests/CSMediaSpecTests.m:110 |
| unnumbered | `testExtensionsWithMetadataAndValidation` |  | Tests/CapDAGTests/CSMediaSpecTests.m:152 |
| unnumbered | `testFileReferenceWithAllFields` |  | Tests/CapDAGTests/CSStdinSourceTests.m:74 |
| unnumbered | `testFoundationHeavyType` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:377 |
| unnumbered | `testFoundationHeavyType` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:377 |
| unnumbered | `testFoundationHeavyType` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:377 |
| unnumbered | `testFullCapValidationWithMediaSpecs` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:679 |
| unnumbered | `testGetCapDefinitionReal` |  | Tests/CapDAGTests/CSCapRegistryTests.m:115 |
| unnumbered | `testGlobstarBashV3NoSlash` | MARK: - Globstar - Bash v3 | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:121 |
| unnumbered | `testGlobstarBashV3NoSlash` | MARK: - Globstar - Bash v3 | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:121 |
| unnumbered | `testGlobstarBashV3NoSlash` | MARK: - Globstar - Bash v3 | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:121 |
| unnumbered | `testGlobstarBashV3WithSlash` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:128 |
| unnumbered | `testGlobstarBashV3WithSlash` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:128 |
| unnumbered | `testGlobstarBashV3WithSlash` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:128 |
| unnumbered | `testGlobstarBashV3WithSlashAndWildcard` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:135 |
| unnumbered | `testGlobstarBashV3WithSlashAndWildcard` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:135 |
| unnumbered | `testGlobstarBashV3WithSlashAndWildcard` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:135 |
| unnumbered | `testGlobstarBashV4NoSlash` | MARK: - Globstar - Bash v4 | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:150 |
| unnumbered | `testGlobstarBashV4NoSlash` | MARK: - Globstar - Bash v4 | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:150 |
| unnumbered | `testGlobstarBashV4NoSlash` | MARK: - Globstar - Bash v4 | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:150 |
| unnumbered | `testGlobstarBashV4WithSlash` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:166 |
| unnumbered | `testGlobstarBashV4WithSlash` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:166 |
| unnumbered | `testGlobstarBashV4WithSlash` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:166 |
| unnumbered | `testGlobstarBashV4WithSlashAndWildcard` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:178 |
| unnumbered | `testGlobstarBashV4WithSlashAndWildcard` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:178 |
| unnumbered | `testGlobstarBashV4WithSlashAndWildcard` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:178 |
| unnumbered | `testGlobstarGradleNoSlash` | MARK: - Globstar - Gradle | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:205 |
| unnumbered | `testGlobstarGradleNoSlash` | MARK: - Globstar - Gradle | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:205 |
| unnumbered | `testGlobstarGradleNoSlash` | MARK: - Globstar - Gradle | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:205 |
| unnumbered | `testGlobstarGradleWithSlash` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:223 |
| unnumbered | `testGlobstarGradleWithSlash` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:223 |
| unnumbered | `testGlobstarGradleWithSlash` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:223 |
| unnumbered | `testGlobstarGradleWithSlashAndWildcard` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:241 |
| unnumbered | `testGlobstarGradleWithSlashAndWildcard` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:241 |
| unnumbered | `testGlobstarGradleWithSlashAndWildcard` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:241 |
| unnumbered | `testIndexing` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:110 |
| unnumbered | `testIndexing` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:110 |
| unnumbered | `testIndexing` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:110 |
| unnumbered | `testIntegrationWithInputValidation` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:263 |
| unnumbered | `testIntegrationWithOutputValidation` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:334 |
| unnumbered | `testInts` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:71 |
| unnumbered | `testInts` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:71 |
| unnumbered | `testInts` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:71 |
| unnumbered | `testInvalidCapUrn` | TEST001 variant: Test empty URN fails | Tests/CapDAGTests/CSCapUrnTests.m:104 |
| unnumbered | `testInvalidCharacters` | TEST003: Invalid format/character test | Tests/CapDAGTests/CSCapUrnTests.m:134 |
| unnumbered | `testInvalidUrnHandling` |  | Tests/CapDAGTests/CSCapMatrixTests.m:147 |
| unnumbered | `testIterateTwice` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:94 |
| unnumbered | `testIterateTwice` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:94 |
| unnumbered | `testIterateTwice` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:94 |
| unnumbered | `testMacOSOnlyTypes` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:474 |
| unnumbered | `testMacOSOnlyTypes` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:474 |
| unnumbered | `testMacOSOnlyTypes` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:474 |
| unnumbered | `testMaps` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:172 |
| unnumbered | `testMaps` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:172 |
| unnumbered | `testMaps` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:172 |
| unnumbered | `testMediaSpecDocumentationPropagatesThroughResolve` | Documentation propagates from a mediaSpecs definition through CSResolveMediaUrn into the resolved CSMediaSpec. Mirrors TEST924 on the Rust side and testJS_mediaSpecDocumentationPropagatesThroughResolve on the JS side. | Tests/CapDAGTests/CSCapTests.m:864 |
| unnumbered | `testMediaSpecsResolution` |  | Tests/CapDAGTests/CSCapTests.m:360 |
| unnumbered | `testMediaSpecsWithoutSchemaSkipsValidation` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:595 |
| unnumbered | `testMerge` | TEST026: Test merge | Tests/CapDAGTests/CSCapUrnTests.m:457 |
| unnumbered | `testMetadataNilByDefault` |  | Tests/CapDAGTests/CSMediaSpecTests.m:44 |
| unnumbered | `testMetadataPropagationFromObjectDef` |  | Tests/CapDAGTests/CSMediaSpecTests.m:14 |
| unnumbered | `testMetadataWithValidation` |  | Tests/CapDAGTests/CSMediaSpecTests.m:62 |
| unnumbered | `testMissingOutSpecDefaultsToWildcard` | TEST002: Missing 'out' defaults to media: | Tests/CapDAGTests/CSCapUrnTests.m:157 |
| unnumbered | `testMoreTransformsURLSchemeBuilding` | / Test building "More..." URL (shows target selection in main app) | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:376 |
| unnumbered | `testMultiStepPath` |  | Tests/CapDAGTests/CSLiveCapGraphTests.m:80 |
| unnumbered | `testMultiTypeStruct` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:295 |
| unnumbered | `testMultiTypeStruct` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:295 |
| unnumbered | `testMultiTypeStruct` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:295 |
| unnumbered | `testMultipleExtensions` |  | Tests/CapDAGTests/CSMediaSpecTests.m:184 |
| unnumbered | `testNegativeInts` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:115 |
| unnumbered | `testNegativeInts` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:115 |
| unnumbered | `testNegativeInts` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:115 |
| unnumbered | `testNestedSubscriptSetter` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:22 |
| unnumbered | `testNestedSubscriptSetter` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORTests.swift:22 |
| unnumbered | `testNestedSubscriptSetter` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:22 |
| unnumbered | `testNestedSubscriptSetterWithNewMap` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:39 |
| unnumbered | `testNestedSubscriptSetterWithNewMap` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORTests.swift:39 |
| unnumbered | `testNestedSubscriptSetterWithNewMap` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:39 |
| unnumbered | `testNil` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:56 |
| unnumbered | `testNil` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:56 |
| unnumbered | `testNil` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:56 |
| unnumbered | `testNonStructuredArgumentSkipsSchemaValidation` | Obj-C specific: Non-structured argument skips schema validation | Tests/CapDAGTests/CSSchemaValidationTests.m:150 |
| unnumbered | `testNormalizeHandlesDifferentTagOrders` | / Test that different tag orders normalize to the same URL | Tests/CapDAGTests/CSCapRegistryTests.m:102 |
| unnumbered | `testNothingMatches` |  | .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:78 |
| unnumbered | `testNothingMatches` |  | testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:78 |
| unnumbered | `testNothingMatches` |  | testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:78 |
| unnumbered | `testOpenInMachineFabricURLSchemeBuilding` | / Test building "Open in MachineFabric" URL | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:406 |
| unnumbered | `testOptionalArray` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:358 |
| unnumbered | `testOptionalArray` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:358 |
| unnumbered | `testOptionalArray` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:358 |
| unnumbered | `testOutputCreationWithNewAPI` |  | Tests/CapDAGTests/CSCapTests.m:766 |
| unnumbered | `testOutputWithEmbeddedSchemaValidationFailure` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:222 |
| unnumbered | `testOutputWithEmbeddedSchemaValidationSuccess` | Obj-C specific: Output validation tests | Tests/CapDAGTests/CSSchemaValidationTests.m:179 |
| unnumbered | `testPressureAndKill` | / Single test: allocate 90% of RAM with incompressible CSPRNG data, monitor / memory, detect pressure (kernel or threshold), kill cartridge, verify death. / The goal is to overload the system — force the kernel into real pressure. | testcartridge-host/Sources/TestcartridgeHost/main.swift:288 |
| unnumbered | `testRandomInputDoesNotHitStackLimits` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:197 |
| unnumbered | `testRandomInputDoesNotHitStackLimits` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:197 |
| unnumbered | `testRandomInputDoesNotHitStackLimits` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:197 |
| unnumbered | `testReadmeExamples` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:301 |
| unnumbered | `testReadmeExamples` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:301 |
| unnumbered | `testReadmeExamples` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:301 |
| unnumbered | `testRegisterAndFindCapSet` |  | Tests/CapDAGTests/CSCapMatrixTests.m:53 |
| unnumbered | `testRegistryCreation` |  | Tests/CapDAGTests/CSCapRegistryTests.m:40 |
| unnumbered | `testRegistryValidCapCheck` | Registry validator tests removed - not part of current API | Tests/CapDAGTests/CSCapRegistryTests.m:47 |
| unnumbered | `testResolveMediaUrnNotFound` |  | Tests/CapDAGTests/CSMediaSpecTests.m:98 |
| unnumbered | `testSchemaValidationErrorDetails` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:495 |
| unnumbered | `testSchemaValidationPerformance` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:621 |
| unnumbered | `testSimpleStruct` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:11 |
| unnumbered | `testSimpleStruct` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:11 |
| unnumbered | `testSimpleStruct` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:11 |
| unnumbered | `testSimpleStructsAsKeysInMap` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:41 |
| unnumbered | `testSimpleStructsAsKeysInMap` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:41 |
| unnumbered | `testSimpleStructsAsKeysInMap` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:41 |
| unnumbered | `testSimpleStructsAsValuesInMap` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:26 |
| unnumbered | `testSimpleStructsAsValuesInMap` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:26 |
| unnumbered | `testSimpleStructsAsValuesInMap` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:26 |
| unnumbered | `testSimpleStructsInArray` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:17 |
| unnumbered | `testSimpleStructsInArray` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:17 |
| unnumbered | `testSimpleStructsInArray` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:17 |
| unnumbered | `testSourceWithData` |  | Tests/CapDAGTests/CSStdinSourceTests.m:14 |
| unnumbered | `testSourceWithFileReference` |  | Tests/CapDAGTests/CSStdinSourceTests.m:29 |
| unnumbered | `testStandaloneCollectNode` | MARK: - Standalone Collect Node Tests | Tests/CapDAGTests/CSPlanDecompositionTests.m:63 |
| unnumbered | `testStrings` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:139 |
| unnumbered | `testStrings` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:139 |
| unnumbered | `testStrings` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:139 |
| unnumbered | `testStructContainingEnum` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:262 |
| unnumbered | `testStructContainingEnum` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:262 |
| unnumbered | `testStructContainingEnum` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:262 |
| unnumbered | `testStructWithArray` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:278 |
| unnumbered | `testStructWithArray` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:278 |
| unnumbered | `testStructWithArray` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:278 |
| unnumbered | `testStructWithFloat` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:241 |
| unnumbered | `testStructWithFloat` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:241 |
| unnumbered | `testStructWithFloat` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:241 |
| unnumbered | `testSubscriptSetter` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:5 |
| unnumbered | `testSubscriptSetter` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORTests.swift:5 |
| unnumbered | `testSubscriptSetter` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:5 |
| unnumbered | `testSyncFromCaps` |  | Tests/CapDAGTests/CSLiveCapGraphTests.m:124 |
| unnumbered | `testToCBOR` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncodableTests.swift:5 |
| unnumbered | `testToCBOR` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncodableTests.swift:5 |
| unnumbered | `testToCBOR` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncodableTests.swift:5 |
| unnumbered | `testTransformURLSchemeBuilding` | / Test building transform URL scheme (done client-side in FinderSync) | testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:344 |
| unnumbered | `testURLEncodesQuotedMediaUrns` | / Test that media URNs in cap URNs are properly URL-encoded | Tests/CapDAGTests/CSCapRegistryTests.m:74 |
| unnumbered | `testURLFormatIsValid` | / Test the URL format is valid and can be parsed | Tests/CapDAGTests/CSCapRegistryTests.m:85 |
| unnumbered | `testURLKeepsCapPrefixLiteral` | / Test that URL construction keeps "cap:" literal and only encodes the tags part | Tests/CapDAGTests/CSCapRegistryTests.m:63 |
| unnumbered | `testUnregisterCapSet` |  | Tests/CapDAGTests/CSCapMatrixTests.m:187 |
| unnumbered | `testUnregisterCapSet569` | TEST569: unregisterCapSet | Tests/CapDAGTests/CSCapMatrixTests.m:241 |
| unnumbered | `testValidateCapCanonical` |  | Tests/CapDAGTests/CSCapRegistryTests.m:135 |
| unnumbered | `testValidateNoMediaSpecDuplicatesEmpty` |  | Tests/CapDAGTests/CSMediaSpecTests.m:241 |
| unnumbered | `testValidateNoMediaSpecDuplicatesFail` |  | Tests/CapDAGTests/CSMediaSpecTests.m:224 |
| unnumbered | `testValidateNoMediaSpecDuplicatesNil` |  | Tests/CapDAGTests/CSMediaSpecTests.m:250 |
| unnumbered | `testValidateNoMediaSpecDuplicatesPass` | Duplicate URN validation tests | Tests/CapDAGTests/CSMediaSpecTests.m:210 |
| unnumbered | `testValuelessTagParsing` | TEST031: Test wildcard rejected in keys but accepted in values (variant: solo tags as wildcards) | Tests/CapDAGTests/CSCapUrnTests.m:114 |
| unnumbered | `testWildcard001EmptyCapDefaultsToMediaWildcard` | TEST_WILDCARD_001: cap: (empty) defaults to in=media:;out=media: | Tests/CapDAGTests/CSCapUrnTests.m:982 |
| unnumbered | `testWildcard002InOnlyDefaultsOutToMedia` | TEST_WILDCARD_002: cap:in defaults out to media: | Tests/CapDAGTests/CSCapUrnTests.m:993 |
| unnumbered | `testWildcard003OutOnlyDefaultsInToMedia` | TEST_WILDCARD_003: cap:out defaults in to media: | Tests/CapDAGTests/CSCapUrnTests.m:1002 |
| unnumbered | `testWildcard004InOutNoValuesBecomeMedia` | TEST_WILDCARD_004: cap:in;out both become media: | Tests/CapDAGTests/CSCapUrnTests.m:1011 |
| unnumbered | `testWildcard005ExplicitAsteriskBecomesMedia` | TEST_WILDCARD_005: cap:in=*;out=* becomes media: | Tests/CapDAGTests/CSCapUrnTests.m:1020 |
| unnumbered | `testWildcard006SpecificInWildcardOut` | TEST_WILDCARD_006: cap:in=media:;out=* has specific in, wildcard out | Tests/CapDAGTests/CSCapUrnTests.m:1029 |
| unnumbered | `testWildcard007WildcardInSpecificOut` | TEST_WILDCARD_007: cap:in=*;out=media:text has wildcard in, specific out | Tests/CapDAGTests/CSCapUrnTests.m:1038 |
| unnumbered | `testWildcard008InvalidInSpecFails` | TEST_WILDCARD_008: cap:in=foo fails (invalid media URN) | Tests/CapDAGTests/CSCapUrnTests.m:1047 |
| unnumbered | `testWildcard009InvalidOutSpecFails` | TEST_WILDCARD_009: cap:in=media:;out=bar fails (invalid media URN) | Tests/CapDAGTests/CSCapUrnTests.m:1056 |
| unnumbered | `testWildcard010WildcardAcceptsSpecific` | TEST_WILDCARD_010: Wildcard in/out match specific caps | Tests/CapDAGTests/CSCapUrnTests.m:1065 |
| unnumbered | `testWildcard011SpecificityScoring` | TEST_WILDCARD_011: Specificity - wildcard has 0, specific has tag count | Tests/CapDAGTests/CSCapUrnTests.m:1075 |
| unnumbered | `testWildcard012PreserveOtherTags` | TEST_WILDCARD_012: cap:in;out;op=test preserves other tags | Tests/CapDAGTests/CSCapUrnTests.m:1085 |
| unnumbered | `testWildcardTagDirection` | TEST027: with_wildcard_tag for in/out direction | Tests/CapDAGTests/CSCapUrnTests.m:433 |
| unnumbered | `testWithInSpec` | TEST036: Test with_in_spec sets input direction | Tests/CapDAGTests/CSCapUrnTests.m:374 |
| unnumbered | `testWithOutSpec` | TEST036: Test with_out_spec sets output direction | Tests/CapDAGTests/CSCapUrnTests.m:384 |
| unnumbered | `testWithTagIgnoresInOut` | TEST036: with_tag ignores in/out (use with_in_spec/with_out_spec instead) | Tests/CapDAGTests/CSCapUrnTests.m:361 |
| unnumbered | `testWithoutTag` | TEST036: Test without_tag removes tag | Tests/CapDAGTests/CSCapUrnTests.m:394 |
| unnumbered | `testWithoutTagIgnoresInOut` | TEST036: without_tag ignores in/out | Tests/CapDAGTests/CSCapUrnTests.m:406 |
| unnumbered | `testWrappedStruct` |  | .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:191 |
| unnumbered | `testWrappedStruct` |  | testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:191 |
| unnumbered | `testWrappedStruct` |  | testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:191 |
| unnumbered | `test_csCapManifestWithPageUrl` | Additional test: CSCapManifest with pageUrl | Tests/BifaciTests/ManifestTests.swift:192 |
| unnumbered | `test_glob_pattern_detection` |  | Tests/CapDAGTests/CSInputResolverTests.m:669 |
| unnumbered | `test_resolved_file_properties` |  | Tests/CapDAGTests/CSInputResolverTests.m:680 |
| unnumbered | `test_resolved_file_scalar_opaque` |  | Tests/CapDAGTests/CSInputResolverTests.m:692 |
| unnumbered | `test_resolved_input_set_total_size` |  | Tests/CapDAGTests/CSInputResolverTests.m:704 |
---

## Unnumbered Tests

The following tests are cataloged but do not currently participate in numeric test indexing.

- `test198b_limitsNegotiation` — Tests/BifaciTests/FrameTests.swift:308
- `test205b_allFrameTypesRoundtrip` — Tests/BifaciTests/FrameTests.swift:903
- `test389b_streamStartIsSequenceRoundtrip` — Tests/BifaciTests/FrameTests.swift:1100
- `test542b_outputStreamStartThenCloseEmpty` — Tests/BifaciTests/StreamingAPITests.swift:407
- `test542c_outputStreamWriteWithoutStartThrows` — Tests/BifaciTests/StreamingAPITests.swift:437
- `test542d_outputStreamDoubleStartThrows` — Tests/BifaciTests/StreamingAPITests.swift:453
- `test542e_outputStreamModeConflictThrows` — Tests/BifaciTests/StreamingAPITests.swift:470
- `test754ExtractPrefixNonexistent` — Tests/CapDAGTests/CSPlanDecompositionTests.m:135
- `test755ExtractForeachBody` — Tests/CapDAGTests/CSPlanDecompositionTests.m:144
- `test756ExtractForeachBodyUnclosed` — Tests/CapDAGTests/CSPlanDecompositionTests.m:176
- `test757ExtractForeachBodyWrongType` — Tests/CapDAGTests/CSPlanDecompositionTests.m:193
- `test758ExtractSuffixFrom` — Tests/CapDAGTests/CSPlanDecompositionTests.m:204
- `test759ExtractSuffixNonexistent` — Tests/CapDAGTests/CSPlanDecompositionTests.m:225
- `test760DecompositionCoversAllCaps` — Tests/CapDAGTests/CSPlanDecompositionTests.m:234
- `test761PrefixIsDag` — Tests/CapDAGTests/CSPlanDecompositionTests.m:273
- `test762BodyIsDag` — Tests/CapDAGTests/CSPlanDecompositionTests.m:282
- `test763SuffixIsDag` — Tests/CapDAGTests/CSPlanDecompositionTests.m:291
- `test764PrefixToInputSlot` — Tests/CapDAGTests/CSPlanDecompositionTests.m:300
- `test772FindPathsMultiStep` — Tests/CapDAGTests/CSLiveCapGraphTests.m:149
- `test773FindPathsEmptyWhenNoPath` — Tests/CapDAGTests/CSLiveCapGraphTests.m:171
- `test774GetReachableTargetsAll` — Tests/CapDAGTests/CSLiveCapGraphTests.m:187
- `test777TypeMismatchPdfPng` — Tests/CapDAGTests/CSLiveCapGraphTests.m:210
- `test778TypeMismatchPngPdf` — Tests/CapDAGTests/CSLiveCapGraphTests.m:225
- `test779ReachableTargetsTypeMatching` — Tests/CapDAGTests/CSLiveCapGraphTests.m:240
- `test781FindPathsTypeChain` — Tests/CapDAGTests/CSLiveCapGraphTests.m:263
- `test787SortingShorterFirst` — Tests/CapDAGTests/CSLiveCapGraphTests.m:286
- `test788ForEachWithSequenceInput` — Tests/CapDAGTests/CSLiveCapGraphTests.m:308
- `test790IdentityUrnSpecific` — Tests/CapDAGTests/CSLiveCapGraphTests.m:349
- `test934FindFirstForeach` — Tests/CapDAGTests/CSPlanDecompositionTests.m:84
- `test935FindFirstForeachLinear` — Tests/CapDAGTests/CSPlanDecompositionTests.m:91
- `test936HasForeach` — Tests/CapDAGTests/CSPlanDecompositionTests.m:100
- `test937ExtractPrefixTo` — Tests/CapDAGTests/CSPlanDecompositionTests.m:112
- `testAddCapAndBasicTraversal` — Tests/CapDAGTests/CSLiveCapGraphTests.m:32
- `testAnyRecursive` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:342
- `testAnyRecursive` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:342
- `testAnyRecursive` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:342
- `testArgumentCreationWithNewAPI` — Tests/CapDAGTests/CSCapTests.m:729
- `testArrays` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:157
- `testArrays` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:157
- `testArrays` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:157
- `testBadgeClearingAfterCompletion` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:432
- `testBadgeStateTransitions` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:448
- `testBadgeStatusPolling_EmptyState` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:266
- `testBadgeStatusPolling_WithActiveTransform` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:293
- `testBestCapSetSelection` — Tests/CapDAGTests/CSCapMatrixTests.m:101
- `testBools` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:62
- `testBools` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:62
- `testBools` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:62
- `testBraces` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:68
- `testBraces` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:68
- `testBraces` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:68
- `testBuilderBasicConstruction` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:16
- `testBuilderComplex` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:173
- `testBuilderCustomTags` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:70
- `testBuilderDirectionAccess` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:53
- `testBuilderDirectionMismatchNoMatch` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:286
- `testBuilderEmptyBuildFailsWithMissingInSpec` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:131
- `testBuilderFluentAPI` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:32
- `testBuilderMatchingWithBuiltCap` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:240
- `testBuilderMinimalValid` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:158
- `testBuilderMissingInSpecFails` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:105
- `testBuilderMissingOutSpecFails` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:118
- `testBuilderStaticFactory` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:231
- `testBuilderTagIgnoresInOut` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:140
- `testBuilderTagOverrides` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:88
- `testBuilderWildcards` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:207
- `testBuiltinSpecIdsResolve` — Tests/CapDAGTests/CSSchemaValidationTests.m:541
- `testCanHandle` — Tests/CapDAGTests/CSCapMatrixTests.m:156
- `testCanonicalArgumentsDeserialization` — Tests/CapDAGTests/CSCapTests.m:215
- `testCanonicalDictionaryDeserialization` — Tests/CapDAGTests/CSCapTests.m:168
- `testCanonicalOutputDeserialization` — Tests/CapDAGTests/CSCapTests.m:239
- `testCanonicalValidationDeserialization` — Tests/CapDAGTests/CSCapTests.m:255
- `testCapAndForEachAreNotStandaloneCollect` — Tests/CapDAGTests/CSPlanDecompositionTests.m:75
- `testCapBlockCanMethod` — Tests/CapDAGTests/CSCapBlockTests.m:244
- `testCapBlockFallbackScenario` — Tests/CapDAGTests/CSCapBlockTests.m:192
- `testCapBlockMoreSpecificWins` — Tests/CapDAGTests/CSCapBlockTests.m:65
- `testCapBlockNoMatch` — Tests/CapDAGTests/CSCapBlockTests.m:178
- `testCapBlockPollsAll` — Tests/CapDAGTests/CSCapBlockTests.m:138
- `testCapBlockRegistryManagement` — Tests/CapDAGTests/CSCapBlockTests.m:269
- `testCapBlockTieGoesToFirst` — Tests/CapDAGTests/CSCapBlockTests.m:106
- `testCapCreation` — Tests/CapDAGTests/CSCapTests.m:22
- `testCapDocumentationOmittedWhenNil` — Tests/CapDAGTests/CSCapTests.m:827
- `testCapDocumentationRoundTrip` — Tests/CapDAGTests/CSCapTests.m:788
- `testCapGraphBasicConstruction` — Tests/CapDAGTests/CSCapGraphTests.m:58
- `testCapGraphCanConvert` — Tests/CapDAGTests/CSCapGraphTests.m:118
- `testCapGraphFindAllPaths` — Tests/CapDAGTests/CSCapGraphTests.m:187
- `testCapGraphFindPath` — Tests/CapDAGTests/CSCapGraphTests.m:149
- `testCapGraphGetDirectEdges` — Tests/CapDAGTests/CSCapGraphTests.m:216
- `testCapGraphOutgoingIncoming` — Tests/CapDAGTests/CSCapGraphTests.m:89
- `testCapGraphStats` — Tests/CapDAGTests/CSCapGraphTests.m:258
- `testCapGraphWithCapBlock` — Tests/CapDAGTests/CSCapGraphTests.m:290
- `testCapManifestCompatibility` — Tests/CapDAGTests/CSCapTests.m:682
- `testCapManifestCreation` — Tests/CapDAGTests/CSCapTests.m:426
- `testCapManifestDictionaryDeserialization` — Tests/CapDAGTests/CSCapTests.m:509
- `testCapManifestEmptyCaps` — Tests/CapDAGTests/CSCapTests.m:611
- `testCapManifestOptionalAuthorField` — Tests/CapDAGTests/CSCapTests.m:635
- `testCapManifestRequiredFields` — Tests/CapDAGTests/CSCapTests.m:555
- `testCapManifestWithAuthor` — Tests/CapDAGTests/CSCapTests.m:455
- `testCapManifestWithMultipleCaps` — Tests/CapDAGTests/CSCapTests.m:568
- `testCapManifestWithPageUrl` — Tests/CapDAGTests/CSCapTests.m:481
- `testCapMatching` — Tests/CapDAGTests/CSCapTests.m:113
- `testCapStdinSerialization` — Tests/CapDAGTests/CSCapTests.m:138
- `testCapStdinType` — Tests/CapDAGTests/CSCapTests.m:69
- `testCapWithDescription` — Tests/CapDAGTests/CSCapTests.m:47
- `testClear` — Tests/CapDAGTests/CSCapMatrixTests.m:475
- `testClear570` — Tests/CapDAGTests/CSCapMatrixTests.m:253
- `testCoding` — Tests/CapDAGTests/CSCapUrnTests.m:487
- `testCompleteCapDeserialization` — Tests/CapDAGTests/CSCapTests.m:275
- `testCompleteFinderSyncFlow` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:480
- `testComplexNestedSchema` — Tests/CapDAGTests/CSSchemaValidationTests.m:404
- `testContextMenuPopulation_MultipleFiles` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:147
- `testContextMenuPopulation_NonExistentFile` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:244
- `testContextMenuPopulation_SinglePDF` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:101
- `testContextMenuPopulation_Timeout` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:175
- `testContextMenuPopulation_UnsupportedFileType` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:214
- `testCopying` — Tests/CapDAGTests/CSCapUrnTests.m:509
- `testDataSourceWithBinaryContent` — Tests/CapDAGTests/CSStdinSourceTests.m:61
- `testDataSourceWithEmptyData` — Tests/CapDAGTests/CSStdinSourceTests.m:51
- `testDecodeArrays` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:64
- `testDecodeArrays` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:92
- `testDecodeArrays` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:64
- `testDecodeArrays` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:92
- `testDecodeArrays` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:64
- `testDecodeArrays` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:92
- `testDecodeBools` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:10
- `testDecodeBools` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:10
- `testDecodeBools` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:10
- `testDecodeByteStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:29
- `testDecodeByteStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:85
- `testDecodeByteStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:29
- `testDecodeByteStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:85
- `testDecodeByteStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:29
- `testDecodeByteStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:85
- `testDecodeData` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:41
- `testDecodeData` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:41
- `testDecodeData` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:41
- `testDecodeDates` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:106
- `testDecodeDates` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:120
- `testDecodeDates` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:106
- `testDecodeDates` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:120
- `testDecodeDates` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:106
- `testDecodeDates` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:120
- `testDecodeFailsForExtremelyDeepStructures` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:172
- `testDecodeFailsForExtremelyDeepStructures` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:172
- `testDecodeFailsForExtremelyDeepStructures` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:172
- `testDecodeFailsForSillyMaximumDepths` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:183
- `testDecodeFailsForSillyMaximumDepths` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:183
- `testDecodeFailsForSillyMaximumDepths` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:183
- `testDecodeFloats` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:98
- `testDecodeFloats` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:98
- `testDecodeFloats` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:98
- `testDecodeFromIssue78` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:141
- `testDecodeFromIssue78` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:141
- `testDecodeFromIssue78` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:141
- `testDecodeInts` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:17
- `testDecodeInts` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:17
- `testDecodeInts` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:17
- `testDecodeMapFromIssue29` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:124
- `testDecodeMapFromIssue29` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:124
- `testDecodeMapFromIssue29` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:124
- `testDecodeMaps` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:73
- `testDecodeMaps` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:107
- `testDecodeMaps` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:73
- `testDecodeMaps` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:107
- `testDecodeMaps` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:73
- `testDecodeMaps` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:107
- `testDecodeNegativeInts` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:51
- `testDecodeNegativeInts` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:51
- `testDecodeNegativeInts` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:51
- `testDecodeNull` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:5
- `testDecodeNull` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:5
- `testDecodeNull` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:5
- `testDecodeNumbers` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:5
- `testDecodeNumbers` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:5
- `testDecodeNumbers` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:5
- `testDecodeOfStructContainingNestedIndefiniteMapsAndArrays` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:159
- `testDecodeOfStructContainingNestedIndefiniteMapsAndArrays` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:159
- `testDecodeOfStructContainingNestedIndefiniteMapsAndArrays` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:159
- `testDecodePerformance` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:113
- `testDecodePerformance` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:113
- `testDecodePerformance` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:113
- `testDecodeSimple` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:88
- `testDecodeSimple` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:88
- `testDecodeSimple` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:88
- `testDecodeStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:71
- `testDecodeStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:71
- `testDecodeStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBORDecoderTests.swift:71
- `testDecodeSucceedsForAllowedDeepStructures` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:190
- `testDecodeSucceedsForAllowedDeepStructures` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:190
- `testDecodeSucceedsForAllowedDeepStructures` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:190
- `testDecodeTagged` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:81
- `testDecodeTagged` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:81
- `testDecodeTagged` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:81
- `testDecodeUtf8Strings` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:53
- `testDecodeUtf8Strings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:53
- `testDecodeUtf8Strings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:53
- `testDeterministicOrdering` — Tests/CapDAGTests/CSLiveCapGraphTests.m:100
- `testDirectAccess` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:88
- `testDirectAccess` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:88
- `testDirectAccess` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:88
- `testDirectionSemanticMatching` — Tests/CapDAGTests/CSCapUrnTests.m:915
- `testDirectionSemanticSpecificity` — Tests/CapDAGTests/CSCapUrnTests.m:962
- `testDirectionWildcardMatches` — Tests/CapDAGTests/CSCapUrnTests.m:218
- `testDotParserCapUrnLabel` — Tests/BifaciTests/OrchestratorTests.swift:413
- `testDotParserComments` — Tests/BifaciTests/OrchestratorTests.swift:397
- `testDotParserEdgeWithLabel` — Tests/BifaciTests/OrchestratorTests.swift:350
- `testDotParserNodeWithAttributes` — Tests/BifaciTests/OrchestratorTests.swift:364
- `testDotParserQuotedIdentifiers` — Tests/BifaciTests/OrchestratorTests.swift:381
- `testDotParserSimpleDigraph` — Tests/BifaciTests/OrchestratorTests.swift:330
- `testDoubleGlobstarBashV3` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:142
- `testDoubleGlobstarBashV3` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:142
- `testDoubleGlobstarBashV3` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:142
- `testDoubleGlobstarBashV4` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:194
- `testDoubleGlobstarBashV4` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:194
- `testDoubleGlobstarBashV4` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:194
- `testDoubleGlobstarGradle` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:259
- `testDoubleGlobstarGradle` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:259
- `testDoubleGlobstarGradle` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:259
- `testEncodeAny` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:331
- `testEncodeAny` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:331
- `testEncodeAny` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:331
- `testEncodeArrays` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:72
- `testEncodeArrays` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:89
- `testEncodeArrays` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:72
- `testEncodeArrays` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:89
- `testEncodeArrays` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:72
- `testEncodeArrays` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:89
- `testEncodeBools` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:10
- `testEncodeBools` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:10
- `testEncodeBools` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:10
- `testEncodeByteStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:27
- `testEncodeByteStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:84
- `testEncodeByteStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:27
- `testEncodeByteStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:84
- `testEncodeByteStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:27
- `testEncodeByteStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:84
- `testEncodeData` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:41
- `testEncodeData` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:41
- `testEncodeData` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:41
- `testEncodeDates` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:277
- `testEncodeDates` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:277
- `testEncodeDates` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:277
- `testEncodeFloats` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:199
- `testEncodeFloats` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:199
- `testEncodeFloats` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:199
- `testEncodeIndefiniteArrays` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:229
- `testEncodeIndefiniteArrays` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:229
- `testEncodeIndefiniteArrays` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:229
- `testEncodeIndefiniteByteStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:265
- `testEncodeIndefiniteByteStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:265
- `testEncodeIndefiniteByteStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:265
- `testEncodeIndefiniteMaps` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:247
- `testEncodeIndefiniteMaps` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:247
- `testEncodeIndefiniteMaps` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:247
- `testEncodeIndefiniteStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:257
- `testEncodeIndefiniteStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:257
- `testEncodeIndefiniteStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:257
- `testEncodeInts` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:10
- `testEncodeInts` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:17
- `testEncodeInts` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:10
- `testEncodeInts` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:17
- `testEncodeInts` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:10
- `testEncodeInts` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:17
- `testEncodeMaps` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:88
- `testEncodeMaps` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:100
- `testEncodeMaps` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:88
- `testEncodeMaps` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:100
- `testEncodeMaps` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:88
- `testEncodeMaps` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:100
- `testEncodeNegativeInts` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:51
- `testEncodeNegativeInts` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:51
- `testEncodeNegativeInts` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:51
- `testEncodeNull` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:5
- `testEncodeNull` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:5
- `testEncodeNull` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:5
- `testEncodeSimple` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:188
- `testEncodeSimple` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:188
- `testEncodeSimple` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:188
- `testEncodeSimpleStructs` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:120
- `testEncodeSimpleStructs` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:120
- `testEncodeSimpleStructs` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:120
- `testEncodeSortedMaps` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:117
- `testEncodeSortedMaps` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:117
- `testEncodeSortedMaps` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:117
- `testEncodeStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:71
- `testEncodeStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:71
- `testEncodeStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CodableCBOREncoderTests.swift:71
- `testEncodeTagged` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:181
- `testEncodeTagged` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:181
- `testEncodeTagged` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:181
- `testEncodeUtf8Strings` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:55
- `testEncodeUtf8Strings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:55
- `testEncodeUtf8Strings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:55
- `testEquality` — Tests/CapDAGTests/CSCapUrnTests.m:473
- `testExactVsConformanceMatching` — Tests/CapDAGTests/CSLiveCapGraphTests.m:50
- `testExtensionsEmptyWhenNotSet` — Tests/CapDAGTests/CSMediaSpecTests.m:133
- `testExtensionsPropagationFromObjectDef` — Tests/CapDAGTests/CSMediaSpecTests.m:110
- `testExtensionsWithMetadataAndValidation` — Tests/CapDAGTests/CSMediaSpecTests.m:152
- `testFileReferenceWithAllFields` — Tests/CapDAGTests/CSStdinSourceTests.m:74
- `testFoundationHeavyType` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:377
- `testFoundationHeavyType` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:377
- `testFoundationHeavyType` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:377
- `testFullCapValidationWithMediaSpecs` — Tests/CapDAGTests/CSSchemaValidationTests.m:679
- `testGetCapDefinitionReal` — Tests/CapDAGTests/CSCapRegistryTests.m:115
- `testGlobstarBashV3NoSlash` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:121
- `testGlobstarBashV3NoSlash` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:121
- `testGlobstarBashV3NoSlash` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:121
- `testGlobstarBashV3WithSlash` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:128
- `testGlobstarBashV3WithSlash` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:128
- `testGlobstarBashV3WithSlash` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:128
- `testGlobstarBashV3WithSlashAndWildcard` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:135
- `testGlobstarBashV3WithSlashAndWildcard` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:135
- `testGlobstarBashV3WithSlashAndWildcard` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:135
- `testGlobstarBashV4NoSlash` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:150
- `testGlobstarBashV4NoSlash` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:150
- `testGlobstarBashV4NoSlash` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:150
- `testGlobstarBashV4WithSlash` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:166
- `testGlobstarBashV4WithSlash` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:166
- `testGlobstarBashV4WithSlash` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:166
- `testGlobstarBashV4WithSlashAndWildcard` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:178
- `testGlobstarBashV4WithSlashAndWildcard` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:178
- `testGlobstarBashV4WithSlashAndWildcard` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:178
- `testGlobstarGradleNoSlash` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:205
- `testGlobstarGradleNoSlash` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:205
- `testGlobstarGradleNoSlash` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:205
- `testGlobstarGradleWithSlash` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:223
- `testGlobstarGradleWithSlash` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:223
- `testGlobstarGradleWithSlash` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:223
- `testGlobstarGradleWithSlashAndWildcard` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:241
- `testGlobstarGradleWithSlashAndWildcard` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:241
- `testGlobstarGradleWithSlashAndWildcard` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:241
- `testIndexing` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:110
- `testIndexing` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:110
- `testIndexing` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:110
- `testIntegrationWithInputValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:263
- `testIntegrationWithOutputValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:334
- `testInts` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:71
- `testInts` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:71
- `testInts` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:71
- `testInvalidCapUrn` — Tests/CapDAGTests/CSCapUrnTests.m:104
- `testInvalidCharacters` — Tests/CapDAGTests/CSCapUrnTests.m:134
- `testInvalidUrnHandling` — Tests/CapDAGTests/CSCapMatrixTests.m:147
- `testIterateTwice` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:94
- `testIterateTwice` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:94
- `testIterateTwice` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:94
- `testMacOSOnlyTypes` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:474
- `testMacOSOnlyTypes` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:474
- `testMacOSOnlyTypes` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:474
- `testMaps` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:172
- `testMaps` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:172
- `testMaps` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:172
- `testMediaSpecDocumentationPropagatesThroughResolve` — Tests/CapDAGTests/CSCapTests.m:864
- `testMediaSpecsResolution` — Tests/CapDAGTests/CSCapTests.m:360
- `testMediaSpecsWithoutSchemaSkipsValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:595
- `testMerge` — Tests/CapDAGTests/CSCapUrnTests.m:457
- `testMetadataNilByDefault` — Tests/CapDAGTests/CSMediaSpecTests.m:44
- `testMetadataPropagationFromObjectDef` — Tests/CapDAGTests/CSMediaSpecTests.m:14
- `testMetadataWithValidation` — Tests/CapDAGTests/CSMediaSpecTests.m:62
- `testMissingOutSpecDefaultsToWildcard` — Tests/CapDAGTests/CSCapUrnTests.m:157
- `testMoreTransformsURLSchemeBuilding` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:376
- `testMultiStepPath` — Tests/CapDAGTests/CSLiveCapGraphTests.m:80
- `testMultiTypeStruct` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:295
- `testMultiTypeStruct` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:295
- `testMultiTypeStruct` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:295
- `testMultipleExtensions` — Tests/CapDAGTests/CSMediaSpecTests.m:184
- `testNegativeInts` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:115
- `testNegativeInts` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:115
- `testNegativeInts` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:115
- `testNestedSubscriptSetter` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:22
- `testNestedSubscriptSetter` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORTests.swift:22
- `testNestedSubscriptSetter` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:22
- `testNestedSubscriptSetterWithNewMap` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:39
- `testNestedSubscriptSetterWithNewMap` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORTests.swift:39
- `testNestedSubscriptSetterWithNewMap` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:39
- `testNil` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:56
- `testNil` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:56
- `testNil` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:56
- `testNonStructuredArgumentSkipsSchemaValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:150
- `testNormalizeHandlesDifferentTagOrders` — Tests/CapDAGTests/CSCapRegistryTests.m:102
- `testNothingMatches` — .build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:78
- `testNothingMatches` — testcartridge-host/.build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:78
- `testNothingMatches` — testcartridge-host/.build/index-build/checkouts/Glob/Tests/GlobTests/GlobTests.swift:78
- `testOpenInMachineFabricURLSchemeBuilding` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:406
- `testOptionalArray` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:358
- `testOptionalArray` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:358
- `testOptionalArray` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:358
- `testOutputCreationWithNewAPI` — Tests/CapDAGTests/CSCapTests.m:766
- `testOutputWithEmbeddedSchemaValidationFailure` — Tests/CapDAGTests/CSSchemaValidationTests.m:222
- `testOutputWithEmbeddedSchemaValidationSuccess` — Tests/CapDAGTests/CSSchemaValidationTests.m:179
- `testPressureAndKill` — testcartridge-host/Sources/TestcartridgeHost/main.swift:288
- `testRandomInputDoesNotHitStackLimits` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:197
- `testRandomInputDoesNotHitStackLimits` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:197
- `testRandomInputDoesNotHitStackLimits` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORDecoderTests.swift:197
- `testReadmeExamples` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:301
- `testReadmeExamples` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:301
- `testReadmeExamples` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncoderTests.swift:301
- `testRegisterAndFindCapSet` — Tests/CapDAGTests/CSCapMatrixTests.m:53
- `testRegistryCreation` — Tests/CapDAGTests/CSCapRegistryTests.m:40
- `testRegistryValidCapCheck` — Tests/CapDAGTests/CSCapRegistryTests.m:47
- `testResolveMediaUrnNotFound` — Tests/CapDAGTests/CSMediaSpecTests.m:98
- `testSchemaValidationErrorDetails` — Tests/CapDAGTests/CSSchemaValidationTests.m:495
- `testSchemaValidationPerformance` — Tests/CapDAGTests/CSSchemaValidationTests.m:621
- `testSimpleStruct` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:11
- `testSimpleStruct` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:11
- `testSimpleStruct` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:11
- `testSimpleStructsAsKeysInMap` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:41
- `testSimpleStructsAsKeysInMap` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:41
- `testSimpleStructsAsKeysInMap` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:41
- `testSimpleStructsAsValuesInMap` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:26
- `testSimpleStructsAsValuesInMap` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:26
- `testSimpleStructsAsValuesInMap` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:26
- `testSimpleStructsInArray` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:17
- `testSimpleStructsInArray` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:17
- `testSimpleStructsInArray` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:17
- `testSourceWithData` — Tests/CapDAGTests/CSStdinSourceTests.m:14
- `testSourceWithFileReference` — Tests/CapDAGTests/CSStdinSourceTests.m:29
- `testStandaloneCollectNode` — Tests/CapDAGTests/CSPlanDecompositionTests.m:63
- `testStrings` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:139
- `testStrings` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:139
- `testStrings` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:139
- `testStructContainingEnum` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:262
- `testStructContainingEnum` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:262
- `testStructContainingEnum` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:262
- `testStructWithArray` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:278
- `testStructWithArray` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:278
- `testStructWithArray` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:278
- `testStructWithFloat` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:241
- `testStructWithFloat` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:241
- `testStructWithFloat` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:241
- `testSubscriptSetter` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:5
- `testSubscriptSetter` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORTests.swift:5
- `testSubscriptSetter` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORTests.swift:5
- `testSyncFromCaps` — Tests/CapDAGTests/CSLiveCapGraphTests.m:124
- `testToCBOR` — .build/index-build/checkouts/SwiftCBOR/Tests/CBOREncodableTests.swift:5
- `testToCBOR` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBOREncodableTests.swift:5
- `testToCBOR` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBOREncodableTests.swift:5
- `testTransformURLSchemeBuilding` — testcartridge-host/.scrap/FinderSyncIntegrationTests.swift:344
- `testURLEncodesQuotedMediaUrns` — Tests/CapDAGTests/CSCapRegistryTests.m:74
- `testURLFormatIsValid` — Tests/CapDAGTests/CSCapRegistryTests.m:85
- `testURLKeepsCapPrefixLiteral` — Tests/CapDAGTests/CSCapRegistryTests.m:63
- `testUnregisterCapSet` — Tests/CapDAGTests/CSCapMatrixTests.m:187
- `testUnregisterCapSet569` — Tests/CapDAGTests/CSCapMatrixTests.m:241
- `testValidateCapCanonical` — Tests/CapDAGTests/CSCapRegistryTests.m:135
- `testValidateNoMediaSpecDuplicatesEmpty` — Tests/CapDAGTests/CSMediaSpecTests.m:241
- `testValidateNoMediaSpecDuplicatesFail` — Tests/CapDAGTests/CSMediaSpecTests.m:224
- `testValidateNoMediaSpecDuplicatesNil` — Tests/CapDAGTests/CSMediaSpecTests.m:250
- `testValidateNoMediaSpecDuplicatesPass` — Tests/CapDAGTests/CSMediaSpecTests.m:210
- `testValuelessTagParsing` — Tests/CapDAGTests/CSCapUrnTests.m:114
- `testWildcard001EmptyCapDefaultsToMediaWildcard` — Tests/CapDAGTests/CSCapUrnTests.m:982
- `testWildcard002InOnlyDefaultsOutToMedia` — Tests/CapDAGTests/CSCapUrnTests.m:993
- `testWildcard003OutOnlyDefaultsInToMedia` — Tests/CapDAGTests/CSCapUrnTests.m:1002
- `testWildcard004InOutNoValuesBecomeMedia` — Tests/CapDAGTests/CSCapUrnTests.m:1011
- `testWildcard005ExplicitAsteriskBecomesMedia` — Tests/CapDAGTests/CSCapUrnTests.m:1020
- `testWildcard006SpecificInWildcardOut` — Tests/CapDAGTests/CSCapUrnTests.m:1029
- `testWildcard007WildcardInSpecificOut` — Tests/CapDAGTests/CSCapUrnTests.m:1038
- `testWildcard008InvalidInSpecFails` — Tests/CapDAGTests/CSCapUrnTests.m:1047
- `testWildcard009InvalidOutSpecFails` — Tests/CapDAGTests/CSCapUrnTests.m:1056
- `testWildcard010WildcardAcceptsSpecific` — Tests/CapDAGTests/CSCapUrnTests.m:1065
- `testWildcard011SpecificityScoring` — Tests/CapDAGTests/CSCapUrnTests.m:1075
- `testWildcard012PreserveOtherTags` — Tests/CapDAGTests/CSCapUrnTests.m:1085
- `testWildcardTagDirection` — Tests/CapDAGTests/CSCapUrnTests.m:433
- `testWithInSpec` — Tests/CapDAGTests/CSCapUrnTests.m:374
- `testWithOutSpec` — Tests/CapDAGTests/CSCapUrnTests.m:384
- `testWithTagIgnoresInOut` — Tests/CapDAGTests/CSCapUrnTests.m:361
- `testWithoutTag` — Tests/CapDAGTests/CSCapUrnTests.m:394
- `testWithoutTagIgnoresInOut` — Tests/CapDAGTests/CSCapUrnTests.m:406
- `testWrappedStruct` — .build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:191
- `testWrappedStruct` — testcartridge-host/.build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:191
- `testWrappedStruct` — testcartridge-host/.build/index-build/checkouts/SwiftCBOR/Tests/CBORCodableRoundtripTests.swift:191
- `test_csCapManifestWithPageUrl` — Tests/BifaciTests/ManifestTests.swift:192
- `test_glob_pattern_detection` — Tests/CapDAGTests/CSInputResolverTests.m:669
- `test_resolved_file_properties` — Tests/CapDAGTests/CSInputResolverTests.m:680
- `test_resolved_file_scalar_opaque` — Tests/CapDAGTests/CSInputResolverTests.m:692
- `test_resolved_input_set_total_size` — Tests/CapDAGTests/CSInputResolverTests.m:704

---

*Generated from CapDag-ObjC/Swift source tree*
*Total tests: 1092*
*Total numbered tests: 618*
*Total unnumbered tests: 474*
