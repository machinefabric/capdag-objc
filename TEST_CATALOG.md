# Swift/ObjC Test Catalog

**Total Tests:** 785

**Numbered Tests:** 658

**Unnumbered Tests:** 127

**Numbered Tests Missing Descriptions:** 4

**Numbering Mismatches:** 0

All numbered test numbers are unique.

This catalog lists all tests in the Swift/ObjC codebase.

| Test # | Function Name | Description | File |
|--------|---------------|-------------|------|
| test001 | `test001_capUrnCreation` | TEST001: Test that cap URN is created with tags parsed correctly and direction specs accessible | Tests/CapDAGTests/CSCapUrnTests.m:31 |
| test002 | `test002_directionSpecsDefaultToWildcard` | TEST002: Test that missing 'in' or 'out' defaults to media: wildcard | Tests/CapDAGTests/CSCapUrnTests.m:146 |
| test003 | `test003_directionMatching` | TEST003: Test that direction specs must match exactly, different in/out types don't match, wildcard matches any | Tests/CapDAGTests/CSCapUrnTests.m:200 |
| test004 | `test004_unquotedValuesLowercased` | TEST004: Test that unquoted keys and values are normalized to lowercase | Tests/CapDAGTests/CSCapUrnTests.m:614 |
| test005 | `test005_quotedValuesPreserveCase` | TEST005: Test that quoted values preserve case while unquoted are lowercased | Tests/CapDAGTests/CSCapUrnTests.m:640 |
| test006 | `test006_quotedValueSpecialChars` | TEST006: Test that quoted values can contain special characters (semicolons, equals, spaces) | Tests/CapDAGTests/CSCapUrnTests.m:669 |
| test007 | `test007_quotedValueEscapeSequences` | TEST007: Test that escape sequences in quoted values (\" and \\) are parsed correctly | Tests/CapDAGTests/CSCapUrnTests.m:693 |
| test008 | `test008_mixedQuotedUnquoted` | TEST008: Test that mixed quoted and unquoted values in same URN parse correctly | Tests/CapDAGTests/CSCapUrnTests.m:710 |
| test009 | `test009_unterminatedQuoteError` | TEST009: Test that unterminated quote produces UnterminatedQuote error | Tests/CapDAGTests/CSCapUrnTests.m:720 |
| test010 | `test010_invalidEscapeSequenceError` | TEST010: Test that invalid escape sequences (like \n, \x) produce InvalidEscapeSequence error | Tests/CapDAGTests/CSCapUrnTests.m:729 |
| test011 | `test011_serializationSmartQuoting` | TEST011: Test that serialization uses smart quoting (no quotes for simple lowercase, quotes for special chars/uppercase) | Tests/CapDAGTests/CSCapUrnTests.m:50 |
| test012 | `test012_roundTripSimple` | TEST012: Test that simple cap URN round-trips (parse -> serialize -> parse equals original) | Tests/CapDAGTests/CSCapUrnTests.m:738 |
| test013 | `test013_roundTripQuoted` | TEST013: Test that quoted values round-trip preserving case and spaces | Tests/CapDAGTests/CSCapUrnTests.m:750 |
| test014 | `test014_roundTripEscapes` | TEST014: Test that escape sequences round-trip correctly | Tests/CapDAGTests/CSCapUrnTests.m:1288 |
| test015 | `test015_capPrefixRequired` | TEST015: Test that cap: prefix is required and case-insensitive | Tests/CapDAGTests/CSCapUrnTests.m:63 |
| test016 | `test016_trailingSemicolonEquivalence` | TEST016: Test that trailing semicolon is equivalent (same hash, same string, matches) | Tests/CapDAGTests/CSCapUrnTests.m:80 |
| test017 | `test017_tagMatching` | TEST017: Test tag matching: exact match, subset match, wildcard match, value mismatch | Tests/CapDAGTests/CSCapUrnTests.m:238 |
| test018 | `test018_matchingCaseSensitiveValues` | TEST018: Test that quoted values with different case do NOT match (case-sensitive) | Tests/CapDAGTests/CSCapUrnTests.m:1300 |
| test019 | `test019_missingTagHandling` | TEST019: Missing tag in instance causes rejection — pattern's tags are constraints | Tests/CapDAGTests/CSCapUrnTests.m:265 |
| test020 | `test020_specificity` | TEST020: Specificity is the sum of per-tag truth-table scores across in/out/y. Marker tags (bare segments and `key=*`) score 2 (must-have-any), exact `key=value` tags score 3, missing/`?` score 0, `!` scores 1. testUrn() builds "cap:in=media:void;out=media:record;textable;<tags>" so the directional baseline is: in:  media:void              -> {void=*}              -> 2 out: media:record;textable   -> {record=*, textable=*} -> 4 Total directional baseline: 6. | Tests/CapDAGTests/CSCapUrnTests.m:293 |
| test021 | `test021_builder` | TEST021: Test builder creates cap URN with correct tags and direction specs | Tests/CapDAGTests/CSCapUrnTests.m:1315 |
| test022 | `test022_builderRequiresDirection` | TEST022: Test builder requires both in_spec and out_spec | Tests/CapDAGTests/CSCapUrnTests.m:1333 |
| test023 | `test023_builderPreservesCase` | TEST023: Test builder lowercases keys but preserves value case | Tests/CapDAGTests/CSCapUrnTests.m:1361 |
| test024 | `test024_directionalAccepts` | TEST024: Directional accepts — pattern's tags are constraints, instance must satisfy | Tests/CapDAGTests/CSCapUrnTests.m:318 |
| test025 | `test025_bestMatch` | TEST025: Test find_best_match returns most specific matching cap | Tests/CapDAGTests/CSCapUrnTests.m:1375 |
| test026 | `test026_mergeAndSubset` | TEST026: Test merge combines tags from both caps, subset keeps only specified tags | Tests/CapDAGTests/CSCapUrnTests.m:465 |
| test027 | `test027_wildcardTag` | TEST027: Test with_wildcard_tag sets tag to wildcard, including in/out | Tests/CapDAGTests/CSCapUrnTests.m:437 |
| test028 | `test028_emptyCapUrnDefaultsToWildcard` | TEST028: Test empty cap URN defaults to media: wildcard | Tests/CapDAGTests/CSCapUrnTests.m:168 |
| test029 | `test029_minimalCapUrn` | TEST029: Test minimal valid cap URN has just in and out, empty tags | Tests/CapDAGTests/CSCapUrnTests.m:188 |
| test030 | `test030_extendedCharacterSupport` | TEST030: Test extended characters (forward slashes, colons) in tag values | Tests/CapDAGTests/CSCapUrnTests.m:541 |
| test031 | `test031_wildcardRestrictions` | TEST031: Test wildcard rejected in keys but accepted in values | Tests/CapDAGTests/CSCapUrnTests.m:552 |
| test032 | `test032_duplicateKeyRejection` | TEST032: Test duplicate keys are rejected with DuplicateKey error | Tests/CapDAGTests/CSCapUrnTests.m:571 |
| test033 | `test033_numericKeyRestriction` | TEST033: Test pure numeric keys rejected, mixed alphanumeric allowed, numeric values allowed | Tests/CapDAGTests/CSCapUrnTests.m:581 |
| test034 | `test034_emptyValueError` | TEST034: Test empty values are rejected | Tests/CapDAGTests/CSCapUrnTests.m:1394 |
| test035 | `test035_hasTagCaseSensitive` | TEST035: Test has_tag is case-sensitive for values, case-insensitive for keys, works for in/out | Tests/CapDAGTests/CSCapUrnTests.m:763 |
| test036 | `test036_withTagPreservesValue` | TEST036: Test with_tag preserves value case | Tests/CapDAGTests/CSCapUrnTests.m:363 |
| test037 | `test037_withTagRejectsEmptyValue` | TEST037: Test with_tag rejects empty value | Tests/CapDAGTests/CSCapUrnTests.m:1405 |
| test038 | `test038_semanticEquivalence` | TEST038: Test semantic equivalence of unquoted and quoted simple lowercase values | Tests/CapDAGTests/CSCapUrnTests.m:786 |
| test039 | `test039_getTagReturnsDirectionSpecs` | TEST039: Test get_tag returns direction specs (in/out) with case-insensitive lookup | Tests/CapDAGTests/CSCapUrnTests.m:349 |
| test040 | `test040_matchingSemantics_exactMatch` | TEST040: Matching semantics - exact match succeeds | Tests/CapDAGTests/CSCapUrnTests.m:808 |
| test041 | `test041_matchingSemantics_capMissingTag` | TEST041: Matching semantics - cap missing tag matches (implicit wildcard) | Tests/CapDAGTests/CSCapUrnTests.m:821 |
| test042 | `test042_matchingSemantics_capHasExtraTag` | TEST042: Pattern rejects instance missing required tags | Tests/CapDAGTests/CSCapUrnTests.m:834 |
| test043 | `test043_matchingSemantics_requestHasWildcard` | TEST043: Matching semantics - request wildcard matches specific cap value | Tests/CapDAGTests/CSCapUrnTests.m:845 |
| test044 | `test044_matchingSemantics_capHasWildcard` | TEST044: Matching semantics - cap wildcard matches specific request value | Tests/CapDAGTests/CSCapUrnTests.m:858 |
| test045 | `test045_matchingSemantics_valueMismatch` | TEST045: Matching semantics - value mismatch does not match | Tests/CapDAGTests/CSCapUrnTests.m:871 |
| test046 | `test046_matchingSemantics_fallbackPattern` | TEST046: Matching semantics - fallback pattern (cap missing tag = implicit wildcard) | Tests/CapDAGTests/CSCapUrnTests.m:884 |
| test047 | `test047_matchingSemantics_thumbnailVoidInput` | TEST047: Matching semantics - thumbnail fallback with void input | Tests/CapDAGTests/CSCapUrnTests.m:1415 |
| test048 | `test048_matchingSemantics_wildcardDirectionMatchesAnything` | TEST048: Matching semantics - wildcard direction matches anything | Tests/CapDAGTests/CSCapUrnTests.m:897 |
| test049 | `test049_matchingSemantics_crossDimensionIndependence` | TEST049: Non-overlapping tags — neither direction accepts | Tests/CapDAGTests/CSCapUrnTests.m:911 |
| test050 | `test050_matchingSemantics_directionMismatch` | TEST050: Matching semantics - direction mismatch prevents matching | Tests/CapDAGTests/CSCapUrnTests.m:921 |
| test054 | `test054_xv5InlineSpecRedefinitionDetected` | TEST054: XV5 - Test inline media spec redefinition of existing registry spec is detected and rejected | Tests/CapDAGTests/CSSchemaValidationTests.m:774 |
| test055 | `test055_xv5NewInlineSpecAllowed` | TEST055: XV5 - Test new inline media spec (not in registry) is allowed | Tests/CapDAGTests/CSSchemaValidationTests.m:801 |
| test056 | `test056_xv5EmptyMediaSpecsAllowed` | TEST056: XV5 - Test empty media_specs (no inline specs) passes XV5 validation | Tests/CapDAGTests/CSSchemaValidationTests.m:825 |
| test060 | `test060_wrong_prefix_fails` | TEST060: Test wrong prefix fails with InvalidPrefix error showing expected and actual prefix | Tests/CapDAGTests/CSMediaUrnTests.m:119 |
| test061 | `test061_is_binary` | TEST061: Test is_binary returns true when textable tag is absent (binary = not textable) | Tests/CapDAGTests/CSMediaUrnTests.m:130 |
| test062 | `test062_is_record` | TEST062: Test is_record returns true when record marker tag is present indicating key-value structure | Tests/CapDAGTests/CSMediaUrnTests.m:146 |
| test063 | `test063_is_scalar` | TEST063: Test is_scalar returns true when list marker tag is absent (scalar is default) | Tests/CapDAGTests/CSMediaUrnTests.m:158 |
| test064 | `test064_is_list` | TEST064: Test is_list returns true when list marker tag is present indicating ordered collection | Tests/CapDAGTests/CSMediaUrnTests.m:172 |
| test065 | `test065_is_opaque` | TEST065: Test is_opaque returns true when record marker is absent (opaque is default) | Tests/CapDAGTests/CSMediaUrnTests.m:184 |
| test066 | `test066_is_json` | TEST066: Test is_json returns true only when json marker tag is present for JSON representation | Tests/CapDAGTests/CSMediaUrnTests.m:197 |
| test067 | `test067_is_text` | TEST067: Test is_text returns true only when textable marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:207 |
| test068 | `test068_is_void` | TEST068: Test is_void returns true when void flag or type=void tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:218 |
| test071 | `test071_to_string_roundtrip` | TEST071: Test to_string roundtrip ensures serialization and deserialization preserve URN structure | Tests/CapDAGTests/CSMediaUrnTests.m:345 |
| test072 | `test072_constants_parse` | TEST072: Test all media URN constants parse successfully as valid media URNs | Tests/CapDAGTests/CSMediaUrnTests.m:356 |
| test074 | `test074_media_urn_matching` | TEST074: Test media URN conforms_to using tagged URN semantics with specific and generic requirements | Tests/CapDAGTests/CSMediaUrnTests.m:388 |
| test075 | `test075_matching` | TEST075: Test accepts with implicit wildcards where handlers with fewer tags can handle more requests | Tests/CapDAGTests/CSMediaUrnTests.m:404 |
| test076 | `test076_specificity` | TEST076: Test specificity increases with more tags for ranking conformance | Tests/CapDAGTests/CSMediaUrnTests.m:415 |
| test078 | `test078_object_does_not_conform_to_string` | TEST078: conforms_to behavior between MEDIA_OBJECT and MEDIA_STRING | Tests/CapDAGTests/CSMediaUrnTests.m:430 |
| test091 | `test091_resolve_custom_media_spec` | TEST091: Test resolving custom media URN from local media_specs takes precedence over registry | Tests/CapDAGTests/CSMediaSpecTests.m:355 |
| test092 | `test092_resolve_custom_with_schema` | TEST092: Test resolving custom record media spec with schema from local media_specs | Tests/CapDAGTests/CSMediaSpecTests.m:373 |
| test094 | `test094_local_overrides_registry` | TEST094: Test local media_specs definition overrides registry definition for same URN | Tests/CapDAGTests/CSMediaSpecTests.m:398 |
| test099 | `test099_resolved_is_binary` | TEST099: Test ResolvedMediaSpec is_binary returns true when textable tag is absent | Tests/CapDAGTests/CSMediaSpecTests.m:262 |
| test100 | `test100_resolved_is_record` | TEST100: Test ResolvedMediaSpec is_record returns true when record marker is present | Tests/CapDAGTests/CSMediaSpecTests.m:277 |
| test101 | `test101_resolved_is_scalar` | TEST101: Test ResolvedMediaSpec is_scalar returns true when list marker is absent | Tests/CapDAGTests/CSMediaSpecTests.m:293 |
| test102 | `test102_resolved_is_list` | TEST102: Test ResolvedMediaSpec is_list returns true when list marker is present | Tests/CapDAGTests/CSMediaSpecTests.m:308 |
| test103 | `test103_resolved_is_json` | TEST103: Test ResolvedMediaSpec is_json returns true when json tag is present | Tests/CapDAGTests/CSMediaSpecTests.m:323 |
| test104 | `test104_resolved_is_text` | TEST104: Test ResolvedMediaSpec is_text returns true when textable tag is present | Tests/CapDAGTests/CSMediaSpecTests.m:338 |
| test148 | `test148_capManifestCreation` | TEST148: Cap manifest construction stores name, version, channel, description, and the cap_groups verbatim. | Tests/BifaciTests/ManifestTests.swift:28 |
| test149 | `test149_capManifestWithAuthor` | TEST149: Author field round-trips through CSCapManifest.withAuthor. | Tests/BifaciTests/ManifestTests.swift:49 |
| test150 | `test150_capManifestJsonRoundtrip` | TEST150: JSON roundtrip preserves channel and cap_groups. | Tests/BifaciTests/ManifestTests.swift:63 |
| test151 | `test151_capManifestRequiredFields` | TEST151: Manifest deserialization fails when any required field is missing — including channel, which is part of the cartridge's identity. There is no fallback default; missing means broken. | Tests/BifaciTests/ManifestTests.swift:92 |
| test152 | `test152_capManifestWithMultipleCaps` | TEST152: Multiple caps across multiple cap_groups serialize and deserialize correctly, preserving group structure. | Tests/BifaciTests/ManifestTests.swift:130 |
| test153 | `test153_capManifestEmptyCapGroups` | TEST153: An empty cap_groups list round-trips without losing the channel / version envelope. | Tests/BifaciTests/ManifestTests.swift:166 |
| test154 | `test154_capManifestOptionalAuthorField` | TEST154: Optional author field on CSCapManifest is nil by default and round-trips through `withAuthor`. | Tests/BifaciTests/ManifestTests.swift:190 |
| test155 | `test155_componentMetadataAccessors` | TEST155: CSCapManifest exposes name / version / channel / description / cap_groups via its accessors. The Obj-C bridge is schema-equivalent to the Swift `Manifest` struct. | Tests/BifaciTests/ManifestTests.swift:208 |
| test163 | `test163_argumentSchemaValidationSuccess` | TEST163: Test argument schema validation succeeds with valid JSON matching schema | Tests/CapDAGTests/CSSchemaValidationTests.m:46 |
| test164 | `test164_argumentSchemaValidationFailure` | TEST164: Test argument schema validation fails with JSON missing required fields | Tests/CapDAGTests/CSSchemaValidationTests.m:87 |
| test165 | `test165_outputSchemaValidationSuccess` | TEST165: Test output schema validation succeeds with valid JSON matching schema | Tests/CapDAGTests/CSSchemaValidationTests.m:179 |
| test171 | `test171_frameTypeRoundtrip` | TEST171: Test all FrameType discriminants roundtrip through u8 conversion preserving identity | Tests/BifaciTests/FrameTests.swift:22 |
| test172 | `test172_invalidFrameType` | TEST172: Test FrameType::from_u8 returns None for values outside the valid discriminant range | Tests/BifaciTests/FrameTests.swift:32 |
| test173 | `test173_frameTypeDiscriminantValues` | TEST173: Test FrameType discriminant values match the wire protocol specification exactly | Tests/BifaciTests/FrameTests.swift:40 |
| test174 | `test174_messageIdUUID` | TEST174: Test MessageId::new_uuid generates valid UUID that roundtrips through string conversion | Tests/BifaciTests/FrameTests.swift:59 |
| test175 | `test175_messageIdUUIDUniqueness` | TEST175: Test two MessageId::new_uuid calls produce distinct IDs (no collisions) | Tests/BifaciTests/FrameTests.swift:66 |
| test176 | `test176_messageIdUintHasNoUUIDString` | TEST176: Test MessageId::Uint does not produce a UUID string, to_uuid_string returns None | Tests/BifaciTests/FrameTests.swift:73 |
| test177 | `test177_messageIdFromInvalidUUIDStr` | TEST177: Test MessageId::from_uuid_str rejects invalid UUID strings | Tests/BifaciTests/FrameTests.swift:80 |
| test178 | `test178_messageIdAsBytes` | TEST178: Test MessageId::as_bytes produces correct byte representations for Uuid and Uint variants | Tests/BifaciTests/FrameTests.swift:1248 |
| test179 | `test179_messageIdNewUUIDIsUUID` | TEST179: Test MessageId::default creates a UUID variant (not Uint) | Tests/BifaciTests/FrameTests.swift:1267 |
| test180 | `test180_helloFrame` | TEST180: Test Frame::hello without manifest produces correct HELLO frame for host side | Tests/BifaciTests/FrameTests.swift:114 |
| test181 | `test181_helloFrameWithManifest` | TEST181: Test Frame::hello_with_manifest produces HELLO with manifest bytes for cartridge side | Tests/BifaciTests/FrameTests.swift:125 |
| test182 | `test182_reqFrame` | TEST182: Test Frame::req stores cap URN, payload, and content_type correctly | Tests/BifaciTests/FrameTests.swift:141 |
| test184 | `test184_chunkFrame` | TEST184: Test Frame::chunk stores seq and payload for streaming (with stream_id) | Tests/BifaciTests/FrameTests.swift:159 |
| test185 | `test185_errFrame` | TEST185: Test Frame::err stores error code and message in metadata | Tests/BifaciTests/FrameTests.swift:173 |
| test186 | `test186_logFrame` | TEST186: Test Frame::log stores level and message in metadata | Tests/BifaciTests/FrameTests.swift:182 |
| test187 | `test187_endFrameWithPayload` | TEST187: Test Frame::end with payload sets eof and optional final payload | Tests/BifaciTests/FrameTests.swift:191 |
| test188 | `test188_endFrameWithoutPayload` | TEST188: Test Frame::end without payload still sets eof marker | Tests/BifaciTests/FrameTests.swift:200 |
| test189 | `test189_chunkWithOffset` | TEST189: Test chunk_with_offset sets offset on all chunks but len only on seq=0 (with stream_id) | Tests/BifaciTests/FrameTests.swift:209 |
| test190 | `test190_heartbeatFrame` | TEST190: Test Frame::heartbeat creates minimal frame with no payload or metadata | Tests/BifaciTests/FrameTests.swift:254 |
| test191 | `test191_errorAccessorsOnNonErrFrame` | TEST191: Test error_code and error_message return None for non-Err frame types | Tests/BifaciTests/FrameTests.swift:264 |
| test192 | `test192_logAccessorsOnNonLogFrame` | TEST192: Test log_level and log_message return None for non-Log frame types | Tests/BifaciTests/FrameTests.swift:271 |
| test193 | `test193_helloAccessorsOnNonHelloFrame` | TEST193: Test hello_max_frame and hello_max_chunk return None for non-Hello frame types | Tests/BifaciTests/FrameTests.swift:278 |
| test194 | `test194_frameNewDefaults` | TEST194: Test Frame::new sets version and defaults correctly, optional fields are None | Tests/BifaciTests/FrameTests.swift:1278 |
| test195 | `test195_frameDefaultType` | TEST195: Test Frame::default creates a Req frame (the documented default) | Tests/BifaciTests/FrameTests.swift:1303 |
| test196 | `test196_isEofWhenNil` | TEST196: Test is_eof returns false when eof field is None (unset) | Tests/BifaciTests/FrameTests.swift:286 |
| test197 | `test197_isEofWhenFalse` | TEST197: Test is_eof returns false when eof field is explicitly Some(false) | Tests/BifaciTests/FrameTests.swift:293 |
| test198 | `test198_limitsDefault` | TEST198: Test Limits::default provides the documented default values | Tests/BifaciTests/FrameTests.swift:300 |
| test199 | `test199_protocolVersionConstant` | TEST199: Test PROTOCOL_VERSION is 2 | Tests/BifaciTests/FrameTests.swift:317 |
| test200 | `test200_keyConstants` | TEST200: Test integer key constants match the protocol specification | Tests/BifaciTests/FrameTests.swift:322 |
| test201 | `test201_helloManifestBinaryData` | TEST201: Test hello_with_manifest preserves binary manifest data (not just JSON text) | Tests/BifaciTests/FrameTests.swift:339 |
| test202 | `test202_messageIdEqualityAndHash` | TEST202: Test MessageId Eq/Hash semantics: equal UUIDs are equal, different ones are not | Tests/BifaciTests/FrameTests.swift:87 |
| test203 | `test203_messageIdCrossVariantInequality` | TEST203: Test Uuid and Uint variants of MessageId are never equal even for coincidental byte values | Tests/BifaciTests/FrameTests.swift:105 |
| test204 | `test204_reqFrameEmptyPayload` | TEST204: Test Frame::req with empty payload stores Some(empty vec) not None | Tests/BifaciTests/FrameTests.swift:351 |
| test205 | `test205_encodeDecodeRoundtrip` | TEST205: Test REQ frame encode/decode roundtrip preserves all fields | Tests/BifaciTests/FrameTests.swift:360 |
| test206 | `test206_helloFrameRoundtrip` | TEST206: Test HELLO frame encode/decode roundtrip preserves max_frame, max_chunk, max_reorder_buffer | Tests/BifaciTests/FrameTests.swift:381 |
| test207 | `test207_errFrameRoundtrip` | TEST207: Test ERR frame encode/decode roundtrip preserves error code and message | Tests/BifaciTests/FrameTests.swift:394 |
| test208 | `test208_logFrameRoundtrip` | TEST208: Test LOG frame encode/decode roundtrip preserves level and message | Tests/BifaciTests/FrameTests.swift:406 |
| test210 | `test210_endFrameRoundtrip` | TEST210: Test END frame encode/decode roundtrip preserves eof marker and optional payload | Tests/BifaciTests/FrameTests.swift:420 |
| test211 | `test211_helloWithManifestRoundtrip` | TEST211: Test HELLO with manifest encode/decode roundtrip preserves manifest bytes and limits | Tests/BifaciTests/FrameTests.swift:433 |
| test212 | `test212_chunkWithOffsetRoundtrip` | TEST212: Test chunk_with_offset encode/decode roundtrip preserves offset, len, eof (with stream_id) | Tests/BifaciTests/FrameTests.swift:452 |
| test213 | `test213_heartbeatRoundtrip` | TEST213: Test heartbeat frame encode/decode roundtrip preserves ID with no extra fields | Tests/BifaciTests/FrameTests.swift:509 |
| test214 | `test214_frameIORoundtrip` | TEST214: Test write_frame/read_frame IO roundtrip through length-prefixed wire format | Tests/BifaciTests/FrameTests.swift:524 |
| test215 | `test215_multipleFrames` | TEST215: Test reading multiple sequential frames from a single buffer | Tests/BifaciTests/FrameTests.swift:543 |
| test216 | `test216_frameTooLarge` | TEST216: Test write_frame rejects frames exceeding max_frame limit | Tests/BifaciTests/FrameTests.swift:583 |
| test217 | `test217_readFrameTooLarge` | TEST217: Test read_frame rejects incoming frames exceeding the negotiated max_frame limit | Tests/BifaciTests/FrameTests.swift:602 |
| test218 | `test218_writeChunked` | TEST218: Test write_chunked splits data into chunks respecting max_chunk and reconstructs correctly Chunks from write_chunked have seq=0. SeqAssigner at the output stage assigns final seq. Chunk ordering within a stream is tracked by chunk_index (chunk_index field). | Tests/BifaciTests/FrameTests.swift:625 |
| test219 | `test219_writeChunkedEmptyData` | TEST219: Test write_chunked with empty data produces a single EOF chunk | Tests/BifaciTests/FrameTests.swift:676 |
| test220 | `test220_writeChunkedExactFit` | TEST220: Test write_chunked with data exactly equal to max_chunk produces exactly one chunk | Tests/BifaciTests/FrameTests.swift:696 |
| test221 | `test221_eofHandling` | TEST221: Test read_frame returns Ok(None) on clean EOF (empty stream) | Tests/BifaciTests/FrameTests.swift:720 |
| test222 | `test222_truncatedLengthPrefix` | TEST222: Test read_frame handles truncated length prefix (fewer than 4 bytes available) | Tests/BifaciTests/FrameTests.swift:730 |
| test223 | `test223_truncatedFrameBody` | TEST223: Test read_frame returns error on truncated frame body (length prefix says more bytes than available) | Tests/BifaciTests/FrameTests.swift:750 |
| test224 | `test224_messageIdUintRoundtrip` | TEST224: Test MessageId::Uint roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:775 |
| test225 | `test225_decodeNonMapValue` | TEST225: Test decode_frame rejects non-map CBOR values (e.g., array, integer, string) | Tests/BifaciTests/FrameTests.swift:784 |
| test226 | `test226_decodeMissingVersion` | TEST226: Test decode_frame rejects CBOR map missing required version field | Tests/BifaciTests/FrameTests.swift:799 |
| test227 | `test227_decodeInvalidFrameTypeValue` | TEST227: Test decode_frame rejects CBOR map with invalid frame_type value | Tests/BifaciTests/FrameTests.swift:817 |
| test228 | `test228_decodeMissingId` | TEST228: Test decode_frame rejects CBOR map missing required id field | Tests/BifaciTests/FrameTests.swift:835 |
| test229 | `test229_frameReaderWriterSetLimits` | TEST229: Test FrameReader/FrameWriter set_limits updates the negotiated limits | Tests/BifaciTests/FrameTests.swift:854 |
| test230 | `test230_syncHandshake` | TEST230: Test async handshake exchanges HELLO frames and negotiates minimum limits | Tests/BifaciTests/IntegrationTests.swift:450 |
| test231 | `test231_attachCartridgeFailsOnWrongFrameType` | TEST231: Test handshake fails when peer sends non-HELLO frame | Tests/BifaciTests/RuntimeTests.swift:237 |
| test232 | `test232_attachCartridgeFailsOnMissingManifest` | TEST232: Test handshake fails when cartridge HELLO is missing required manifest | Tests/BifaciTests/RuntimeTests.swift:203 |
| test233 | `test233_binaryPayloadAllByteValues` | TEST233: Test binary payload with all 256 byte values roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:870 |
| test234 | `test234_decodeGarbageBytes` | TEST234: Test decode_frame handles garbage CBOR bytes gracefully with an error | Tests/BifaciTests/FrameTests.swift:886 |
| test235 | `test235_responseChunk` | TEST235: Test ResponseChunk stores payload, seq, offset, len, and eof fields correctly | Tests/BifaciTests/FrameTests.swift:925 |
| test236 | `test236_responseChunkWithAllFields` | TEST236: Test ResponseChunk with all fields populated preserves offset, len, and eof | Tests/BifaciTests/FrameTests.swift:938 |
| test237 | `test237_cartridgeResponseSingle` | TEST237: Test CartridgeResponse::Single final_payload returns the single payload slice | Tests/BifaciTests/FrameTests.swift:950 |
| test238 | `test238_cartridgeResponseSingleEmpty` | TEST238: Test CartridgeResponse::Single with empty payload returns empty slice and empty vec | Tests/BifaciTests/FrameTests.swift:957 |
| test239 | `test239_cartridgeResponseStreaming` | TEST239: Test CartridgeResponse::Streaming concatenated joins all chunk payloads in order | Tests/BifaciTests/FrameTests.swift:964 |
| test240 | `test240_cartridgeResponseStreamingFinalPayload` | TEST240: Test CartridgeResponse::Streaming final_payload returns the last chunk's payload | Tests/BifaciTests/FrameTests.swift:975 |
| test241 | `test241_cartridgeResponseStreamingEmptyChunks` | TEST241: Test CartridgeResponse::Streaming with empty chunks vec returns empty concatenation | Tests/BifaciTests/FrameTests.swift:985 |
| test242 | `test242_cartridgeResponseStreamingLargePayload` | TEST242: Test CartridgeResponse::Streaming concatenated capacity is pre-allocated correctly for large payloads | Tests/BifaciTests/FrameTests.swift:992 |
| test243 | `test243_cartridgeHostErrorDisplay` | TEST243: Test AsyncHostError variants display correct error messages | Tests/BifaciTests/FrameTests.swift:1007 |
| test244 | `test244_cartridgeHostErrorFromFrameError` | TEST244: Test AsyncHostError::from converts CborError to Cbor variant | Tests/BifaciTests/RuntimeTests.swift:1314 |
| test245 | `test245_cartridgeHostErrorDetails` | TEST245: Test AsyncHostError::from converts io::Error to Io variant | Tests/BifaciTests/RuntimeTests.swift:1330 |
| test246 | `test246_cartridgeHostErrorVariants` | TEST246: Test AsyncHostError Clone implementation produces equal values | Tests/BifaciTests/RuntimeTests.swift:1338 |
| test247 | `test247_responseChunkStorage` | TEST247: Test ResponseChunk Clone produces independent copy with same data | Tests/BifaciTests/RuntimeTests.swift:1365 |
| test248 | `test248_registerAndFindHandler` | TEST248: Test register_op and find_handler by exact cap URN | Tests/BifaciTests/CartridgeRuntimeTests.swift:165 |
| test249 | `test249_rawHandler` | TEST249: Test register_op handler echoes bytes directly | Tests/BifaciTests/CartridgeRuntimeTests.swift:177 |
| test250 | `test250_typedHandlerRegistration` | TEST250: Test Op handler collects input and processes it | Tests/BifaciTests/CartridgeRuntimeTests.swift:479 |
| test251 | `test251_typedHandlerErrorPropagation` | TEST251: Test Op handler propagates errors through RuntimeError::Handler | Tests/BifaciTests/CartridgeRuntimeTests.swift:497 |
| test252 | `test252_findHandlerUnknownCap` | TEST252: Test find_handler returns None for unregistered cap URNs | Tests/BifaciTests/CartridgeRuntimeTests.swift:200 |
| test253 | `test253_handlerIsSendable` | TEST253: Test OpFactory can be cloned via Arc and sent across tasks (Send + Sync) | Tests/BifaciTests/CartridgeRuntimeTests.swift:509 |
| test254 | `test254_noPeerInvoker` | TEST254: Test NoPeerInvoker always returns PeerRequest error | Tests/BifaciTests/CartridgeRuntimeTests.swift:256 |
| test255 | `test255_noPeerInvokerWithArguments` | TEST255: Test NoPeerInvoker call_with_bytes also returns error | Tests/BifaciTests/CartridgeRuntimeTests.swift:271 |
| test256 | `test256_withManifestJson` | TEST256: Test CartridgeRuntime::with_manifest_json stores manifest data and parses when valid | Tests/BifaciTests/CartridgeRuntimeTests.swift:281 |
| test257 | `test257_newWithInvalidJson` | TEST257: Test CartridgeRuntime::new with invalid JSON still creates runtime (manifest is None) | Tests/BifaciTests/CartridgeRuntimeTests.swift:288 |
| test258 | `test258_withManifestStruct` | TEST258: Test CartridgeRuntime::with_manifest creates runtime with valid manifest data | Tests/BifaciTests/CartridgeRuntimeTests.swift:295 |
| test259 | `test259_extractEffectivePayloadNonCbor` | TEST259: Test extract_effective_payload with non-CBOR content_type returns raw payload unchanged | Tests/BifaciTests/CartridgeRuntimeTests.swift:305 |
| test260 | `test260_extractEffectivePayloadNoContentType` | TEST260: Test extract_effective_payload with empty content_type returns raw payload unchanged | Tests/BifaciTests/CartridgeRuntimeTests.swift:313 |
| test261 | `test261_extractEffectivePayloadCborMatch` | TEST261: Test extract_effective_payload with CBOR content extracts matching argument value | Tests/BifaciTests/CartridgeRuntimeTests.swift:321 |
| test262 | `test262_extractEffectivePayloadCborNoMatch` | TEST262: Test extract_effective_payload with CBOR content fails when no argument matches expected input | Tests/BifaciTests/CartridgeRuntimeTests.swift:345 |
| test263 | `test263_extractEffectivePayloadInvalidCbor` | TEST263: Test extract_effective_payload with invalid CBOR bytes returns deserialization error | Tests/BifaciTests/CartridgeRuntimeTests.swift:364 |
| test264 | `test264_extractEffectivePayloadCborNotArray` | TEST264: Test extract_effective_payload with CBOR non-array (e.g. map) returns error | Tests/BifaciTests/CartridgeRuntimeTests.swift:375 |
| test266 | `test266_cliFrameSenderConstruction` | TEST266: Test CliFrameSender wraps CliStreamEmitter correctly (basic construction) | Tests/BifaciTests/CartridgeRuntimeTests.swift:525 |
| test268 | `test268_runtimeErrorDisplay` | TEST268: Test RuntimeError variants display correct messages | Tests/BifaciTests/CartridgeRuntimeTests.swift:456 |
| test270 | `test270_multipleHandlers` | TEST270: Test registering multiple Op handlers for different caps and finding each independently | Tests/BifaciTests/CartridgeRuntimeTests.swift:207 |
| test271 | `test271_handlerReplacement` | TEST271: Test Op handler replacing an existing registration for the same cap URN | Tests/BifaciTests/CartridgeRuntimeTests.swift:238 |
| test272 | `test272_extractEffectivePayloadMultipleArgs` | TEST272: Test extract_effective_payload CBOR with multiple arguments selects the correct one | Tests/BifaciTests/CartridgeRuntimeTests.swift:389 |
| test273 | `test273_extractEffectivePayloadBinaryValue` | TEST273: Test extract_effective_payload with binary data in CBOR value (not just text) | Tests/BifaciTests/CartridgeRuntimeTests.swift:425 |
| test274 | `test274_capArgumentValueNew` | TEST274: Test CapArgumentValue::new stores media_urn and raw byte value | Tests/BifaciTests/CartridgeRuntimeTests.swift:551 |
| test275 | `test275_capArgumentValueFromStr` | TEST275: Test CapArgumentValue::from_str converts string to UTF-8 bytes | Tests/BifaciTests/CartridgeRuntimeTests.swift:561 |
| test276 | `test276_capArgumentValueAsStrValid` | TEST276: Test CapArgumentValue::value_as_str succeeds for UTF-8 data | Tests/BifaciTests/CartridgeRuntimeTests.swift:568 |
| test277 | `test277_capArgumentValueAsStrInvalidUtf8` | TEST277: Test CapArgumentValue::value_as_str fails for non-UTF-8 binary data | Tests/BifaciTests/CartridgeRuntimeTests.swift:574 |
| test278 | `test278_capArgumentValueEmpty` | TEST278: Test CapArgumentValue::new with empty value stores empty vec | Tests/BifaciTests/CartridgeRuntimeTests.swift:580 |
| test282 | `test282_capArgumentValueUnicode` | TEST282: Test CapArgumentValue::from_str with Unicode string preserves all characters | Tests/BifaciTests/CartridgeRuntimeTests.swift:587 |
| test283 | `test283_capArgumentValueLargeBinary` | TEST283: Test CapArgumentValue with large binary payload preserves all bytes | Tests/BifaciTests/CartridgeRuntimeTests.swift:593 |
| test284 | `test284_handshakeHostCartridge` | TEST284: Handshake exchanges HELLO frames, negotiates limits | Tests/BifaciTests/IntegrationTests.swift:50 |
| test285 | `test285_requestResponseSimple` | TEST285: Simple request-response flow (REQ → END with payload) | Tests/BifaciTests/IntegrationTests.swift:90 |
| test286 | `test286_streamingChunks` | TEST286: Streaming response with multiple CHUNK frames | Tests/BifaciTests/IntegrationTests.swift:140 |
| test287 | `test287_heartbeatFromHost` | TEST287: Host-initiated heartbeat | Tests/BifaciTests/IntegrationTests.swift:206 |
| test290 | `test290_limitsNegotiation` | TEST290: Limit negotiation picks minimum | Tests/BifaciTests/IntegrationTests.swift:252 |
| test291 | `test291_binaryPayloadRoundtrip` | TEST291: Binary payload roundtrip (all 256 byte values) | Tests/BifaciTests/IntegrationTests.swift:287 |
| test292 | `test292_messageIdUniqueness` | TEST292: Sequential requests get distinct MessageIds | Tests/BifaciTests/IntegrationTests.swift:346 |
| test293 | `test293_cartridgeRuntimeHandlerRegistration` | TEST293: Test CartridgeRuntime Op registration and lookup by exact and non-existent cap URN | Tests/BifaciTests/RuntimeTests.swift:677 |
| test299 | `test299_emptyPayloadRoundtrip` | TEST299: Empty payload request/response roundtrip | Tests/BifaciTests/IntegrationTests.swift:399 |
| test304 | `test304_media_availability_output_constant` | TEST304: Test MEDIA_AVAILABILITY_OUTPUT constant parses as valid media URN with correct tags | Tests/CapDAGTests/CSMediaUrnTests.m:442 |
| test305 | `test305_media_path_output_constant` | TEST305: Test MEDIA_PATH_OUTPUT constant parses as valid media URN with correct tags | Tests/CapDAGTests/CSMediaUrnTests.m:454 |
| test306 | `test306_availability_and_path_output_distinct` | TEST306: Test MEDIA_AVAILABILITY_OUTPUT and MEDIA_PATH_OUTPUT are distinct URNs | Tests/CapDAGTests/CSMediaUrnTests.m:466 |
| test336 | `test336_file_path_reads_file_passes_bytes` | TEST336: Single file-path arg with stdin source reads file and passes bytes to handler TEST336: Single file-path arg with stdin source reads file and passes bytes to handler. Mirrors Rust test336_file_path_reads_file_passes_bytes. | Tests/BifaciTests/CartridgeRuntimeTests.swift:708 |
| test337 | `test337_file_path_without_stdin_passes_string` | TEST337: file-path arg without stdin source passes path as string (no conversion). Mirrors Rust test337_file_path_without_stdin_passes_string. | Tests/BifaciTests/CartridgeRuntimeTests.swift:748 |
| test338 | `test338_file_path_via_cli_flag` | TEST338: file-path arg reads file via --file CLI flag. Mirrors Rust test338_file_path_via_cli_flag. | Tests/BifaciTests/CartridgeRuntimeTests.swift:778 |
| test339 | `test339_file_path_array_glob_expansion` | TEST339: A sequence-declared file-path arg (isSequence=true) expands a glob into N files and the runtime delivers them as a CBOR Array of bytes — one item per matched file. List-ness comes from the arg declaration, NOT from any `;list` URN tag. TEST339: A sequence-declared file-path arg expands a glob to N files and the runtime delivers them as a CBOR Array of bytes — one item per matched file. List-ness comes from the arg declaration, not from any `;list` URN tag. Mirrors Rust test339_file_path_array_glob_expansion. | Tests/BifaciTests/CartridgeRuntimeTests.swift:811 |
| test340 | `test340_file_not_found_clear_error` | TEST340: File not found error provides clear message | Tests/BifaciTests/CartridgeRuntimeTests.swift:846 |
| test341 | `test341_stdin_precedence_over_file_path` | TEST341: stdin takes precedence over file-path in source order. Mirrors Rust test341_stdin_precedence_over_file_path. | Tests/BifaciTests/CartridgeRuntimeTests.swift:876 |
| test342 | `test342_file_path_position_zero_reads_first_arg` | TEST342: file-path with position 0 reads first positional arg as file. Mirrors Rust test342_file_path_position_zero_reads_first_arg. | Tests/BifaciTests/CartridgeRuntimeTests.swift:906 |
| test343 | `test343_non_file_path_args_unaffected` | TEST343: Non-file-path args are not affected by file reading. Mirrors Rust test343_non_file_path_args_unaffected. | Tests/BifaciTests/CartridgeRuntimeTests.swift:933 |
| test344 | `test344_file_path_array_invalid_json_fails` | TEST344: A scalar file-path arg receiving a nonexistent path fails hard with a clear error that names the path. The runtime refuses to silently swallow user mistakes like typos or wrong directories. | Tests/BifaciTests/CartridgeRuntimeTests.swift:957 |
| test345 | `test345_file_path_array_one_file_missing_fails_hard` | TEST345: file-path arg with literal nonexistent path fails hard. Mirrors Rust test345_file_path_array_one_file_missing_fails_hard. | Tests/BifaciTests/CartridgeRuntimeTests.swift:987 |
| test346 | `test346_large_file_reads_successfully` | TEST346: Large file (1MB) reads successfully | Tests/BifaciTests/CartridgeRuntimeTests.swift:1016 |
| test347 | `test347_empty_file_reads_as_empty_bytes` | TEST347: Empty file reads as empty bytes. Mirrors Rust test347_empty_file_reads_as_empty_bytes. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1054 |
| test348 | `test348_file_path_conversion_respects_source_order` | TEST348: file-path conversion respects source order. Mirrors Rust test348_file_path_conversion_respects_source_order. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1081 |
| test349 | `test349_file_path_multiple_sources_fallback` | TEST349: file-path arg with multiple sources tries all in order | Tests/BifaciTests/CartridgeRuntimeTests.swift:1108 |
| test350 | `test350_full_cli_mode_with_file_path_integration` | TEST350: Integration test - full CLI mode invocation with file-path | Tests/BifaciTests/CartridgeRuntimeTests.swift:1140 |
| test351 | `test351_file_path_array_empty_array` | TEST351: file-path arg in CBOR mode with empty Array value returns empty. CBOR Array (not JSON) is the multi-input wire form for sequence args. Mirrors Rust test351_file_path_array_empty_array. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1182 |
| test352 | `test352_file_permission_denied_clear_error` | TEST352: file permission denied error is clear (Unix-specific) | Tests/BifaciTests/CartridgeRuntimeTests.swift:1214 |
| test353 | `test353_cbor_payload_format_consistency` | TEST353: CBOR payload format matches between CLI and CBOR mode | Tests/BifaciTests/CartridgeRuntimeTests.swift:1253 |
| test354 | `test354_glob_pattern_no_matches_fails_hard` | TEST354: Glob pattern with no matches fails hard (NO FALLBACK). Mirrors Rust test354_glob_pattern_no_matches_empty_array. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1316 |
| test355 | `test355_glob_pattern_skips_directories` | TEST355: Glob pattern skips directories. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1345 |
| test356 | `test356_multiple_glob_patterns_combined` | TEST356: Multiple glob patterns combined as CBOR Array (CBOR mode). Mirrors Rust test356_multiple_glob_patterns_combined. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1384 |
| test357 | `test357_symlinks_followed` | TEST357: Symlinks are followed when reading files | Tests/BifaciTests/CartridgeRuntimeTests.swift:1443 |
| test358 | `test358_binary_file_non_utf8` | TEST358: Binary file with non-UTF8 data reads correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1478 |
| test359 | `test359_invalid_glob_pattern_fails` | TEST359: Invalid glob pattern fails with a clear error. Mirrors Rust test359_invalid_glob_pattern_fails. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1512 |
| test360 | `test360_extract_effective_payload_with_file_data` | TEST360: Extract effective payload handles file-path data correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1540 |
| test361 | `test361_cli_mode_file_path` | TEST361: CLI mode with file path - pass file path as command-line argument | Tests/BifaciTests/CartridgeRuntimeTests.swift:1739 |
| test362 | `test362_cli_mode_piped_binary` | TEST362: CLI mode with binary piped in - pipe binary data via stdin This test simulates real-world conditions: - Pure binary data piped to stdin (NOT CBOR) - CLI mode detected (command arg present) - Cap accepts stdin source - Binary is chunked on-the-fly and accumulated - Handler receives complete CBOR payload | Tests/BifaciTests/CartridgeRuntimeTests.swift:1777 |
| test363 | `test363_cbor_mode_chunked_content` | TEST363: CBOR mode with chunked content - send file content streaming as chunks | Tests/BifaciTests/CartridgeRuntimeTests.swift:1845 |
| test364 | `test364_cbor_mode_file_path` | TEST364: CBOR mode with file path - file-path arg in CBOR mode is auto-converted to file bytes via extract_effective_payload. Mirrors Rust test364_cbor_mode_file_path. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1916 |
| test365 | `test365_streamStartFrame` | TEST365: Frame::stream_start stores request_id, stream_id, and media_urn | Tests/BifaciTests/FrameTests.swift:1025 |
| test366 | `test366_streamEndFrame` | TEST366: Frame::stream_end stores request_id and stream_id | Tests/BifaciTests/FrameTests.swift:1038 |
| test367 | `test367_streamStartWithEmptyStreamId` | TEST367: StreamStart frame with empty stream_id still constructs (validation happens elsewhere) | Tests/BifaciTests/FrameTests.swift:1051 |
| test368 | `test368_streamStartWithEmptyMediaUrn` | TEST368: StreamStart frame with empty media_urn still constructs (validation happens elsewhere) | Tests/BifaciTests/FrameTests.swift:1063 |
| test389 | `test389_streamStartRoundtrip` | TEST389: StreamStart encode/decode roundtrip preserves stream_id and media_urn | Tests/BifaciTests/FrameTests.swift:1075 |
| test390 | `test390_streamEndRoundtrip` | TEST390: StreamEnd encode/decode roundtrip preserves stream_id, no media_urn | Tests/BifaciTests/FrameTests.swift:1111 |
| test395 | `test395_build_payload_small` | TEST395: Small payload (< max_chunk) produces correct CBOR arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:1592 |
| test396 | `test396_build_payload_large` | TEST396: Large payload (> max_chunk) accumulates across chunks correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1630 |
| test397 | `test397_build_payload_empty` | TEST397: Empty reader produces valid empty CBOR arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:1660 |
| test398 | `test398_build_payload_io_error` | TEST398: IO error from reader propagates as RuntimeError::Io | Tests/BifaciTests/CartridgeRuntimeTests.swift:1718 |
| test399 | `test399_relayNotifyDiscriminantRoundtrip` | TEST399: Verify RelayNotify frame type discriminant roundtrips through u8 (value 10) | Tests/BifaciTests/FrameTests.swift:1129 |
| test400 | `test400_relayStateDiscriminantRoundtrip` | TEST400: Verify RelayState frame type discriminant roundtrips through u8 (value 11) | Tests/BifaciTests/FrameTests.swift:1137 |
| test401 | `test401_relayNotifyFactoryAndAccessors` | TEST401: Verify relay_notify factory stores manifest and limits, and accessors extract them | Tests/BifaciTests/FrameTests.swift:1145 |
| test402 | `test402_relayStateFactoryAndPayload` | TEST402: Verify relay_state factory stores resource payload in frame payload field | Tests/BifaciTests/FrameTests.swift:1171 |
| test403 | `test403_invalidFrameTypePastCancel` | TEST403: Verify from_u8 returns None for values past the last valid frame type | Tests/BifaciTests/FrameTests.swift:1181 |
| test404 | `test404_slaveSendsRelayNotifyOnConnect` | TEST404: Slave sends RelayNotify on connect (initial_notify parameter) | Tests/BifaciTests/RelayTests.swift:19 |
| test405 | `test405_masterReadsRelayNotify` | TEST405: Master reads RelayNotify and extracts manifest + limits | Tests/BifaciTests/RelayTests.swift:50 |
| test406 | `test406_slaveStoresRelayState` | TEST406: Slave stores RelayState from master | Tests/BifaciTests/RelayTests.swift:76 |
| test407 | `test407_protocolFramesPassThrough` | TEST407: Protocol frames pass through slave transparently (both directions) | Tests/BifaciTests/RelayTests.swift:104 |
| test408 | `test408_relayFramesNotForwarded` | TEST408: RelayNotify/RelayState are NOT forwarded through relay | Tests/BifaciTests/RelayTests.swift:163 |
| test409 | `test409_slaveInjectsRelayNotifyMidstream` | TEST409: Slave can inject RelayNotify mid-stream (cap change) | Tests/BifaciTests/RelayTests.swift:197 |
| test410 | `test410_masterReceivesUpdatedRelayNotify` | TEST410: Master receives updated RelayNotify (cap change callback via read_frame) | Tests/BifaciTests/RelayTests.swift:235 |
| test411 | `test411_socketCloseDetection` | TEST411: Socket close detection (both directions) | Tests/BifaciTests/RelayTests.swift:284 |
| test412 | `test412_bidirectionalConcurrentFlow` | TEST412: Bidirectional concurrent frame flow through relay | Tests/BifaciTests/RelayTests.swift:310 |
| test413 | `test413_registerCartridgeAddsToCaptable` | TEST413: Register cartridge adds entries to cap_table | Tests/BifaciTests/RuntimeTests.swift:312 |
| test414 | `test414_capabilitiesEmptyInitially` | TEST414: capabilities() returns empty JSON initially (no running cartridges) | Tests/BifaciTests/RuntimeTests.swift:320 |
| test415 | `test415_reqTriggersSpawnError` | TEST415: REQ for known cap triggers spawn attempt (verified by expected spawn error). Mirrors Rust test415_req_for_known_cap_triggers_spawn: production install layout — versioned cartridge directory with cartridge.json (carrying the channel) plus an entry-point binary that isn't executable, so spawn fails. | Tests/BifaciTests/RuntimeTests.swift:695 |
| test416 | `test416_attachCartridgeUpdatesCaps` | TEST416: Attach cartridge performs HELLO handshake, extracts manifest, updates capabilities | Tests/BifaciTests/RuntimeTests.swift:339 |
| test417 | `test417_fullPathRequestResponse` | TEST417: Route REQ to correct cartridge by cap_urn (with two attached cartridges) | Tests/BifaciTests/RuntimeTests.swift:369 |
| test418 | `test418_routeContinuationByReqId` | TEST418: Route STREAM_START/CHUNK/STREAM_END/END by req_id (not cap_urn) Verifies that after the initial REQ→cartridge routing, all subsequent continuation frames with the same req_id are routed to the same cartridge — even though no cap_urn is present on those frames. | Tests/BifaciTests/RuntimeTests.swift:735 |
| test419 | `test419_heartbeatHandledLocally` | TEST419: Cartridge HEARTBEAT handled locally (not forwarded to relay) | Tests/BifaciTests/RuntimeTests.swift:445 |
| test420 | `test420_cartridgeFramesForwardedToRelay` | TEST420: Cartridge non-HELLO/non-HB frames forwarded to relay (pass-through) | Tests/BifaciTests/RuntimeTests.swift:821 |
| test421 | `test421_cartridgeDeathUpdatesCaps` | TEST421: Cartridge death updates capability list (caps removed) | Tests/BifaciTests/RuntimeTests.swift:895 |
| test422 | `test422_cartridgeDeathSendsErr` | TEST422: Cartridge death sends ERR for all pending requests via relay | Tests/BifaciTests/RuntimeTests.swift:947 |
| test423 | `test423_multipleCartridgesRouteIndependently` | TEST423: Multiple cartridges registered with distinct caps route independently | Tests/BifaciTests/RuntimeTests.swift:522 |
| test424 | `test424_concurrentRequestsSameCartridge` | TEST424: Concurrent requests to the same cartridge are handled independently | Tests/BifaciTests/RuntimeTests.swift:1014 |
| test425 | `test425_findCartridgeForCapUnknown` | TEST425: find_cartridge_for_cap returns None for unregistered cap | Tests/BifaciTests/RuntimeTests.swift:329 |
| test426 | `test426_single_master_req_response` | TEST426: Single master REQ/response routing | Tests/BifaciTests/RelaySwitchTests.swift:80 |
| test427 | `test427_multi_master_cap_routing` | TEST427: Multi-master cap routing | Tests/BifaciTests/RelaySwitchTests.swift:139 |
| test428 | `test428_unknown_cap_returns_error` | TEST428: Unknown cap returns error | Tests/BifaciTests/RelaySwitchTests.swift:234 |
| test429 | `test429_find_master_for_cap` | TEST429: Cap routing logic (find_master_for_cap) | Tests/BifaciTests/RelaySwitchTests.swift:275 |
| test430 | `test430_tie_breaking_same_cap_multiple_masters` | TEST430: Tie-breaking (same cap on multiple masters - first match wins, routing is consistent) | Tests/BifaciTests/RelaySwitchTests.swift:320 |
| test431 | `test431_continuation_frame_routing` | TEST431: Continuation frame routing (CHUNK, END follow REQ) | Tests/BifaciTests/RelaySwitchTests.swift:401 |
| test432 | `test432_empty_masters_allowed` | TEST432: Empty masters list creates empty switch, add_master works | Tests/BifaciTests/RelaySwitchTests.swift:466 |
| test433 | `test433_capability_aggregation_deduplicates` | TEST433: Capability aggregation deduplicates caps | Tests/BifaciTests/RelaySwitchTests.swift:483 |
| test434 | `test434_limits_negotiation_minimum` | TEST434: Limits negotiation takes minimum | Tests/BifaciTests/RelaySwitchTests.swift:538 |
| test435 | `test435_urn_matching_exact_and_accepts` | TEST435: URN matching (exact vs accepts()) Dispatch is contravariant on input (request input must conform to provider input — i.e. request can be more specific) and covariant on output (provider output must conform to request output — i.e. provider can be more specific). A request whose input is in a different type family than any registered provider has no handler. | Tests/BifaciTests/RelaySwitchTests.swift:588 |
| test436 | `test436_computeChecksum` | TEST436: Verify FNV-1a checksum function produces consistent results | Tests/BifaciTests/FrameTests.swift:1310 |
| test437 | `test437_preferredCapRoutesToExactMatch` | TEST437: find_master_for_cap with preferred_cap routes to generic handler With is_dispatchable semantics: - Generic provider (in=media:) CAN dispatch specific request (in="media:pdf") because media: (wildcard) accepts any input type - Preference routes to preferred among dispatchable candidates | Tests/BifaciTests/RelaySwitchTests.swift:662 |
| test438 | `test438_preferredCapExactMatch` | TEST438: find_master_for_cap with preference falls back to closest-specificity when preferred cap is not in the comparable set | Tests/BifaciTests/RelaySwitchTests.swift:702 |
| test439 | `test439_specificRequestNoMatchingHandler` | TEST439: Generic provider CAN dispatch specific request (but only matches if no more specific provider exists) With is_dispatchable: generic provider (in=media:) CAN handle specific request (in="media:pdf") because media: accepts any input type. With preference, can route to generic even when more specific exists. | Tests/BifaciTests/RelaySwitchTests.swift:742 |
| test440 | `test440_chunkIndexChecksumRoundtrip` | TEST440: CHUNK frame with chunk_index and checksum roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:1334 |
| test441 | `test441_streamEndChunkCountRoundtrip` | TEST441: STREAM_END frame with chunk_count roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:1352 |
| test442 | `test442_seqAssignerMonotonicSameRid` | TEST442: SeqAssigner assigns seq 0,1,2,3 for consecutive frames with same RID | Tests/BifaciTests/FlowOrderingTests.swift:11 |
| test443 | `test443_seqAssignerIndependentRids` | TEST443: SeqAssigner maintains independent counters for different RIDs | Tests/BifaciTests/FlowOrderingTests.swift:32 |
| test444 | `test444_seqAssignerSkipsNonFlow` | TEST444: SeqAssigner skips non-flow frames (Heartbeat, RelayNotify, RelayState, Hello) | Tests/BifaciTests/FlowOrderingTests.swift:57 |
| test445 | `test445_seqAssignerRemoveByFlowKey` | TEST445: SeqAssigner.remove with FlowKey(rid, None) resets that flow; FlowKey(rid, Some(xid)) is unaffected | Tests/BifaciTests/FlowOrderingTests.swift:77 |
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
| test461 | `test461_writeChunkedSeqZero` | TEST461: write_chunked produces frames with seq=0; SeqAssigner assigns at output stage | Tests/BifaciTests/FlowOrderingTests.swift:427 |
| test472 | `test472_handshakeNegotiatesReorderBuffer` | TEST472: Handshake negotiates max_reorder_buffer (minimum of both sides) | Tests/BifaciTests/FlowOrderingTests.swift:457 |
| test473 | `test473_capDiscardParsesAsValidCapUrn` | TEST473: CAP_DISCARD parses as valid CapUrn with in=media: and out=media:void | Tests/BifaciTests/StandardCapsTests.swift:14 |
| test474 | `test474_capDiscardAcceptsVoidOutputCaps` | TEST474: CAP_DISCARD accepts specific-input/void-output caps | Tests/BifaciTests/StandardCapsTests.swift:23 |
| test475 | `test475_manifestValidatePassesWithIdentity` | TEST475: CapManifest::validate() passes when CAP_IDENTITY is present | Tests/BifaciTests/StandardCapsTests.swift:41 |
| test476 | `test476_manifestValidateFailsWithoutIdentity` | TEST476: CapManifest::validate() fails when CAP_IDENTITY is missing | Tests/BifaciTests/StandardCapsTests.swift:56 |
| test478 | `test478_cartridgeRuntimeAutoRegistersIdentity` | TEST478: CartridgeRuntime auto-registers identity and discard handlers on construction | Tests/BifaciTests/StandardCapsTests.swift:95 |
| test479 | `test479_identityHandlerEchoesInput` | TEST479: Custom identity Op overrides auto-registered default | Tests/BifaciTests/StandardCapsTests.swift:110 |
| test480 | `test480_discardHandlerConsumesInput` | TEST480: parse_caps_from_manifest rejects manifest without CAP_IDENTITY | Tests/BifaciTests/StandardCapsTests.swift:178 |
| test481 | `test481_verifyIdentitySucceeds` | TEST481: verify_identity succeeds with standard identity echo handler | Tests/BifaciTests/IntegrationTests.swift:497 |
| test482 | `test482_verifyIdentityFailsOnErr` | TEST482: verify_identity fails when cartridge returns ERR on identity call | Tests/BifaciTests/IntegrationTests.swift:584 |
| test483 | `test483_verifyIdentityFailsOnClose` | TEST483: verify_identity fails when connection closes before response | Tests/BifaciTests/IntegrationTests.swift:927 |
| test485 | `test485_attachCartridgeIdentityVerificationSucceeds` | TEST485: attach_cartridge completes identity verification with working cartridge | Tests/BifaciTests/RuntimeTests.swift:1385 |
| test486 | `test486_attachCartridgeIdentityVerificationFails` | TEST486: attach_cartridge rejects cartridge that fails identity verification | Tests/BifaciTests/RuntimeTests.swift:1458 |
| test487 | `test487_relaySwitchIdentityVerificationSucceeds` | TEST487: RelaySwitch construction verifies identity through relay chain | Tests/BifaciTests/RelaySwitchTests.swift:780 |
| test488 | `test488_relaySwitchIdentityVerificationFails` | TEST488: RelaySwitch construction fails when master's identity verification fails | Tests/BifaciTests/RelaySwitchTests.swift:809 |
| test489 | `test489_addMasterDynamic` | TEST489: add_master dynamically connects new host to running switch | Tests/BifaciTests/RelaySwitchTests.swift:843 |
| test490 | `test490_identityVerificationMultipleCartridges` | TEST490: Identity verification with multiple cartridges through single relay Both cartridges must pass identity verification independently before any real requests are routed. | Tests/BifaciTests/RuntimeTests.swift:1512 |
| test491 | `test491_chunkRequiresChunkIndexAndChecksum` | TEST491: Frame::chunk constructor requires and sets chunk_index and checksum | Tests/BifaciTests/FrameTests.swift:1366 |
| test492 | `test492_streamEndRequiresChunkCount` | TEST492: Frame::stream_end constructor requires and sets chunk_count | Tests/BifaciTests/FrameTests.swift:1378 |
| test493 | `test493_computeChecksumFnv1aTestVectors` | TEST493: compute_checksum produces correct FNV-1a hash for known test vectors | Tests/BifaciTests/FrameTests.swift:1387 |
| test494 | `test494_computeChecksumDeterministic` | TEST494: compute_checksum is deterministic | Tests/BifaciTests/FrameTests.swift:1405 |
| test495 | `test495_cborRejectsChunkWithoutChunkIndex` | TEST495: CBOR decode REJECTS CHUNK frame missing chunk_index field | Tests/BifaciTests/FrameTests.swift:1417 |
| test496 | `test496_cborRejectsChunkWithoutChecksum` | TEST496: CBOR decode REJECTS CHUNK frame missing checksum field | Tests/BifaciTests/FrameTests.swift:1441 |
| test497 | `test497_chunkCorruptedPayloadRejected` | TEST497: Verify CHUNK frame with corrupted payload is rejected by checksum | Tests/BifaciTests/FrameTests.swift:1465 |
| test498 | `test498_routingIdCborRoundtrip` | TEST498: routing_id field roundtrips through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1481 |
| test499 | `test499_chunkIndexChecksumCborRoundtrip` | TEST499: chunk_index and checksum roundtrip through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1495 |
| test500 | `test500_chunkCountCborRoundtrip` | TEST500: chunk_count roundtrips through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1510 |
| test501 | `test501_frameNewInitializesOptionalFieldsNone` | TEST501: Frame::new initializes new fields to None | Tests/BifaciTests/FrameTests.swift:1522 |
| test502 | `test502_keysModuleNewFieldConstants` | TEST502: Keys module has constants for new fields | Tests/BifaciTests/FrameTests.swift:1532 |
| test503 | `test503_computeChecksumEmptyData` | TEST503: compute_checksum handles empty data correctly | Tests/BifaciTests/FrameTests.swift:1540 |
| test504 | `test504_computeChecksumLargePayload` | TEST504: compute_checksum handles large payloads without overflow | Tests/BifaciTests/FrameTests.swift:1548 |
| test505 | `test505_chunkWithOffsetSetsChunkIndex` | TEST505: chunk_with_offset sets chunk_index correctly | Tests/BifaciTests/FrameTests.swift:1559 |
| test506 | `test506_computeChecksumDifferentDataDifferentHash` | TEST506: Different data produces different checksums | Tests/BifaciTests/FrameTests.swift:1582 |
| test507 | `test507_reorderBufferXidIsolation` | TEST507: ReorderBuffer isolates flows by XID (routing_id) - same RID different XIDs | Tests/BifaciTests/FlowOrderingTests.swift:496 |
| test508 | `test508_reorderBufferDuplicateBufferedSeq` | TEST508: ReorderBuffer rejects duplicate seq already in buffer | Tests/BifaciTests/FlowOrderingTests.swift:519 |
| test509 | `test509_reorderBufferLargeGapRejected` | TEST509: ReorderBuffer handles large seq gaps without DOS | Tests/BifaciTests/FlowOrderingTests.swift:540 |
| test510 | `test510_reorderBufferMultipleGaps` | TEST510: ReorderBuffer with multiple interleaved gaps fills correctly | Tests/BifaciTests/FlowOrderingTests.swift:565 |
| test511 | `test511_reorderBufferRejectsStaleSeq` | TEST511: ReorderBuffer cleanup with buffered frames discards them | Tests/BifaciTests/FlowOrderingTests.swift:591 |
| test512 | `test512_reorderBufferNonFlowFramesBypass` | TEST512: ReorderBuffer delivers burst of consecutive buffered frames | Tests/BifaciTests/FlowOrderingTests.swift:614 |
| test513 | `test513_reorderBufferCleanup` | TEST513: ReorderBuffer different frame types in same flow maintain order | Tests/BifaciTests/FlowOrderingTests.swift:635 |
| test514 | `test514_reorderBufferRespectsMaxBuffer` | TEST514: ReorderBuffer with XID cleanup doesn't affect different XID | Tests/BifaciTests/FlowOrderingTests.swift:653 |
| test515 | `test515_seqAssignerRemoveByFlowKey` | TEST515: ReorderBuffer overflow error includes diagnostic information | Tests/BifaciTests/FlowOrderingTests.swift:678 |
| test516 | `test516_seqAssignerIndependentFlowsByXid` | TEST516: ReorderBuffer stale error includes diagnostic information | Tests/BifaciTests/FlowOrderingTests.swift:701 |
| test517 | `test517_flowKeyNilXidSeparate` | TEST517: FlowKey with None XID differs from Some(xid) | Tests/BifaciTests/FlowOrderingTests.swift:733 |
| test518 | `test518_reorderBufferFlowCleanupAfterEnd` | TEST518: ReorderBuffer handles zero-length ready vec correctly | Tests/BifaciTests/FlowOrderingTests.swift:764 |
| test519 | `test519_reorderBufferMultipleRids` | TEST519: ReorderBuffer state persists across accept calls | Tests/BifaciTests/FlowOrderingTests.swift:786 |
| test520 | `test520_reorderBufferDrainsBufferedFrames` | TEST520: ReorderBuffer max_buffer_per_flow is per-flow not global | Tests/BifaciTests/FlowOrderingTests.swift:808 |
| test521 | `test521_relayNotifyCborRoundtrip` | TEST521: RelayNotify CBOR roundtrip preserves manifest and limits | Tests/BifaciTests/FrameTests.swift:1187 |
| test522 | `test522_relayStateCborRoundtrip` | TEST522: RelayState CBOR roundtrip preserves payload | Tests/BifaciTests/FrameTests.swift:1208 |
| test523 | `test523_relayNotifyNotFlowFrame` | TEST523: is_flow_frame returns false for RelayNotify | Tests/BifaciTests/FrameTests.swift:1597 |
| test524 | `test524_relayStateNotFlowFrame` | TEST524: is_flow_frame returns false for RelayState | Tests/BifaciTests/FrameTests.swift:1603 |
| test525 | `test525_relayNotifyEmptyManifest` | TEST525: RelayNotify with empty manifest is valid | Tests/BifaciTests/FrameTests.swift:1609 |
| test526 | `test526_relayStateEmptyPayload` | TEST526: RelayState with empty payload is valid | Tests/BifaciTests/FrameTests.swift:1620 |
| test527 | `test527_relayNotifyLargeManifest` | TEST527: RelayNotify with large manifest roundtrips correctly | Tests/BifaciTests/FrameTests.swift:1631 |
| test528 | `test528_relayFramesUseUintZeroId` | TEST528: RelayNotify and RelayState use MessageId::Uint(0) | Tests/BifaciTests/FrameTests.swift:1643 |
| test529 | `test529_inputStreamIteratorOrder` | TEST529: InputStream recv yields chunks in order | Tests/BifaciTests/StreamingAPITests.swift:20 |
| test530 | `test530_inputStreamCollectBytes` | TEST530: InputStream::collect_bytes concatenates byte chunks | Tests/BifaciTests/StreamingAPITests.swift:57 |
| test531 | `test531_inputStreamCollectBytesText` | TEST531: InputStream::collect_bytes handles text chunks | Tests/BifaciTests/StreamingAPITests.swift:79 |
| test532 | `test532_inputStreamEmpty` | TEST532: InputStream empty stream produces empty bytes | Tests/BifaciTests/StreamingAPITests.swift:101 |
| test533 | `test533_inputStreamErrorPropagation` | TEST533: InputStream propagates errors | Tests/BifaciTests/StreamingAPITests.swift:119 |
| test534 | `test534_inputStreamMediaUrn` | TEST534: InputStream::media_urn returns correct URN | Tests/BifaciTests/StreamingAPITests.swift:146 |
| test535 | `test535_inputPackageIteration` | TEST535: InputPackage recv yields streams | Tests/BifaciTests/StreamingAPITests.swift:156 |
| test536 | `test536_inputPackageCollectAllBytes` | TEST536: InputPackage::collect_all_bytes aggregates all streams | Tests/BifaciTests/StreamingAPITests.swift:202 |
| test537 | `test537_inputPackageEmpty` | TEST537: InputPackage empty package produces empty bytes | Tests/BifaciTests/StreamingAPITests.swift:243 |
| test538 | `test538_inputPackageErrorPropagation` | TEST538: InputPackage propagates stream errors | Tests/BifaciTests/StreamingAPITests.swift:261 |
| test539 | `test539_outputStreamSendsStreamStart` | TEST539: OutputStream sends STREAM_START on first write | Tests/BifaciTests/StreamingAPITests.swift:289 |
| test540 | `test540_outputStreamCloseSendsStreamEnd` | TEST540: OutputStream::close sends STREAM_END with correct chunk_count | Tests/BifaciTests/StreamingAPITests.swift:319 |
| test541 | `test541_outputStreamChunksLargeData` | TEST541: OutputStream chunks large data correctly | Tests/BifaciTests/StreamingAPITests.swift:350 |
| test542 | `test542_outputStreamCloseWithoutStartIsNoop` | TEST542: OutputStream empty stream sends STREAM_START and STREAM_END only | Tests/BifaciTests/StreamingAPITests.swift:385 |
| test543 | `test543_peerCallArgCreatesStream` | TEST543: PeerCall::arg creates OutputStream with correct stream_id | Tests/BifaciTests/StreamingAPITests.swift:490 |
| test544 | `test544_peerCallFinishSendsEnd` | TEST544: PeerCall::finish sends END frame | Tests/BifaciTests/StreamingAPITests.swift:519 |
| test545 | `test545_peerCallFinishReturnsPeerResponse` | TEST545: PeerCall::finish returns PeerResponse with data | Tests/BifaciTests/StreamingAPITests.swift:541 |
| test546 | `test546_is_image` | TEST546: is_image returns true only when image marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:225 |
| test547 | `test547_is_audio` | TEST547: is_audio returns true only when audio marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:237 |
| test548 | `test548_is_video` | TEST548: is_video returns true only when video marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:248 |
| test549 | `test549_is_numeric` | TEST549: is_numeric returns true only when numeric marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:258 |
| test550 | `test550_is_bool` | TEST550: is_bool returns true only when bool marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:270 |
| test551 | `test551_is_file_path` | TEST551: isFilePath returns true for the single file-path media URN, false for everything else. There is no "array" variant — cardinality is carried by is_sequence on the wire, not by URN tags. | Tests/CapDAGTests/CSMediaUrnTests.m:284 |
| test555 | `test555_with_tag_and_without_tag` | TEST555: with_tag adds a tag and without_tag removes it | Tests/CapDAGTests/CSMediaUrnTests.m:292 |
| test558 | `test558_predicate_constant_consistency` | TEST558: predicates are consistent with constants — every constant triggers exactly the expected predicates | Tests/CapDAGTests/CSMediaUrnTests.m:310 |
| test638 | `test638_noPeerRouterRejectsAll` | TEST638: Verify NoPeerRouter rejects all requests with PeerInvokeNotSupported | Tests/BifaciTests/RouterTests.swift:14 |
| test654 | `test654_routesReqToHandler` | TEST654: InProcessCartridgeHost routes REQ to matching handler and returns response | Tests/BifaciTests/InProcessCartridgeHostTests.swift:104 |
| test655 | `test655_identityVerification` | TEST655: InProcessCartridgeHost handles identity verification (echo nonce) | Tests/BifaciTests/InProcessCartridgeHostTests.swift:188 |
| test656 | `test656_noHandlerReturnsErr` | TEST656: InProcessCartridgeHost returns NO_HANDLER for unregistered cap | Tests/BifaciTests/InProcessCartridgeHostTests.swift:249 |
| test657 | `test657_manifestIncludesAllCaps` | TEST657: InProcessCartridgeHost manifest includes identity cap and handler caps | Tests/BifaciTests/InProcessCartridgeHostTests.swift:291 |
| test658 | `test658_heartbeatResponse` | TEST658: InProcessCartridgeHost handles heartbeat by echoing same ID | Tests/BifaciTests/InProcessCartridgeHostTests.swift:314 |
| test659 | `test659_handlerErrorReturnsErrFrame` | TEST659: InProcessCartridgeHost handler error returns ERR frame | Tests/BifaciTests/InProcessCartridgeHostTests.swift:348 |
| test660 | `test660_closestSpecificityRouting` | TEST660: InProcessCartridgeHost closest-specificity routing prefers specific over identity | Tests/BifaciTests/InProcessCartridgeHostTests.swift:394 |
| test661 | `test661_cartridgeDeathKeepsKnownCapsAdvertised` | TEST661: Cartridge death keeps known_caps advertised for on-demand respawn. Identity is the gating filter for advertisement; we provision a real cartridge directory with a valid `cartridge.json` so the cartridge has a resolvable identity. cap_table routes regardless of identity (in-process / attached cartridges still need to be dispatchable), but the relay payload only advertises cartridges with identity records. | Tests/BifaciTests/RuntimeTests.swift:1128 |
| test662 | `test662_rebuildCapabilitiesIncludesNonRunningCartridges` | TEST662: rebuild_capabilities includes non-running cartridges' caps. cap_groups is the source of truth and advertisement does not gate on `running` — only on identity (cartridge.json present) and on `helloFailed`. | Tests/BifaciTests/RuntimeTests.swift:1153 |
| test663 | `test663_helloFailedCartridgeRemovedFromCapabilities` | TEST663: Cartridge with hello_failed is permanently removed from capabilities | Tests/BifaciTests/RuntimeTests.swift:1178 |
| test664 | `test664_runningCartridgeUsesManifestCaps` | TEST664: Running cartridge uses manifest caps, not known_caps | Tests/BifaciTests/RuntimeTests.swift:1217 |
| test665 | `test665_capTableMixedRunningAndNonRunning` | TEST665: Cap table aggregates caps from every healthy cartridge — attached/running cartridges contribute their post-HELLO cap_groups; registered-but-not-yet-spawned cartridges contribute their probe-time cap_groups. Both flow through the same `cap_urns()` view derived from cap_groups. | Tests/BifaciTests/RuntimeTests.swift:1260 |
| test667 | `test667_verifyChunkChecksumDetectsCorruption` | TEST667: verify_chunk_checksum detects corrupted payload | Tests/BifaciTests/FrameTests.swift:1220 |
| test678 | `test678_findStreamEquivalentUrnDifferentTagOrder` | TEST678: find_stream with exact equivalent URN (same tags, different order) succeeds | Tests/BifaciTests/StreamingAPITests.swift:578 |
| test679 | `test679_findStreamBaseUrnDoesNotMatchFullUrn` | TEST679: find_stream with base URN vs full URN fails — is_equivalent is strict This is the root cause of the cartridge_client.rs bug. Sender sent "media:llm-generation-request" but receiver looked for "media:llm-generation-request;json;record". | Tests/BifaciTests/StreamingAPITests.swift:591 |
| test680 | `test680_requireStreamMissingUrnReturnsError` | TEST680: require_stream with missing URN returns hard StreamError | Tests/BifaciTests/StreamingAPITests.swift:602 |
| test681 | `test681_findStreamMultipleStreamsReturnsCorrect` | TEST681: find_stream with multiple streams returns the correct one | Tests/BifaciTests/StreamingAPITests.swift:617 |
| test682 | `test682_requireStreamStrReturnsUtf8` | TEST682: require_stream_str returns UTF-8 string for text data | Tests/BifaciTests/StreamingAPITests.swift:635 |
| test683 | `test683_findStreamInvalidUrnReturnsNone` | TEST683: find_stream returns None for invalid media URN string (not a parse error — just None) | Tests/BifaciTests/StreamingAPITests.swift:645 |
| test688 | `test688_is_multiple` | TEST688: Tests is_multiple method correctly identifies multi-value cardinalities Verifies Single returns false while Sequence and AtLeastOne return true | Tests/CapDAGTests/CSCardinalityTests.m:22 |
| test689 | `test689_accepts_single` | TEST689: Tests accepts_single method identifies cardinalities that accept single values Verifies Single and AtLeastOne accept singles while Sequence does not | Tests/CapDAGTests/CSCardinalityTests.m:30 |
| test690 | `test690_compatibility_single_to_single` | TEST690: Tests cardinality compatibility for single-to-single data flow Verifies Direct compatibility when both input and output are Single | Tests/CapDAGTests/CSCardinalityTests.m:40 |
| test691 | `test691_compatibility_single_to_vector` | TEST691: Tests cardinality compatibility when wrapping single value into array Verifies WrapInArray compatibility when Sequence expects Single input | Tests/CapDAGTests/CSCardinalityTests.m:47 |
| test692 | `test692_compatibility_vector_to_single` | TEST692: Tests cardinality compatibility when unwrapping array to singles Verifies RequiresFanOut compatibility when Single expects Sequence input | Tests/CapDAGTests/CSCardinalityTests.m:54 |
| test693 | `test693_compatibility_vector_to_vector` | TEST693: Tests cardinality compatibility for sequence-to-sequence data flow Verifies Direct compatibility when both input and output are Sequence | Tests/CapDAGTests/CSCardinalityTests.m:61 |
| test697 | `test697_cap_shape_info_one_to_one` | TEST697: Tests CapShapeInfo correctly identifies one-to-one pattern Verifies Single input and Single output result in OneToOne pattern | Tests/CapDAGTests/CSCardinalityTests.m:70 |
| test698 | `test698_cap_shape_info_cardinality_always_single_from_urn` | TEST698: CapShapeInfo cardinality is always Single when derived from URN Cardinality comes from context (is_sequence), not from URN tags. The list tag is a semantic type property, not a cardinality indicator. | Tests/CapDAGTests/CSCardinalityTests.m:80 |
| test699 | `test699_cap_shape_info_list_urn_still_single_cardinality` | TEST699: CapShapeInfo cardinality from URN is always Single; ManyToOne requires is_sequence | Tests/CapDAGTests/CSCardinalityTests.m:88 |
| test709 | `test709_pattern_produces_vector` | TEST709: Tests CardinalityPattern correctly identifies patterns that produce vectors Verifies OneToMany and ManyToMany return true, others return false | Tests/CapDAGTests/CSCardinalityTests.m:110 |
| test710 | `test710_pattern_requires_vector` | TEST710: Tests CardinalityPattern correctly identifies patterns that require vectors Verifies ManyToOne and ManyToMany return true, others return false | Tests/CapDAGTests/CSCardinalityTests.m:119 |
| test711 | `test711_strand_shape_analysis_simple_linear` | TEST711: Tests shape chain analysis for simple linear one-to-one capability chains Verifies chains with no fan-out are valid and require no transformation | Tests/CapDAGTests/CSCardinalityTests.m:130 |
| test712 | `test712_strand_shape_analysis_with_fan_out` | TEST712: Tests shape chain analysis detects fan-out points in capability chains Fan-out requires is_sequence=true on the cap's output, not a "list" URN tag | Tests/CapDAGTests/CSCardinalityTests.m:143 |
| test713 | `test713_strand_shape_analysis_empty` | TEST713: Tests shape chain analysis handles empty capability chains correctly Verifies empty chains are valid and require no transformation | Tests/CapDAGTests/CSCardinalityTests.m:160 |
| test714 | `test714_cardinality_serialization` | TEST714: Tests InputCardinality enum values are distinct (parity for Rust serde round-trip) | Tests/CapDAGTests/CSCardinalityTests.m:172 |
| test715 | `test715_pattern_serialization` | TEST715: Tests CardinalityPattern enum values are distinct (parity for Rust serde round-trip) | Tests/CapDAGTests/CSCardinalityTests.m:179 |
| test720 | `test720_from_media_urn_opaque` | TEST720: Tests InputStructure correctly identifies opaque media URNs Verifies that URNs without record marker are parsed as Opaque | Tests/CapDAGTests/CSCardinalityTests.m:192 |
| test721 | `test721_from_media_urn_record` | TEST721: Tests InputStructure correctly identifies record media URNs Verifies that URNs with record marker tag are parsed as Record | Tests/CapDAGTests/CSCardinalityTests.m:202 |
| test722 | `test722_structure_compatibility_opaque_to_opaque` | TEST722: Tests structure compatibility for opaque-to-opaque data flow | Tests/CapDAGTests/CSCardinalityTests.m:211 |
| test723 | `test723_structure_compatibility_record_to_record` | TEST723: Tests structure compatibility for record-to-record data flow | Tests/CapDAGTests/CSCardinalityTests.m:217 |
| test724 | `test724_structure_incompatibility_opaque_to_record` | TEST724: Tests structure incompatibility for opaque-to-record flow | Tests/CapDAGTests/CSCardinalityTests.m:223 |
| test725 | `test725_structure_incompatibility_record_to_opaque` | TEST725: Tests structure incompatibility for record-to-opaque flow | Tests/CapDAGTests/CSCardinalityTests.m:229 |
| test726 | `test726_apply_structure_add_record` | TEST726: Tests applying Record structure adds record marker to URN | Tests/CapDAGTests/CSCardinalityTests.m:235 |
| test727 | `test727_apply_structure_remove_record` | TEST727: Tests applying Opaque structure removes record marker from URN | Tests/CapDAGTests/CSCardinalityTests.m:241 |
| test730 | `test730_media_shape_from_urn_all_combinations` | TEST730: Tests MediaShape correctly parses all four combinations Cardinality is always Single from URN — comes from context, not URN tags | Tests/CapDAGTests/CSCardinalityTests.m:250 |
| test731 | `test731_media_shape_compatible_direct` | TEST731: Tests MediaShape compatibility for matching shapes | Tests/CapDAGTests/CSCardinalityTests.m:273 |
| test732 | `test732_media_shape_cardinality_changes` | TEST732: Tests MediaShape compatibility for cardinality changes with matching structure | Tests/CapDAGTests/CSCardinalityTests.m:287 |
| test733 | `test733_media_shape_structure_mismatch` | TEST733: Tests MediaShape incompatibility when structures don't match | Tests/CapDAGTests/CSCardinalityTests.m:303 |
| test740 | `test740_cap_shape_info_from_specs` | TEST740: Tests CapShapeInfo correctly parses cap specs | Tests/CapDAGTests/CSCardinalityTests.m:323 |
| test741 | `test741_cap_shape_info_pattern` | TEST741: Tests CapShapeInfo pattern detection — OneToMany requires output is_sequence=true | Tests/CapDAGTests/CSCardinalityTests.m:334 |
| test750 | `test750_strand_shape_valid` | TEST750: Tests shape chain analysis for valid chain with matching structures | Tests/CapDAGTests/CSCardinalityTests.m:346 |
| test751 | `test751_strand_shape_structure_mismatch` | TEST751: Tests shape chain analysis detects structure mismatch | Tests/CapDAGTests/CSCardinalityTests.m:357 |
| test752 | `test752_strand_shape_with_fanout` | TEST752: Tests shape chain analysis with fan-out (matching structures) Fan-out requires output is_sequence=true on the disbind cap | Tests/CapDAGTests/CSCardinalityTests.m:371 |
| test753 | `test753_strand_shape_list_record_to_list_record` | TEST753: Tests shape chain analysis correctly handles list-to-list record flow | Tests/CapDAGTests/CSCardinalityTests.m:387 |
| test754 | `test754_extractPrefixNonexistent` | TEST754: extractPrefixTo with nonexistent node returns error | Tests/CapDAGTests/CSPlanDecompositionTests.m:135 |
| test755 | `test755_extractForeachBody` | TEST755: extractForeachBody extracts body with synthetic I/O | Tests/CapDAGTests/CSPlanDecompositionTests.m:144 |
| test756 | `test756_extractForeachBodyUnclosed` | TEST756: extractForeachBody for unclosed ForEach (single body cap) | Tests/CapDAGTests/CSPlanDecompositionTests.m:176 |
| test757 | `test757_extractForeachBodyWrongType` | TEST757: extractForeachBody fails for non-ForEach node | Tests/CapDAGTests/CSPlanDecompositionTests.m:193 |
| test758 | `test758_extractSuffixFrom` | TEST758: extractSuffixFrom extracts collect → cap_post → output | Tests/CapDAGTests/CSPlanDecompositionTests.m:204 |
| test759 | `test759_extractSuffixNonexistent` | TEST759: extractSuffixFrom fails for nonexistent node | Tests/CapDAGTests/CSPlanDecompositionTests.m:225 |
| test760 | `test760_decompositionCoversAllCaps` | TEST760: Full decomposition covers all cap nodes | Tests/CapDAGTests/CSPlanDecompositionTests.m:234 |
| test761 | `test761_prefixIsDag` | TEST761: Prefix is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:273 |
| test762 | `test762_bodyIsDag` | TEST762: Body is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:282 |
| test763 | `test763_suffixIsDag` | TEST763: Suffix is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:291 |
| test764 | `test764_prefixToInputSlot` | TEST764: extractPrefixTo with InputSlot as target (trivial prefix) | Tests/CapDAGTests/CSPlanDecompositionTests.m:300 |
| test772 | `test772_findPathsMultiStep` | TEST772: Multi-step path through intermediate node | Tests/CapDAGTests/CSLiveCapFabTests.m:149 |
| test773 | `test773_findPathsEmptyWhenNoPath` | TEST773: Empty when target unreachable | Tests/CapDAGTests/CSLiveCapFabTests.m:171 |
| test774 | `test774_getReachableTargetsAll` | TEST774: BFS finds multiple direct targets | Tests/CapDAGTests/CSLiveCapFabTests.m:187 |
| test777 | `test777_typeMismatchPdfPng` | TEST777: PDF cap does not match PNG input | Tests/CapDAGTests/CSLiveCapFabTests.m:210 |
| test778 | `test778_typeMismatchPngPdf` | TEST778: PNG cap does not match PDF input | Tests/CapDAGTests/CSLiveCapFabTests.m:225 |
| test779 | `test779_reachableTargetsTypeMatching` | TEST779: BFS respects type matching | Tests/CapDAGTests/CSLiveCapFabTests.m:240 |
| test780 | `test780_splitIntegerArray` | TEST780: split_cbor_array splits a simple array of integers | Tests/BifaciTests/CborSequenceTests.swift:236 |
| test781 | `test781_findPathsTypeChain` | TEST781: Multi-step type chain enforcement | Tests/CapDAGTests/CSLiveCapFabTests.m:263 |
| test782 | `test782_splitNonArray` | TEST782: split_cbor_array rejects non-array input | Tests/BifaciTests/CborSequenceTests.swift:266 |
| test783 | `test783_splitEmptyArray` | TEST783: split_cbor_array rejects empty array | Tests/BifaciTests/CborSequenceTests.swift:284 |
| test784 | `test784_splitInvalidCbor` | TEST784: split_cbor_array rejects invalid CBOR bytes | Tests/BifaciTests/CborSequenceTests.swift:302 |
| test785 | `test785_assembleIntegerArray` | TEST785: assemble_cbor_array creates array from individual items | Tests/BifaciTests/CborSequenceTests.swift:321 |
| test786 | `test786_roundtripSplitAssemble` | TEST786: split then assemble roundtrip preserves data | Tests/BifaciTests/CborSequenceTests.swift:342 |
| test787 | `test787_sortingShorterFirst` | TEST787: Sorting prefers shorter paths | Tests/CapDAGTests/CSLiveCapFabTests.m:286 |
| test788 | `test788_forEachWithSequenceInput` | TEST788: ForEach synthesized when input is a sequence | Tests/CapDAGTests/CSLiveCapFabTests.m:308 |
| test790 | `test790_identityUrnSpecific` | TEST790: Identity URN is specific, not equivalent to everything | Tests/CapDAGTests/CSLiveCapFabTests.m:349 |
| test810 | `test810_splitSequenceBytes` | TEST810: Tests EdgeType::JsonPath extracts values using nested path expressions Verifies that JsonPath edge type correctly navigates through multiple levels like "data.nested.value" | Tests/BifaciTests/CborSequenceTests.swift:26 |
| test811 | `test811_splitSequenceText` | TEST811: Tests EdgeType::Iteration preserves array values for iterative processing Verifies that Iteration edge type passes through arrays unchanged to enable ForEach patterns | Tests/BifaciTests/CborSequenceTests.swift:50 |
| test812 | `test812_splitSequenceMixed` | TEST812: Tests EdgeType::Collection preserves collected values without transformation Verifies that Collection edge type maintains structure for aggregation patterns | Tests/BifaciTests/CborSequenceTests.swift:66 |
| test813 | `test813_splitSequenceSingle` | TEST813: Tests JSON path extraction through deeply nested object hierarchies (4+ levels) Verifies that paths can traverse multiple nested levels like "level1.level2.level3.level4.value" | Tests/BifaciTests/CborSequenceTests.swift:84 |
| test814 | `test814_roundtripAssembleSplitSequence` | TEST814: Tests error handling when array index exceeds available elements Verifies that out-of-bounds array access returns a descriptive error message | Tests/BifaciTests/CborSequenceTests.swift:96 |
| test815 | `test815_roundtripSplitAssembleSequence` | TEST815: Tests JSON path extraction with single-level paths (no nesting) Verifies that simple field names without dots correctly extract top-level values | Tests/BifaciTests/CborSequenceTests.swift:114 |
| test816 | `test816_splitSequenceEmpty` | TEST816: Tests JSON path extraction preserves special characters in string values Verifies that quotes, backslashes, and other special characters are correctly maintained | Tests/BifaciTests/CborSequenceTests.swift:127 |
| test817 | `test817_splitSequenceTruncated` | TEST817: Tests JSON path extraction correctly handles explicit null values Verifies that null is returned as serde_json::Value::Null rather than an error | Tests/BifaciTests/CborSequenceTests.swift:142 |
| test818 | `test818_assembleSequenceInvalidItem` | TEST818: Tests JSON path extraction correctly returns empty arrays Verifies that zero-length arrays are extracted as valid empty array values | Tests/BifaciTests/CborSequenceTests.swift:165 |
| test819 | `test819_assembleSequenceEmpty` | TEST819: Tests JSON path extraction handles various numeric types correctly Verifies extraction of integers, floats, negative numbers, and zero | Tests/BifaciTests/CborSequenceTests.swift:186 |
| test820 | `test820_singleValueSequence` | TEST820: Tests JSON path extraction correctly handles boolean values Verifies that true and false are extracted as proper boolean JSON values | Tests/BifaciTests/CborSequenceTests.swift:192 |
| test821 | `test821_inputStreamCollectCborSequence` | TEST821: Tests JSON path extraction with multi-dimensional arrays (matrix access) Verifies that nested array structures like "matrix[1]" correctly extract inner arrays | Tests/BifaciTests/CborSequenceTests.swift:202 |
| test822 | `test822_collectBytesVsSequence` | TEST822: Tests error handling for non-numeric array indices Verifies that invalid indices like "items[abc]" return a descriptive parse error | Tests/BifaciTests/CborSequenceTests.swift:589 |
| test823 | `test823_isDispatchable_exactMatch` | TEST823: is_dispatchable — exact match provider dispatches request | Tests/CapDAGTests/CSCapUrnTests.m:1123 |
| test824 | `test824_isDispatchable_broaderInputHandlesSpecific` | TEST824: is_dispatchable — provider with broader input handles specific request (contravariance) | Tests/CapDAGTests/CSCapUrnTests.m:1133 |
| test825 | `test825_isDispatchable_unconstrainedInput` | TEST825: is_dispatchable — request with unconstrained input dispatches to specific provider media: on the request input axis means "unconstrained" — vacuously true | Tests/CapDAGTests/CSCapUrnTests.m:1144 |
| test826 | `test826_isDispatchable_providerOutputSatisfiesRequest` | TEST826: is_dispatchable — provider output must satisfy request output (covariance) | Tests/CapDAGTests/CSCapUrnTests.m:1154 |
| test827 | `test827_isDispatchable_genericOutputCannotSatisfySpecific` | TEST827: is_dispatchable — provider with generic output cannot satisfy specific request | Tests/CapDAGTests/CSCapUrnTests.m:1164 |
| test828 | `test828_isDispatchable_wildcardRequestProviderMissingTag` | TEST828: is_dispatchable — wildcard * tag in request, provider missing tag → reject | Tests/CapDAGTests/CSCapUrnTests.m:1174 |
| test829 | `test829_isDispatchable_wildcardRequestProviderHasTag` | TEST829: is_dispatchable — wildcard * tag in request, provider has tag → accept | Tests/CapDAGTests/CSCapUrnTests.m:1184 |
| test830 | `test830_isDispatchable_providerExtraTags` | TEST830: is_dispatchable — provider extra tags are refinement, always OK | Tests/CapDAGTests/CSCapUrnTests.m:1194 |
| test831 | `test831_isDispatchable_crossBackendMismatch` | TEST831: is_dispatchable — cross-backend mismatch prevented | Tests/CapDAGTests/CSCapUrnTests.m:1204 |
| test832 | `test832_isDispatchable_asymmetric` | TEST832: is_dispatchable is NOT symmetric | Tests/CapDAGTests/CSCapUrnTests.m:1214 |
| test833 | `test833_isComparable_symmetric` | TEST833: is_comparable — both directions checked | Tests/CapDAGTests/CSCapUrnTests.m:1225 |
| test834 | `test834_isComparable_unrelated` | TEST834: is_comparable — unrelated caps are NOT comparable | Tests/CapDAGTests/CSCapUrnTests.m:1236 |
| test835 | `test835_isEquivalent_identical` | TEST835: is_equivalent — identical caps | Tests/CapDAGTests/CSCapUrnTests.m:1247 |
| test836 | `test836_isEquivalent_nonEquivalent` | TEST836: is_equivalent — non-equivalent comparable caps | Tests/CapDAGTests/CSCapUrnTests.m:1257 |
| test837 | `test837_isDispatchable_opTagMismatch` | TEST837: is_dispatchable — op tag mismatch rejects | Tests/CapDAGTests/CSCapUrnTests.m:1268 |
| test838 | `test838_isDispatchable_requestWildcardOutput` | TEST838: is_dispatchable — request with wildcard output accepts any provider output | Tests/CapDAGTests/CSCapUrnTests.m:1278 |
| test839 | `test839_peerResponseDeliversLogsBeforeStreamStart` | TEST839: LOG frames arriving BEFORE StreamStart are delivered immediately This tests the critical fix: during a peer call, the peer (e.g., modelcartridge) sends LOG frames for minutes during model download BEFORE sending any data (StreamStart + Chunk). The handler must receive these LOGs in real-time so it can re-emit progress and keep the engine's activity timer alive. Previously, demux_single_stream blocked on awaiting StreamStart before returning PeerResponse, which meant the handler couldn't call recv() until data arrived — causing 120s activity timeouts during long downloads. | Tests/BifaciTests/StreamingAPITests.swift:662 |
| test840 | `test840_peerResponseCollectBytesDiscardsLogs` | TEST840: PeerResponse::collect_bytes discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:733 |
| test841 | `test841_peerResponseCollectValueDiscardsLogs` | TEST841: PeerResponse::collect_value discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:763 |
| test842 | `test842_runWithKeepaliveReturnsResult` | TEST842: run_with_keepalive returns closure result (fast operation, no keepalive frames) | Tests/BifaciTests/StreamingAPITests.swift:794 |
| test843 | `test843_runWithKeepaliveReturnsResultType` | TEST843: run_with_keepalive returns Ok/Err from closure | Tests/BifaciTests/StreamingAPITests.swift:817 |
| test844 | `test844_runWithKeepalivePropagatesError` | TEST844: run_with_keepalive propagates errors from closure | Tests/BifaciTests/StreamingAPITests.swift:835 |
| test845 | `test845_progressSenderEmitsFrames` | TEST845: ProgressSender emits progress and log frames independently of OutputStream | Tests/BifaciTests/StreamingAPITests.swift:863 |
| test846 | `test846_progressFrameRoundtrip` | TEST846: Test progress LOG frame encode/decode roundtrip preserves progress float | Tests/BifaciTests/FrameTests.swift:1707 |
| test847 | `test847_progressDoubleRoundtrip` | TEST847: Double roundtrip (modelcartridge → relay → candlecartridge) | Tests/BifaciTests/FrameTests.swift:1744 |
| test852 | `test852_lub_identical` | TEST852: LUB of identical URNs returns the same URN | Tests/CapDAGTests/CSMediaUrnTests.m:18 |
| test853 | `test853_lub_no_common_tags` | TEST853: LUB of URNs with no common tags returns media: (universal) | Tests/CapDAGTests/CSMediaUrnTests.m:27 |
| test854 | `test854_lub_partial_overlap` | TEST854: LUB keeps common tags, drops differing ones | Tests/CapDAGTests/CSMediaUrnTests.m:41 |
| test855 | `test855_lub_list_vs_scalar` | TEST855: LUB of list and non-list drops list tag | Tests/CapDAGTests/CSMediaUrnTests.m:55 |
| test856 | `test856_lub_empty` | TEST856: LUB of empty input returns universal type | Tests/CapDAGTests/CSMediaUrnTests.m:69 |
| test857 | `test857_lub_single` | TEST857: LUB of single input returns that input | Tests/CapDAGTests/CSMediaUrnTests.m:78 |
| test858 | `test858_lub_three_inputs` | TEST858: LUB with three+ inputs narrows correctly | Tests/CapDAGTests/CSMediaUrnTests.m:87 |
| test859 | `test859_lub_valued_tags` | TEST859: LUB with valued tags (non-marker) that differ | Tests/CapDAGTests/CSMediaUrnTests.m:103 |
| test860 | `test860_seqAssignerSameRidDifferentXidsIndependent` | TEST860: Same RID with different XIDs get independent seq counters | Tests/BifaciTests/FlowOrderingTests.swift:115 |
| test896 | `test896_fullPathEngineReqToCartridgeResponse` | TEST896: All cap input media specs that represent user files must have extensions. These are the entry points — the file types users can right-click on. | Tests/BifaciTests/IntegrationTests.swift:636 |
| test897 | `test897_cartridgeErrorFlowsToEngine` | TEST897: Verify that specific cap output URNs resolve to the correct extension. This catches misconfigurations where a spec exists but has the wrong extension. | Tests/BifaciTests/IntegrationTests.swift:703 |
| test898 | `test898_binaryIntegrityThroughRelay` | TEST898: Binary data integrity through full relay path (256 byte values) | Tests/BifaciTests/IntegrationTests.swift:745 |
| test899 | `test899_streamingChunksThroughRelay` | TEST899: Streaming chunks flow through relay without accumulation | Tests/BifaciTests/IntegrationTests.swift:803 |
| test900 | `test900_twoCartridgesRoutedIndependently` | TEST900: Two cartridges routed independently by cap_urn | Tests/BifaciTests/IntegrationTests.swift:860 |
| test901 | `test901_reqForUnknownCapReturnsErr` | TEST901: REQ for unknown cap returns ERR frame (not fatal) | Tests/BifaciTests/RuntimeTests.swift:624 |
| test902 | `test902_computeChecksumEmpty` | TEST902: Verify FNV-1a checksum handles empty data | Tests/BifaciTests/FrameTests.swift:1652 |
| test903 | `test903_chunkWithChunkIndexAndChecksum` | TEST903: Verify CHUNK frame can store chunk_index and checksum fields | Tests/BifaciTests/FrameTests.swift:1659 |
| test904 | `test904_streamEndWithChunkCount` | TEST904: Verify STREAM_END frame can store chunk_count field | Tests/BifaciTests/FrameTests.swift:1672 |
| test907 | `test907_cborRejectsStreamEndWithoutChunkCount` | TEST907: Offline flag blocks fetch_from_registry without making HTTP request | Tests/BifaciTests/FrameTests.swift:1682 |
| test908 | `test908_map_progress_basic_mapping` | TEST908: Cached caps remain accessible when offline | Tests/CapDAGTests/CSProgressMapperTests.m:17 |
| test909 | `test909_map_progress_deterministic` | TEST909: set_offline(false) restores fetch ability (would fail with HTTP error, not NetworkBlocked) | Tests/CapDAGTests/CSProgressMapperTests.m:34 |
| test910 | `test910_map_progress_monotonic` | TEST910: map_progress output is monotonic for monotonically increasing input | Tests/CapDAGTests/CSProgressMapperTests.m:44 |
| test911 | `test911_map_progress_bounded` | TEST911: map_progress output is bounded within [base, base+weight] | Tests/CapDAGTests/CSProgressMapperTests.m:56 |
| test912 | `test912_progress_mapper_reports_through_parent` | TEST912: ProgressMapper correctly maps through a CapProgressFn | Tests/CapDAGTests/CSProgressMapperTests.m:70 |
| test913 | `test913_progress_mapper_as_cap_progress_fn` | TEST913: ProgressMapper.as_cap_progress_fn produces same mapping | Tests/CapDAGTests/CSProgressMapperTests.m:89 |
| test914 | `test914_progress_mapper_sub_mapper` | TEST914: ProgressMapper.sub_mapper chains correctly | Tests/CapDAGTests/CSProgressMapperTests.m:110 |
| test915 | `test915_per_group_subdivision_monotonic_bounded` | TEST915: Per-group subdivision produces monotonic, bounded progress for N groups Uses pre-computed boundaries (same pattern as production code) to guarantee monotonicity regardless of f32 rounding. | Tests/CapDAGTests/CSProgressMapperTests.m:132 |
| test917 | `test917_high_frequency_progress_bounded` | TEST917: High-frequency progress emission does not violate bounds (Regression test for the deadlock scenario — verifies computation stays bounded) | Tests/CapDAGTests/CSProgressMapperTests.m:170 |
| test919 | `test919_parseSimpleTestcartridgeGraph` | TEST919: Parse simple machine notation graph with test-edge1 | Tests/BifaciTests/OrchestratorTests.swift:82 |
| test934 | `test934_findFirstForeach` | MARK: - TEST934: findFirstForeach detects ForEach | Tests/CapDAGTests/CSPlanDecompositionTests.m:84 |
| test935 | `test935_findFirstForeachLinear` | TEST935: findFirstForeach returns nil for linear plans | Tests/CapDAGTests/CSPlanDecompositionTests.m:91 |
| test936 | `test936_hasForeach` | TEST936: hasForeach | Tests/CapDAGTests/CSPlanDecompositionTests.m:100 |
| test937 | `test937_extractPrefixTo` | TEST937: extractPrefixTo extracts input_slot → cap_0 as standalone plan | Tests/CapDAGTests/CSPlanDecompositionTests.m:112 |
| test944 | `test944_sixMachine` | TEST944: 6-machine: edge1 -> edge2 -> edge7 -> edge8 -> edge9 -> edge10 Full cycle: node1 -> node2 -> node3 -> node6 -> node7 -> node8 -> node1 Completes the round trip: unwrap markers + lowercase | Tests/BifaciTests/OrchestratorTests.swift:300 |
| test945 | `test945_fiveMachine` | TEST945: 5-machine: edge1 -> edge2 -> edge7 -> edge8 -> edge9 node1 -> node2 -> node3 -> node6 -> node7 -> node8 adds <<...>> wrapping around the reversed string | Tests/BifaciTests/OrchestratorTests.swift:274 |
| test946 | `test946_fourMachine` | TEST946: 4-machine: edge1 -> edge2 -> edge7 -> edge8 node1 -> node2 -> node3 -> node6 -> node7 "hello" -> "[PREPEND]hello" -> "[PREPEND]hello[APPEND]" -> "[PREPEND]HELLO[APPEND]" -> "]DNEPPA[OLLEH]DNEPERP[" | Tests/BifaciTests/OrchestratorTests.swift:250 |
| test947 | `test947_capNotFound` | TEST947: Cap not found in registry | Tests/BifaciTests/OrchestratorTests.swift:224 |
| test948 | `test948_invalidCapUrn` | TEST948: Invalid cap URN in machine notation | Tests/BifaciTests/OrchestratorTests.swift:206 |
| test949 | `test949_emptyGraph` | TEST949: Empty machine notation (no edges) | Tests/BifaciTests/OrchestratorTests.swift:188 |
| test955 | `test955_splitMapArray` | TEST955: split_cbor_array with nested maps | Tests/BifaciTests/CborSequenceTests.swift:250 |
| test956 | `test956_roundtripAssembleSplit` | TEST956: assemble then split roundtrip preserves data | Tests/BifaciTests/CborSequenceTests.swift:360 |
| test961 | `test961_assembleEmpty` | TEST961: assemble empty list produces empty CBOR array | Tests/BifaciTests/CborSequenceTests.swift:377 |
| test962 | `test962_assembleInvalidItem` | TEST962: assemble rejects invalid CBOR item | Tests/BifaciTests/CborSequenceTests.swift:387 |
| test963 | `test963_splitBinaryItems` | TEST963: split preserves CBOR byte strings (binary data — the common case in bifaci) | Tests/BifaciTests/CborSequenceTests.swift:403 |
| test964 | `test964_splitSequenceBytes` | TEST964: split_cbor_sequence splits concatenated CBOR Bytes values | Tests/BifaciTests/CborSequenceTests.swift:421 |
| test965 | `test965_splitSequenceText` | TEST965: split_cbor_sequence splits concatenated CBOR Text values | Tests/BifaciTests/CborSequenceTests.swift:436 |
| test966 | `test966_splitSequenceMixed` | TEST966: split_cbor_sequence handles mixed types | Tests/BifaciTests/CborSequenceTests.swift:451 |
| test967 | `test967_splitSequenceSingle` | TEST967: split_cbor_sequence single-item sequence | Tests/BifaciTests/CborSequenceTests.swift:470 |
| test968 | `test968_roundtripAssembleSplitSequence` | TEST968: roundtrip — assemble then split preserves items | Tests/BifaciTests/CborSequenceTests.swift:481 |
| test969 | `test969_roundtripSplitAssembleSequence` | TEST969: roundtrip — split then assemble preserves byte-for-byte | Tests/BifaciTests/CborSequenceTests.swift:498 |
| test970 | `test970_splitSequenceEmpty` | TEST970: split_cbor_sequence rejects empty data | Tests/BifaciTests/CborSequenceTests.swift:512 |
| test971 | `test971_splitSequenceTruncated` | TEST971: split_cbor_sequence rejects truncated CBOR | Tests/BifaciTests/CborSequenceTests.swift:526 |
| test972 | `test972_assembleSequenceInvalidItem` | TEST972: assemble_cbor_sequence rejects invalid CBOR item | Tests/BifaciTests/CborSequenceTests.swift:537 |
| test973 | `test973_assembleSequenceEmpty` | TEST973: assemble_cbor_sequence with empty items list produces empty bytes | Tests/BifaciTests/CborSequenceTests.swift:548 |
| test974 | `test974_sequenceIsNotArray` | TEST974: CBOR sequence is NOT a CBOR array — split_cbor_array rejects a sequence | Tests/BifaciTests/CborSequenceTests.swift:554 |
| test975 | `test975_singleValueSequence` | TEST975: split_cbor_sequence works on data that is also a valid CBOR array (single top-level value) | Tests/BifaciTests/CborSequenceTests.swift:571 |
| test1000 | `test1000_single_existing_file` | TEST1000: Single existing file | Tests/CapDAGTests/CSInputResolverTests.m:51 |
| test1001 | `test1001_nonexistent_file` | TEST1001: Single non-existent file | Tests/CapDAGTests/CSInputResolverTests.m:64 |
| test1002 | `test1002_empty_directory` | TEST1002: Empty directory | Tests/CapDAGTests/CSInputResolverTests.m:76 |
| test1003 | `test1003_directory_with_files` | TEST1003: Directory with files | Tests/CapDAGTests/CSInputResolverTests.m:88 |
| test1004 | `test1004_directory_with_subdirs` | TEST1004: Directory with subdirs (recursive) | Tests/CapDAGTests/CSInputResolverTests.m:103 |
| test1005 | `test1005_glob_matching_files` | TEST1005: Glob matching files | Tests/CapDAGTests/CSInputResolverTests.m:118 |
| test1006 | `test1006_glob_matching_nothing` | TEST1006: Glob matching nothing | Tests/CapDAGTests/CSInputResolverTests.m:133 |
| test1007 | `test1007_recursive_glob` | TEST1007: Recursive glob | Tests/CapDAGTests/CSInputResolverTests.m:145 |
| test1008 | `test1008_mixed_file_dir` | TEST1008: Mixed file + dir | Tests/CapDAGTests/CSInputResolverTests.m:164 |
| test1010 | `test1010_duplicate_paths` | TEST1010: Duplicate paths are deduplicated | Tests/CapDAGTests/CSInputResolverTests.m:178 |
| test1011 | `test1011_invalid_glob` | TEST1011: Invalid glob syntax | Tests/CapDAGTests/CSInputResolverTests.m:190 |
| test1013 | `test1013_empty_input` | TEST1013: Empty input array | Tests/CapDAGTests/CSInputResolverTests.m:201 |
| test1014 | `test1014_symlink_to_file` | TEST1014: Symlink to file resolves to its target | Tests/CapDAGTests/CSInputResolverTests.m:212 |
| test1016 | `test1016_path_with_spaces` | TEST1016: Path with spaces | Tests/CapDAGTests/CSInputResolverTests.m:230 |
| test1017 | `test1017_path_with_unicode` | TEST1017: Path with unicode | Tests/CapDAGTests/CSInputResolverTests.m:242 |
| test1018 | `test1018_relative_path` | TEST1018: Relative path | Tests/CapDAGTests/CSInputResolverTests.m:254 |
| test1020 | `test1020_ds_store_excluded` | TEST1020: macOS .DS_Store is excluded | Tests/CapDAGTests/CSInputResolverTests.m:272 |
| test1021 | `test1021_thumbs_db_excluded` | TEST1021: Windows Thumbs.db is excluded | Tests/CapDAGTests/CSInputResolverTests.m:278 |
| test1022 | `test1022_resource_fork_excluded` | TEST1022: macOS resource fork files are excluded | Tests/CapDAGTests/CSInputResolverTests.m:284 |
| test1023 | `test1023_office_lock_excluded` | TEST1023: Office lock files are excluded | Tests/CapDAGTests/CSInputResolverTests.m:290 |
| test1024 | `test1024_git_dir_excluded` | TEST1024: .git directory is excluded | Tests/CapDAGTests/CSInputResolverTests.m:296 |
| test1025 | `test1025_macosx_dir_excluded` | TEST1025: __MACOSX archive artifact is excluded | Tests/CapDAGTests/CSInputResolverTests.m:302 |
| test1026 | `test1026_temp_files_excluded` | TEST1026: Temp files are excluded | Tests/CapDAGTests/CSInputResolverTests.m:308 |
| test1027 | `test1027_localized_excluded` | TEST1027: .localized is excluded | Tests/CapDAGTests/CSInputResolverTests.m:314 |
| test1028 | `test1028_desktop_ini_excluded` | TEST1028: desktop.ini is excluded | Tests/CapDAGTests/CSInputResolverTests.m:319 |
| test1029 | `test1029_normal_files_not_excluded` | TEST1029: Normal files are NOT excluded | Tests/CapDAGTests/CSInputResolverTests.m:324 |
| test1090 | `test1090_single_file_scalar` | TEST1090: 1 file → is_sequence=false | Tests/CapDAGTests/CSInputResolverTests.m:335 |
| test1092 | `test1092_two_files` | TEST1092: 2 files → is_sequence=true | Tests/CapDAGTests/CSInputResolverTests.m:347 |
| test1093 | `test1093_dir_single_file` | TEST1093: 1 dir with 1 file → is_sequence=false | Tests/CapDAGTests/CSInputResolverTests.m:361 |
| test1094 | `test1094_dir_multiple_files` | TEST1094: 1 dir with 3 files → is_sequence=true | Tests/CapDAGTests/CSInputResolverTests.m:375 |
| test1098 | `test1098_extension_based_pdf` | TEST1098: Extension-based detection picks up pdf tag for .pdf files | Tests/CapDAGTests/CSInputResolverTests.m:391 |
| test1144 | `test1144_content_structure_helpers` | TEST1144: ContentStructure is_list/is_record helpers are correct | Tests/CapDAGTests/CSInputResolverTests.m:411 |
| test1145 | `test1145_resolved_input_set_uses_equivalent_media_and_file_count_cardinality` | TEST1145: ResolvedInputSet uses URN equivalence for common_media and file count for is_sequence | Tests/CapDAGTests/CSInputResolverTests.m:442 |
| test1400 | `test1400_missingOutSpecDefaultsToWildcard` | TEST1400: Missing 'out' defaults to media: wildcard (mirror-local variant of TEST002 covering the out-side case) | Tests/CapDAGTests/CSCapUrnTests.m:157 |
| test1401 | `test1401_directionWildcardMatches` | TEST1401: Wildcard in/out specs accept any concrete value (mirror-local variant of TEST003's wildcard branch) | Tests/CapDAGTests/CSCapUrnTests.m:218 |
| test1402 | `test1402_invalidCharacters` | TEST1402: Invalid characters (e.g. '@') in tag keys are rejected by the parser (mirror-local variant of TEST003) | Tests/CapDAGTests/CSCapUrnTests.m:134 |
| test1403 | `test1403_equality` | TEST1403: Equality and hash of CSCapUrn identify identical URNs and distinguish direction/tag differences (mirror-local variant of TEST016) | Tests/CapDAGTests/CSCapUrnTests.m:491 |
| test1404 | `test1404_merge` | TEST1404: merge() combines tags from two cap URNs; direction comes from the other cap (mirror-local variant of TEST026's merge branch) | Tests/CapDAGTests/CSCapUrnTests.m:475 |
| test1405 | `test1405_wildcardTagDirection` | TEST1405: withWildcardTag resolves to withInSpec/withOutSpec for "in"/"out" tags, setting them to the wildcard "media:" (mirror-local variant of TEST027) | Tests/CapDAGTests/CSCapUrnTests.m:451 |
| test1406 | `test1406_valuelessTagParsing` | TEST1406: Value-less tags (bare keys like ";flag") parse as wildcards (mirror-local variant of TEST031) | Tests/CapDAGTests/CSCapUrnTests.m:114 |
| test1407 | `test1407_withTagIgnoresInOut` | TEST1407: withTag silently ignores attempts to set "in" or "out" tags (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:377 |
| test1408 | `test1408_withInSpec` | TEST1408: withInSpec returns a new URN with the in= spec replaced, leaving the original unchanged (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:390 |
| test1409 | `test1409_withOutSpec` | TEST1409: withOutSpec returns a new URN with the out= spec replaced, leaving the original unchanged (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:400 |
| test1410 | `test1410_withoutTag` | TEST1410: withoutTag removes a tag and returns a new URN, leaving the original unchanged (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:410 |
| test1411 | `test1411_withoutTagIgnoresInOut` | TEST1411: withoutTag silently ignores attempts to remove "in" or "out" tags (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:424 |
| test1412 | `test1412_directionSemanticMatching` | TEST1412: Semantic direction matching - generic provider matches specific request (mirror-local variant of TEST051) | Tests/CapDAGTests/CSCapUrnTests.m:934 |
| test1413 | `test1413_directionSemanticSpecificity` | TEST1413: Semantic direction specificity - more media URN tags = higher specificity (mirror-local variant of TEST052) | Tests/CapDAGTests/CSCapUrnTests.m:981 |
| test1414 | `test1414_parseSingleEdgeDag` | TEST1414: Parse DAG with a single edge using different node names (mirror-local) | Tests/BifaciTests/OrchestratorTests.swift:100 |
| test1415 | `test1415_parseEdge1ToEdge2Chain` | TEST1415: Parse DAG chaining test_edge1 → test_edge2 (mirror-local) | Tests/BifaciTests/OrchestratorTests.swift:118 |
| test1500 | `test1500_writeAfterCloseThrowsCleanly` | TEST1500: Writing to a closed FrameWriter must throw FrameError.ioError("writer closed"), never raise an Objective-C NSException that aborts the process. | Tests/BifaciTests/FrameTests.swift:1791 |
| test1501 | `test1501_doubleCloseIsIdempotent` | TEST1501: Calling close() twice on a FrameWriter is a no-op — the second call must not throw, must not double-close the underlying fd, and must leave the writer in the closed state. | Tests/BifaciTests/FrameTests.swift:1816 |
| test1502 | `test1502_flushAfterCloseThrowsCleanly` | TEST1502: flush() on a closed FrameWriter — even with an empty buffer — must throw FrameError.ioError, not silently succeed. A flush call after close() is a programmer error and must surface, not be papered over. | Tests/BifaciTests/FrameTests.swift:1839 |
| test1503 | `test1503_concurrentCloseAndWriteDoesNotCrash` | TEST1503: Concurrent close() + write() must not raise an Objective-C NSException. This is the regression test for the CartridgeXPCService crash on cartridge OOM: the old writer accessed `handle.fileDescriptor` on every write, so a close() racing a write() called the accessor on a closed handle and aborted the process. The cached-fd writer keeps the descriptor in the writer's own state, so the worst outcome of the race is a clean FrameError thrown from write(). | Tests/BifaciTests/FrameTests.swift:1853 |
| test1504 | `test1504_closeShutsTheUnderlyingPipe` | TEST1504: After FrameWriter.close(), the underlying FileHandle is closed. A subsequent read on the paired read end must observe EOF — proving that close() actually closes the pipe (not just marks the writer dead in software). This guards against the regression where close() flips the writer flag but leaves the pipe open, which would let buffered data still drain into a peer that's been told the writer is gone. | Tests/BifaciTests/FrameTests.swift:1920 |
| test1505 | `test1505_deinitDoesNotAccessClosedHandle` | TEST1505: A FrameWriter going through deinit must NOT touch the underlying handle's `fileDescriptor` accessor. The original bug used to deinit-flush by reading `handle.fileDescriptor`, which raises NSFileHandleOperationException on a closed handle and aborts the process. The new contract: deinit does no I/O. This test deinits a writer whose handle was closed externally, then asserts the test process is still alive (i.e. did not crash via NSException). | Tests/BifaciTests/FrameTests.swift:1932 |
| test1600 | `test1600_hashesFileLargerThanOneChunk` | TEST1600: Hashing a directory containing a file LARGER than the streaming chunk size produces the same hash as an independent reference implementation. Exercises the multi-iteration read loop in `computeCartridgeDirectoryHash` — if a future refactor reverted to slurping whole files, the hash would still match (slurp gives the right answer too), so this is the necessary correctness pin even though it is not the tightest possible regression. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:92 |
| test1601 | `test1601_streamChunkSizeIsBounded` | TEST1601: The streaming chunk size is bounded so no single allocation scales with file size. This is the structural guard that prevents a future revert to FileManager.contents(atPath:) on a 200+ MB cartridge binary — that revert silently corrupted state in the sandboxed XPC service. Anything above 16 MiB is in the "you're slurping" zone and must not land. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:114 |
| test1602 | `test1602_cartridgeJsonExcluded` | TEST1602: cartridge.json is excluded from the hash — adding it (or changing its contents) must not change the directory hash, because cartridge.json carries install-time metadata that varies between installs of the same logical content. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:122 |
| test1603 | `test1603_missingDirectoryThrowsTypedError` | TEST1603: Hashing a directory that does not exist throws CartridgeDirectoryHashError.directoryUnreadable carrying the offending path. Replaces the original silent `return nil` that the caller turned into a generic "must be hashable" fatalError — the new error names the actual path so operators see what to fix. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:142 |
| test1604 | `test1604_emptyDirectoryHashes` | TEST1604: An empty directory hashes successfully (just the SHA256 of nothing — empty input). Ensures the function does not insist on at least one file. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:161 |
| test1605 | `test1605_fileSHA256MatchesKnownVector` | TEST1605: computeFileSHA256 streams a single file (used for quarantine identity tracking) and produces the standard SHA256 of the file's bytes. Verifies multi-chunk read correctness against a known SHA256 of `"abc"` from the FIPS-180-2 test vectors. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:172 |
| test1606 | `test1606_fileSHA256StreamsAcrossChunks` | TEST1606: computeFileSHA256 streams arbitrarily large files without loading the whole file into memory. Hashes a file roughly 3.5 chunks long and verifies the result against a single-shot CC_SHA256 over the same buffer — proving the chunk loop is correct across multiple read iterations. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:184 |
| test1607 | `test1607_fileSHA256ThrowsOnMissingPath` | TEST1607: computeFileSHA256 throws openFailed on a missing path with the offending path attached. Replaces the previous silent `return nil` so callers can surface the actual cause to the operator. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:204 |
| test1700 | `test1700_healthyAnchorHashesAndCarriesNoError` | / TEST1700: A healthy cartridge whose directory exists hashes / successfully and the resulting identity has the same name / / version / channel as the cartridge.json, a non-empty sha256, / and NO attachment error. Pins the happy path so a future / refactor that breaks healthy-case hashing surfaces here. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:94 |
| test1701 | `test1701_missingManifestReturnsNil` | / TEST1701: A cartridge whose `cartridge.json` has been / deleted (e.g. the operator uninstalled, or the directory / got swept up by a `dx clear --cartridges`) returns nil from / `buildInstalledCartridgeRecord`. There is no layout / fallback — cartridge.json IS the identity, and a cartridge / without a manifest is considered gone for this RelayNotify / pass. The host stays alive; the discovery scanner picks up / the change on its next scan. / / Regression test for the field crash: /   Bifaci/CartridgeHost.swift:617: Fatal error: /   BUG: healthy installed cartridge directory must be /   hashable at .../pdfcartridge/0.182.450 / Before the fix this code path aborted the whole XPC service. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:131 |
| test1702 | `test1702_malformedManifestReturnsNil` | / TEST1702: Cartridge.json that's present-but-malformed (e.g. / the file got truncated mid-write) also returns nil. There / is no salvage path — a cartridge whose manifest can't be / parsed is not a cartridge. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:154 |
| test1703 | `test1703_oldSchemaManifestMissingRegistryUrlReturnsNil` | / TEST1703: A cartridge.json that omits the required / `registry_url` key (old-schema file) returns nil. / `registry_url` is required-but-nullable in the manifest / schema; absent-key surfaces here as nil identity, surfaces / downstream as the cartridge being filtered out of / RelayNotify, and forces the operator to reinstall on the / new schema. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:179 |
| test1704 | `test1704_existingAttachmentErrorRoundTrips` | / TEST1704: A cartridge that already carries an attachment / error from upstream (e.g. failed HELLO) round-trips that / error verbatim — the identity-build path does NOT mint a / fresh error or override it. The sha256 is the real hash / because the directory is still healthy; the error / describes a different problem (the failed HELLO) than the / hash function could surface. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:215 |
| test1705 | `test1705_missingManifestWinsOverExistingError` | / TEST1705: An attached cartridge whose manifest has gone / missing returns nil regardless of any prior attachment / error. The contract is "manifest is identity"; a cartridge / without a manifest is gone for this RelayNotify pass — / even if it had a previously-recorded HELLO failure, the / disappeared anchor wins. The discovery scanner removes the / stale tree on its next pass. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:254 |
| test1710 | `test1710_kindRawValuesMatchProtoSnakeCase` | / TEST1710: Every variant's `rawValue` must be its / snake_case proto name. New variants must be added here AND / to `cartridge.proto`'s `CartridgeAttachmentErrorKind`. This / test fails with a clear "expected X for Y" message rather / than a "unknown enum case" runtime crash if the two sides / drift. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:31 |
| test1711 | `test1711_attachmentErrorJSONRoundTripsForEveryKind` | / TEST1711: A `CartridgeAttachmentError` round-trips through / `JSONEncoder` → bytes → `JSONDecoder` unchanged for every / kind. RelayNotify's wire payload is JSON; if any variant / fails to deserialize, the engine's aggregate parse fails / and ALL cartridges from that host disappear from the / inventory — including the healthy ones. This test / covers each variant individually so a single-variant / regression doesn't hide behind a passing healthy-case. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:59 |
| test1712 | `test1712_decodesWireFormatJSONIntoExpectedVariants` | / TEST1712: An on-the-wire JSON payload using the snake_case / raw values decodes into the right Swift variant. This is / the engine → Swift path: the engine emits / `{"kind":"bad_installation",...}` and the Swift side must / resolve it to `.badInstallation`. Asserts the lookup table / the decoder synthesises for `String`-backed enums actually / covers the new variants. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:90 |
| test1713 | `test1713_unknownWireKindFailsToDecode` | / TEST1713: An unknown wire kind FAILS to decode. The two / new variants are wire-additive — older Swift binaries that / don't know `bad_installation` or `disabled` will see those / strings and reject them, which is correct: silently / coercing an unknown variant to a fallback would hide the / version-skew bug. The fatalError sites in / CartridgeGRPCAdapter and InstalledCartridgesStore rely on / this — they expect decode to throw / produce a known / variant, never silently pick a default. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:127 |
| test1800 | `test1800_kind_identity_only_for_bare_cap` | TEST1800: Identity classifier — only the bare cap: form qualifies. Adding any tag (even one that doesn't constrain in/out) demotes the cap to Transform because the operation/metadata axis is no longer fully generic. | Tests/CapDAGTests/CSCapUrnTests.m:1439 |
| test1801 | `test1801_kind_source_when_input_is_void` | TEST1801: Source classifier — in=media:void, out non-void. | Tests/CapDAGTests/CSCapUrnTests.m:1467 |
| test1802 | `test1802_kind_sink_when_output_is_void` | TEST1802: Sink classifier — out=media:void, in non-void. | Tests/CapDAGTests/CSCapUrnTests.m:1480 |
| test1803 | `test1803_kind_effect_when_both_sides_void` | TEST1803: Effect classifier — both sides void. Reads as `() → ()`. | Tests/CapDAGTests/CSCapUrnTests.m:1493 |
| test1804 | `test1804_kind_transform_for_normal_data_processors` | TEST1804: Transform classifier — at least one side non-void, and the cap is not the bare identity. | Tests/CapDAGTests/CSCapUrnTests.m:1507 |
| test1805 | `test1805_kind_invariant_under_canonical_spellings` | TEST1805: Kind is invariant under canonicalization. The same morphism written in many surface forms must classify the same way once parsed. | Tests/CapDAGTests/CSCapUrnTests.m:1522 |
| test1810 | `test1810_media_void_is_atomic` | TEST1810: media:void is atomic — refinements are parse errors. Mirrored across every language port (Rust, Go, Python, Swift/ObjC, JS) under the SAME number. Any divergence is a wire-level inconsistency — the unit type's atomicity is part of the protocol's deepest layer, not a per-port detail. | Tests/CapDAGTests/CSMediaUrnTests.m:482 |
| test1820 | `test1820_specificity_question_is_zero` | TEST1820: A `?`-valued cap-tag scores 0. Same as missing. | Tests/CapDAGTests/CSCapUrnTests.m:1570 |
| test1821 | `test1821_specificity_must_not_have_is_five` | TEST1821: A `!`-valued cap-tag scores 5 (top of negative chain). | Tests/CapDAGTests/CSCapUrnTests.m:1584 |
| test1822 | `test1822_specificity_must_have_any_is_two` | TEST1822: A `*`-valued cap-tag (including bare markers) scores 2. | Tests/CapDAGTests/CSCapUrnTests.m:1593 |
| test1823 | `test1823_specificity_exact_value_is_four` | TEST1823: An exact-valued cap-tag scores 4. | Tests/CapDAGTests/CSCapUrnTests.m:1611 |
| test1824 | `test1824_specificity_combined_y_axis` | TEST1824: All six forms compose additively on a single cap. y combining 0+1+2+3+4+5 must sum to 15. | Tests/CapDAGTests/CSCapUrnTests.m:1621 |
| test1830 | `test1830_canonicalize_no_constraint` |  | Tests/CapDAGTests/CSCapUrnTests.m:1631 |
| test1831 | `test1831_canonicalize_absent_or_not_value` | TEST1831: ?x=v and x?=v both canonicalize to x?=v. The third hypothetical form `x=?v` is NOT recognized as a qualifier — a value starting with `?` is just an exact value beginning with a `?` character. | Tests/CapDAGTests/CSCapUrnTests.m:1646 |
| test1832 | `test1832_canonicalize_must_have_any` |  | Tests/CapDAGTests/CSCapUrnTests.m:1664 |
| test1833 | `test1833_canonicalize_present_not_value` | TEST1833: !x=v and x!=v both canonicalize to x!=v. The third hypothetical form `x=!v` is NOT recognized as a qualifier — a value starting with `!` is just an exact value beginning with a `!` character. | Tests/CapDAGTests/CSCapUrnTests.m:1679 |
| test1834 | `test1834_canonicalize_exact_value` |  | Tests/CapDAGTests/CSCapUrnTests.m:1697 |
| test1835 | `test1835_canonicalize_must_not_have` |  | Tests/CapDAGTests/CSCapUrnTests.m:1704 |
| test1842 | `test1842_truth_table_full_cross_product` | TEST1842: Full 6×6 truth table. | Tests/CapDAGTests/CSCapUrnTests.m:1716 |
| test1843 | `test1843_reject_invalid_combinations` | TEST1843: Invalid qualifier combinations must be rejected. | Tests/CapDAGTests/CSCapUrnTests.m:1748 |
| test1844 | `test1844_axis_weighting_out_dominates` | TEST1844: out-axis difference dominates combined in+y differences. | Tests/CapDAGTests/CSCapUrnTests.m:1764 |
| test1845 | `test1845_axis_weighting_in_dominates_y` | TEST1845: With equal out, in-axis dominates over y-axis. | Tests/CapDAGTests/CSCapUrnTests.m:1777 |
| test1846 | `test1846_axis_weighting_decoded_layout` | TEST1846: Decoded layout — 10000*out + 100*in + y. | Tests/CapDAGTests/CSCapUrnTests.m:1790 |
| | | | |
| unnumbered | `test198b_limitsNegotiation` | TEST198 (continued): Limits negotiation picks minimum of both sides | Tests/BifaciTests/FrameTests.swift:307 |
| unnumbered | `test205b_allFrameTypesRoundtrip` | Covers all frame types in a single loop for comprehensive roundtrip verification | Tests/BifaciTests/FrameTests.swift:894 |
| unnumbered | `test389b_streamStartIsSequenceRoundtrip` | TEST389b: STREAM_START with isSequence roundtrips correctly | Tests/BifaciTests/FrameTests.swift:1091 |
| unnumbered | `test542b_outputStreamStartThenCloseEmpty` | TEST542b: OutputStream start + close sends STREAM_START + STREAM_END (empty stream) | Tests/BifaciTests/StreamingAPITests.swift:407 |
| unnumbered | `test542c_outputStreamWriteWithoutStartThrows` | TEST542c: OutputStream write without start() throws | Tests/BifaciTests/StreamingAPITests.swift:437 |
| unnumbered | `test542d_outputStreamDoubleStartThrows` | TEST542d: OutputStream start() twice throws | Tests/BifaciTests/StreamingAPITests.swift:453 |
| unnumbered | `test542e_outputStreamModeConflictThrows` | TEST542e: OutputStream mode conflict throws (start write, call emitListItem) | Tests/BifaciTests/StreamingAPITests.swift:470 |
| unnumbered | `testAddCapAndBasicTraversal` | MARK: - Basic Tests (unnumbered, match Rust unnumbered tests) | Tests/CapDAGTests/CSLiveCapFabTests.m:32 |
| unnumbered | `testArgumentCreationWithNewAPI` |  | Tests/CapDAGTests/CSCapTests.m:776 |
| unnumbered | `testArgumentValidationWithUnknownSpecFails` | Obj-C specific: unresolved spec ID fails hard during schema validation | Tests/CapDAGTests/CSSchemaValidationTests.m:131 |
| unnumbered | `testBuilderBasicConstruction` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:16 |
| unnumbered | `testBuilderComplex` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:177 |
| unnumbered | `testBuilderCustomTags` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:70 |
| unnumbered | `testBuilderDirectionAccess` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:53 |
| unnumbered | `testBuilderDirectionMismatchNoMatch` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:302 |
| unnumbered | `testBuilderEmptyBuildFailsWithMissingInSpec` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:131 |
| unnumbered | `testBuilderFluentAPI` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:32 |
| unnumbered | `testBuilderMatchingWithBuiltCap` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:252 |
| unnumbered | `testBuilderMinimalValid` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:158 |
| unnumbered | `testBuilderMissingInSpecFails` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:105 |
| unnumbered | `testBuilderMissingOutSpecFails` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:118 |
| unnumbered | `testBuilderStaticFactory` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:243 |
| unnumbered | `testBuilderTagIgnoresInOut` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:140 |
| unnumbered | `testBuilderTagOverrides` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:88 |
| unnumbered | `testBuilderWildcards` |  | Tests/CapDAGTests/CSCapUrnBuilderTests.m:218 |
| unnumbered | `testBuiltinSpecIdsResolve` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:541 |
| unnumbered | `testCanonicalArgumentsDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:216 |
| unnumbered | `testCanonicalDictionaryDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:169 |
| unnumbered | `testCanonicalOutputDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:240 |
| unnumbered | `testCanonicalValidationDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:256 |
| unnumbered | `testCapAndForEachAreNotStandaloneCollect` |  | Tests/CapDAGTests/CSPlanDecompositionTests.m:75 |
| unnumbered | `testCapCreation` |  | Tests/CapDAGTests/CSCapTests.m:22 |
| unnumbered | `testCapDocumentationOmittedWhenNil` | When documentation is nil, toDictionary must omit the field entirely. This matches the Rust serializer's skip-when-None semantics and the JS toJSON behaviour. A regression where nil is emitted as `documentation: NSNull` (or simply not omitted) would break the symmetric round-trip with Rust. | Tests/CapDAGTests/CSCapTests.m:874 |
| unnumbered | `testCapDocumentationRoundTrip` | Mirrors TEST920 in capdag/src/cap/definition.rs and the JS testJS_capDocumentationRoundTrip test. The body is non-trivial — multi-line, embedded backticks and double quotes, Unicode dingbat (\u2605) — so any escaping mismatch between dictionary serialization here and the Rust / JS counterparts surfaces as a failed round-trip. | Tests/CapDAGTests/CSCapTests.m:835 |
| unnumbered | `testCapManifestCompatibility` |  | Tests/CapDAGTests/CSCapTests.m:721 |
| unnumbered | `testCapManifestCreation` | MARK: - Cap Manifest Tests | Tests/CapDAGTests/CSCapTests.m:427 |
| unnumbered | `testCapManifestDictionaryDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:522 |
| unnumbered | `testCapManifestEmptyCaps` |  | Tests/CapDAGTests/CSCapTests.m:635 |
| unnumbered | `testCapManifestOptionalAuthorField` |  | Tests/CapDAGTests/CSCapTests.m:663 |
| unnumbered | `testCapManifestRequiredFields` |  | Tests/CapDAGTests/CSCapTests.m:575 |
| unnumbered | `testCapManifestWithAuthor` |  | Tests/CapDAGTests/CSCapTests.m:460 |
| unnumbered | `testCapManifestWithMultipleCaps` |  | Tests/CapDAGTests/CSCapTests.m:588 |
| unnumbered | `testCapManifestWithPageUrl` |  | Tests/CapDAGTests/CSCapTests.m:490 |
| unnumbered | `testCapMatching` |  | Tests/CapDAGTests/CSCapTests.m:114 |
| unnumbered | `testCapStdinSerialization` |  | Tests/CapDAGTests/CSCapTests.m:139 |
| unnumbered | `testCapStdinType` |  | Tests/CapDAGTests/CSCapTests.m:70 |
| unnumbered | `testCapWithDescription` |  | Tests/CapDAGTests/CSCapTests.m:48 |
| unnumbered | `testCoding` | Obj-C specific: NSCoding support | Tests/CapDAGTests/CSCapUrnTests.m:505 |
| unnumbered | `testCompleteCapDeserialization` |  | Tests/CapDAGTests/CSCapTests.m:276 |
| unnumbered | `testComplexNestedSchema` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:404 |
| unnumbered | `testCopying` | Obj-C specific: NSCopying support | Tests/CapDAGTests/CSCapUrnTests.m:527 |
| unnumbered | `testDataSourceWithBinaryContent` |  | Tests/CapDAGTests/CSStdinSourceTests.m:61 |
| unnumbered | `testDataSourceWithEmptyData` |  | Tests/CapDAGTests/CSStdinSourceTests.m:51 |
| unnumbered | `testDeterministicOrdering` |  | Tests/CapDAGTests/CSLiveCapFabTests.m:100 |
| unnumbered | `testDotParserCapUrnLabel` | TEST: Parse cap URN label with escaped quotes | Tests/BifaciTests/OrchestratorTests.swift:413 |
| unnumbered | `testDotParserComments` | TEST: Parse graph with comments | Tests/BifaciTests/OrchestratorTests.swift:397 |
| unnumbered | `testDotParserEdgeWithLabel` | TEST: Parse edge with label attribute | Tests/BifaciTests/OrchestratorTests.swift:350 |
| unnumbered | `testDotParserNodeWithAttributes` | TEST: Parse node with attributes | Tests/BifaciTests/OrchestratorTests.swift:364 |
| unnumbered | `testDotParserQuotedIdentifiers` | TEST: Parse quoted identifiers | Tests/BifaciTests/OrchestratorTests.swift:381 |
| unnumbered | `testDotParserSimpleDigraph` | TEST: Parse simple digraph | Tests/BifaciTests/OrchestratorTests.swift:330 |
| unnumbered | `testExactVsConformanceMatching` |  | Tests/CapDAGTests/CSLiveCapFabTests.m:50 |
| unnumbered | `testExtensionsEmptyWhenNotSet` |  | Tests/CapDAGTests/CSMediaSpecTests.m:133 |
| unnumbered | `testExtensionsPropagationFromObjectDef` | Extensions field tests | Tests/CapDAGTests/CSMediaSpecTests.m:110 |
| unnumbered | `testExtensionsWithMetadataAndValidation` |  | Tests/CapDAGTests/CSMediaSpecTests.m:152 |
| unnumbered | `testFileReferenceWithAllFields` |  | Tests/CapDAGTests/CSStdinSourceTests.m:74 |
| unnumbered | `testFullCapValidationWithMediaSpecs` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:679 |
| unnumbered | `testGcEvictsOldestEntriesByTouchedAt` | / Contract #2 — the GC drops the OLDEST entries by / `touchedAt`, not arbitrary keys. We seed a known age / distribution and recompute the expected victim set / independently of the production code, then assert that / the post-GC table contains exactly the entries the test / computed should survive. / / A regression where the GC e.g. iterates the dictionary and / drops the first N entries (dictionary iteration order is / arbitrary in Swift) would still pass contract #1 but fail / this one — so this is the assertion that catches a "wrong / victims" bug, which is the more dangerous one (silently / drops in-flight continuation frames). | Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:108 |
| unnumbered | `testGcReducesTableBelowSoftWatermarkInOnePass` | / Contract #1 — the GC keeps the table strictly below the / hard cap. We seed the table well above the soft watermark / (matching what a runaway producer would do mid-frame-burst) / and call the production GC entry point. The post-state / must be at most `softWatermark` entries because the GC / drops at least `evictionFraction × pre-state` entries in / one pass and the pre-state is below `hardCap` (i.e. one / pass is enough; the secondary "hard cap" pass would only / kick in if pre-state crossed the hard cap before insertion / completed, which production prevents by gc-ing on every / insert). | Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:45 |
| unnumbered | `testGcSecondaryPassEnforcesHardCap` | / Contract #3 — the secondary "hard cap" pass kicks in if / the table somehow exceeds `hardCap` (e.g. a seed that goes / over, simulating an extreme runaway). Without the / secondary pass, a single GC at the soft watermark would / not be enough to recover headroom and the table could / grow without bound between bursts. | Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:172 |
| unnumbered | `testGetCapDefinitionReal` |  | Tests/CapDAGTests/CSFabricRegistryTests.m:115 |
| unnumbered | `testHostConstructsAndClosesWithoutAnObserver` |  | Tests/BifaciTests/CartridgeHostObserverTests.swift:53 |
| unnumbered | `testIntegrationWithInputValidation` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:263 |
| unnumbered | `testIntegrationWithOutputValidation` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:334 |
| unnumbered | `testInvalidCapUrn` | TEST001 variant: Test empty URN fails | Tests/CapDAGTests/CSCapUrnTests.m:104 |
| unnumbered | `testMediaSpecDocumentationPropagatesThroughResolve` | Documentation propagates from a mediaSpecs definition through CSResolveMediaUrn into the resolved CSMediaSpec. Mirrors TEST924 on the Rust side and testJS_mediaSpecDocumentationPropagatesThroughResolve on the JS side. | Tests/CapDAGTests/CSCapTests.m:911 |
| unnumbered | `testMediaSpecsResolution` |  | Tests/CapDAGTests/CSCapTests.m:361 |
| unnumbered | `testMediaSpecsWithoutSchemaSkipsValidation` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:595 |
| unnumbered | `testMetadataNilByDefault` |  | Tests/CapDAGTests/CSMediaSpecTests.m:44 |
| unnumbered | `testMetadataPropagationFromObjectDef` |  | Tests/CapDAGTests/CSMediaSpecTests.m:14 |
| unnumbered | `testMetadataWithValidation` |  | Tests/CapDAGTests/CSMediaSpecTests.m:62 |
| unnumbered | `testMultiStepPath` |  | Tests/CapDAGTests/CSLiveCapFabTests.m:80 |
| unnumbered | `testMultipleExtensions` |  | Tests/CapDAGTests/CSMediaSpecTests.m:184 |
| unnumbered | `testNewHostInstancePerRelaySession` | / Contract #2 (well-behaved path): one host → one run() → / drop. The misuse path (calling run() twice) is enforced via / `precondition` and is not death-tested here — the well- / behaved path is sufficient because if the precondition were / silently disabled, the prior test (`testRunExitKills…`) / would still pass on the first invocation but the second / call would race with itself and fail intermittently. This / test documents the contract by demonstrating that a fresh / `CartridgeHost` instance is the only correct way to start / a new relay session. | Tests/BifaciTests/CartridgeHostSessionLifecycleTests.swift:141 |
| unnumbered | `testNonStructuredArgumentSkipsSchemaValidation` | Obj-C specific: Non-structured argument skips schema validation | Tests/CapDAGTests/CSSchemaValidationTests.m:150 |
| unnumbered | `testNormalizeHandlesDifferentTagOrders` | / Test that different tag orders normalize to the same URL | Tests/CapDAGTests/CSFabricRegistryTests.m:102 |
| unnumbered | `testOutputCreationWithNewAPI` |  | Tests/CapDAGTests/CSCapTests.m:813 |
| unnumbered | `testOutputWithEmbeddedSchemaValidationFailure` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:222 |
| unnumbered | `testPressureAndKill` | / Single test: allocate 90% of RAM with incompressible CSPRNG data, monitor / memory, detect pressure (kernel or threshold), kill cartridge, verify death. / The goal is to overload the system — force the kernel into real pressure. | testcartridge-host/Sources/TestcartridgeHost/main.swift:288 |
| unnumbered | `testRegistryCreation` |  | Tests/CapDAGTests/CSFabricRegistryTests.m:40 |
| unnumbered | `testRegistryValidCapCheck` | Registry validator tests removed - not part of current API | Tests/CapDAGTests/CSFabricRegistryTests.m:47 |
| unnumbered | `testResolveMediaUrnNotFound` |  | Tests/CapDAGTests/CSMediaSpecTests.m:98 |
| unnumbered | `testRunExitKillsAllManagedCartridges` | / Contract #1: when `run()` exits because the relay closed, / every running cartridge is torn down and the observer is / fired with a death notification for each. The Rust reference / enforces this by calling `kill_all_cartridges().await` at / the very end of `run()`. The Swift mirror's previous / behavior was to leak cartridges across reconnects, which is / what allowed the XPC-service NSConcreteData accumulator bug. | Tests/BifaciTests/CartridgeHostSessionLifecycleTests.swift:66 |
| unnumbered | `testSchemaValidationErrorDetails` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:495 |
| unnumbered | `testSchemaValidationPerformance` |  | Tests/CapDAGTests/CSSchemaValidationTests.m:621 |
| unnumbered | `testSetObserverNilClearsThePreviouslyRegisteredObserver` |  | Tests/BifaciTests/CartridgeHostObserverTests.swift:62 |
| unnumbered | `testSourceWithData` |  | Tests/CapDAGTests/CSStdinSourceTests.m:14 |
| unnumbered | `testSourceWithFileReference` |  | Tests/CapDAGTests/CSStdinSourceTests.m:29 |
| unnumbered | `testStandaloneCollectNode` | MARK: - Standalone Collect Node Tests | Tests/CapDAGTests/CSPlanDecompositionTests.m:63 |
| unnumbered | `testSyncFromCaps` |  | Tests/CapDAGTests/CSLiveCapFabTests.m:124 |
| unnumbered | `testURLEncodesQuotedMediaUrns` | / Test that media URNs in cap URNs are properly URL-encoded | Tests/CapDAGTests/CSFabricRegistryTests.m:74 |
| unnumbered | `testURLFormatIsValid` | / Test the URL format is valid and can be parsed | Tests/CapDAGTests/CSFabricRegistryTests.m:85 |
| unnumbered | `testURLKeepsCapPrefixLiteral` | / Test that URL construction keeps "cap:" literal and only encodes the tags part | Tests/CapDAGTests/CSFabricRegistryTests.m:63 |
| unnumbered | `testValidateCapCanonical` |  | Tests/CapDAGTests/CSFabricRegistryTests.m:135 |
| unnumbered | `testValidateNoMediaSpecDuplicatesEmpty` |  | Tests/CapDAGTests/CSMediaSpecTests.m:241 |
| unnumbered | `testValidateNoMediaSpecDuplicatesFail` |  | Tests/CapDAGTests/CSMediaSpecTests.m:224 |
| unnumbered | `testValidateNoMediaSpecDuplicatesNil` |  | Tests/CapDAGTests/CSMediaSpecTests.m:250 |
| unnumbered | `testValidateNoMediaSpecDuplicatesPass` | Duplicate URN validation tests | Tests/CapDAGTests/CSMediaSpecTests.m:210 |
| unnumbered | `testWildcard001EmptyCapDefaultsToMediaWildcard` | TEST_WILDCARD_001: cap: (empty) defaults to in=media:;out=media: | Tests/CapDAGTests/CSCapUrnTests.m:1008 |
| unnumbered | `testWildcard002InOnlyDefaultsOutToMedia` | TEST_WILDCARD_002: cap:in defaults out to media: | Tests/CapDAGTests/CSCapUrnTests.m:1019 |
| unnumbered | `testWildcard003OutOnlyDefaultsInToMedia` | TEST_WILDCARD_003: cap:out defaults in to media: | Tests/CapDAGTests/CSCapUrnTests.m:1028 |
| unnumbered | `testWildcard004InOutNoValuesBecomeMedia` | TEST_WILDCARD_004: cap:in;out both become media: | Tests/CapDAGTests/CSCapUrnTests.m:1037 |
| unnumbered | `testWildcard005ExplicitAsteriskBecomesMedia` | TEST_WILDCARD_005: cap:in=*;out=* becomes media: | Tests/CapDAGTests/CSCapUrnTests.m:1046 |
| unnumbered | `testWildcard006SpecificInWildcardOut` | TEST_WILDCARD_006: cap:in=media:;out=* has specific in, wildcard out | Tests/CapDAGTests/CSCapUrnTests.m:1055 |
| unnumbered | `testWildcard007WildcardInSpecificOut` | TEST_WILDCARD_007: cap:in=*;out=media:text has wildcard in, specific out | Tests/CapDAGTests/CSCapUrnTests.m:1064 |
| unnumbered | `testWildcard008InvalidInSpecFails` | TEST_WILDCARD_008: cap:in=foo fails (invalid media URN) | Tests/CapDAGTests/CSCapUrnTests.m:1073 |
| unnumbered | `testWildcard009InvalidOutSpecFails` | TEST_WILDCARD_009: cap:in=media:;out=bar fails (invalid media URN) | Tests/CapDAGTests/CSCapUrnTests.m:1082 |
| unnumbered | `testWildcard010WildcardAcceptsSpecific` | TEST_WILDCARD_010: Wildcard in/out match specific caps | Tests/CapDAGTests/CSCapUrnTests.m:1091 |
| unnumbered | `testWildcard011SpecificityScoring` | TEST_WILDCARD_011: Specificity - wildcard has 0, specific has tag count | Tests/CapDAGTests/CSCapUrnTests.m:1101 |
| unnumbered | `testWildcard012PreserveOtherTags` | TEST_WILDCARD_012: cap:in=media:;out=media:;test preserves other tags | Tests/CapDAGTests/CSCapUrnTests.m:1111 |
| unnumbered | `test_csCapManifestRejectsUnknownChannel` | Channel is part of the cartridge's identity; the deserializer accepts the closed enum {release, nightly} only. Anything else is a publish-pipeline bug we want to surface. | Tests/BifaciTests/ManifestTests.swift:247 |
| unnumbered | `test_csCapManifestWithPageUrl` | MARK: - CSCapManifest With PageUrl Test | Tests/BifaciTests/ManifestTests.swift:231 |
| unnumbered | `test_glob_pattern_detection` | Mirror-specific: glob pattern detection is an objc-only helper used by the resolver internals. Rust uses globwalk; these checks exercise the BSD glob detection logic. | Tests/CapDAGTests/CSInputResolverTests.m:477 |
| unnumbered | `test_resolved_input_set_total_size` | Mirror-specific: CSResolvedInputSet aggregates totalSize across files | Tests/CapDAGTests/CSInputResolverTests.m:486 |
| unnumbered | `testconcatenatedVsFinalPayloadDivergence` | Mirror-specific coverage: concatenated() returns full payload while finalPayload returns only last chunk | Tests/BifaciTests/RuntimeTests.swift:1105 |
| unnumbered | `testmanifestEnsureIdentityIdempotent` | Mirror-specific coverage: Manifest.ensureIdentity() adds if missing, idempotent if present | Tests/BifaciTests/StandardCapsTests.swift:71 |
| unnumbered | `testparseFanInPattern` | Mirror-specific coverage: Parse fan-in pattern | Tests/BifaciTests/OrchestratorTests.swift:138 |
| unnumbered | `testrejectCycles` | Mirror-specific coverage: Validate that cycles are rejected | Tests/BifaciTests/OrchestratorTests.swift:163 |
---

## Unnumbered Tests

The following tests are cataloged but do not currently participate in numeric test indexing.

- `test198b_limitsNegotiation` — Tests/BifaciTests/FrameTests.swift:307
- `test205b_allFrameTypesRoundtrip` — Tests/BifaciTests/FrameTests.swift:894
- `test389b_streamStartIsSequenceRoundtrip` — Tests/BifaciTests/FrameTests.swift:1091
- `test542b_outputStreamStartThenCloseEmpty` — Tests/BifaciTests/StreamingAPITests.swift:407
- `test542c_outputStreamWriteWithoutStartThrows` — Tests/BifaciTests/StreamingAPITests.swift:437
- `test542d_outputStreamDoubleStartThrows` — Tests/BifaciTests/StreamingAPITests.swift:453
- `test542e_outputStreamModeConflictThrows` — Tests/BifaciTests/StreamingAPITests.swift:470
- `testAddCapAndBasicTraversal` — Tests/CapDAGTests/CSLiveCapFabTests.m:32
- `testArgumentCreationWithNewAPI` — Tests/CapDAGTests/CSCapTests.m:776
- `testArgumentValidationWithUnknownSpecFails` — Tests/CapDAGTests/CSSchemaValidationTests.m:131
- `testBuilderBasicConstruction` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:16
- `testBuilderComplex` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:177
- `testBuilderCustomTags` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:70
- `testBuilderDirectionAccess` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:53
- `testBuilderDirectionMismatchNoMatch` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:302
- `testBuilderEmptyBuildFailsWithMissingInSpec` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:131
- `testBuilderFluentAPI` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:32
- `testBuilderMatchingWithBuiltCap` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:252
- `testBuilderMinimalValid` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:158
- `testBuilderMissingInSpecFails` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:105
- `testBuilderMissingOutSpecFails` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:118
- `testBuilderStaticFactory` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:243
- `testBuilderTagIgnoresInOut` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:140
- `testBuilderTagOverrides` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:88
- `testBuilderWildcards` — Tests/CapDAGTests/CSCapUrnBuilderTests.m:218
- `testBuiltinSpecIdsResolve` — Tests/CapDAGTests/CSSchemaValidationTests.m:541
- `testCanonicalArgumentsDeserialization` — Tests/CapDAGTests/CSCapTests.m:216
- `testCanonicalDictionaryDeserialization` — Tests/CapDAGTests/CSCapTests.m:169
- `testCanonicalOutputDeserialization` — Tests/CapDAGTests/CSCapTests.m:240
- `testCanonicalValidationDeserialization` — Tests/CapDAGTests/CSCapTests.m:256
- `testCapAndForEachAreNotStandaloneCollect` — Tests/CapDAGTests/CSPlanDecompositionTests.m:75
- `testCapCreation` — Tests/CapDAGTests/CSCapTests.m:22
- `testCapDocumentationOmittedWhenNil` — Tests/CapDAGTests/CSCapTests.m:874
- `testCapDocumentationRoundTrip` — Tests/CapDAGTests/CSCapTests.m:835
- `testCapManifestCompatibility` — Tests/CapDAGTests/CSCapTests.m:721
- `testCapManifestCreation` — Tests/CapDAGTests/CSCapTests.m:427
- `testCapManifestDictionaryDeserialization` — Tests/CapDAGTests/CSCapTests.m:522
- `testCapManifestEmptyCaps` — Tests/CapDAGTests/CSCapTests.m:635
- `testCapManifestOptionalAuthorField` — Tests/CapDAGTests/CSCapTests.m:663
- `testCapManifestRequiredFields` — Tests/CapDAGTests/CSCapTests.m:575
- `testCapManifestWithAuthor` — Tests/CapDAGTests/CSCapTests.m:460
- `testCapManifestWithMultipleCaps` — Tests/CapDAGTests/CSCapTests.m:588
- `testCapManifestWithPageUrl` — Tests/CapDAGTests/CSCapTests.m:490
- `testCapMatching` — Tests/CapDAGTests/CSCapTests.m:114
- `testCapStdinSerialization` — Tests/CapDAGTests/CSCapTests.m:139
- `testCapStdinType` — Tests/CapDAGTests/CSCapTests.m:70
- `testCapWithDescription` — Tests/CapDAGTests/CSCapTests.m:48
- `testCoding` — Tests/CapDAGTests/CSCapUrnTests.m:505
- `testCompleteCapDeserialization` — Tests/CapDAGTests/CSCapTests.m:276
- `testComplexNestedSchema` — Tests/CapDAGTests/CSSchemaValidationTests.m:404
- `testCopying` — Tests/CapDAGTests/CSCapUrnTests.m:527
- `testDataSourceWithBinaryContent` — Tests/CapDAGTests/CSStdinSourceTests.m:61
- `testDataSourceWithEmptyData` — Tests/CapDAGTests/CSStdinSourceTests.m:51
- `testDeterministicOrdering` — Tests/CapDAGTests/CSLiveCapFabTests.m:100
- `testDotParserCapUrnLabel` — Tests/BifaciTests/OrchestratorTests.swift:413
- `testDotParserComments` — Tests/BifaciTests/OrchestratorTests.swift:397
- `testDotParserEdgeWithLabel` — Tests/BifaciTests/OrchestratorTests.swift:350
- `testDotParserNodeWithAttributes` — Tests/BifaciTests/OrchestratorTests.swift:364
- `testDotParserQuotedIdentifiers` — Tests/BifaciTests/OrchestratorTests.swift:381
- `testDotParserSimpleDigraph` — Tests/BifaciTests/OrchestratorTests.swift:330
- `testExactVsConformanceMatching` — Tests/CapDAGTests/CSLiveCapFabTests.m:50
- `testExtensionsEmptyWhenNotSet` — Tests/CapDAGTests/CSMediaSpecTests.m:133
- `testExtensionsPropagationFromObjectDef` — Tests/CapDAGTests/CSMediaSpecTests.m:110
- `testExtensionsWithMetadataAndValidation` — Tests/CapDAGTests/CSMediaSpecTests.m:152
- `testFileReferenceWithAllFields` — Tests/CapDAGTests/CSStdinSourceTests.m:74
- `testFullCapValidationWithMediaSpecs` — Tests/CapDAGTests/CSSchemaValidationTests.m:679
- `testGcEvictsOldestEntriesByTouchedAt` — Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:108
- `testGcReducesTableBelowSoftWatermarkInOnePass` — Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:45
- `testGcSecondaryPassEnforcesHardCap` — Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:172
- `testGetCapDefinitionReal` — Tests/CapDAGTests/CSFabricRegistryTests.m:115
- `testHostConstructsAndClosesWithoutAnObserver` — Tests/BifaciTests/CartridgeHostObserverTests.swift:53
- `testIntegrationWithInputValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:263
- `testIntegrationWithOutputValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:334
- `testInvalidCapUrn` — Tests/CapDAGTests/CSCapUrnTests.m:104
- `testMediaSpecDocumentationPropagatesThroughResolve` — Tests/CapDAGTests/CSCapTests.m:911
- `testMediaSpecsResolution` — Tests/CapDAGTests/CSCapTests.m:361
- `testMediaSpecsWithoutSchemaSkipsValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:595
- `testMetadataNilByDefault` — Tests/CapDAGTests/CSMediaSpecTests.m:44
- `testMetadataPropagationFromObjectDef` — Tests/CapDAGTests/CSMediaSpecTests.m:14
- `testMetadataWithValidation` — Tests/CapDAGTests/CSMediaSpecTests.m:62
- `testMultiStepPath` — Tests/CapDAGTests/CSLiveCapFabTests.m:80
- `testMultipleExtensions` — Tests/CapDAGTests/CSMediaSpecTests.m:184
- `testNewHostInstancePerRelaySession` — Tests/BifaciTests/CartridgeHostSessionLifecycleTests.swift:141
- `testNonStructuredArgumentSkipsSchemaValidation` — Tests/CapDAGTests/CSSchemaValidationTests.m:150
- `testNormalizeHandlesDifferentTagOrders` — Tests/CapDAGTests/CSFabricRegistryTests.m:102
- `testOutputCreationWithNewAPI` — Tests/CapDAGTests/CSCapTests.m:813
- `testOutputWithEmbeddedSchemaValidationFailure` — Tests/CapDAGTests/CSSchemaValidationTests.m:222
- `testPressureAndKill` — testcartridge-host/Sources/TestcartridgeHost/main.swift:288
- `testRegistryCreation` — Tests/CapDAGTests/CSFabricRegistryTests.m:40
- `testRegistryValidCapCheck` — Tests/CapDAGTests/CSFabricRegistryTests.m:47
- `testResolveMediaUrnNotFound` — Tests/CapDAGTests/CSMediaSpecTests.m:98
- `testRunExitKillsAllManagedCartridges` — Tests/BifaciTests/CartridgeHostSessionLifecycleTests.swift:66
- `testSchemaValidationErrorDetails` — Tests/CapDAGTests/CSSchemaValidationTests.m:495
- `testSchemaValidationPerformance` — Tests/CapDAGTests/CSSchemaValidationTests.m:621
- `testSetObserverNilClearsThePreviouslyRegisteredObserver` — Tests/BifaciTests/CartridgeHostObserverTests.swift:62
- `testSourceWithData` — Tests/CapDAGTests/CSStdinSourceTests.m:14
- `testSourceWithFileReference` — Tests/CapDAGTests/CSStdinSourceTests.m:29
- `testStandaloneCollectNode` — Tests/CapDAGTests/CSPlanDecompositionTests.m:63
- `testSyncFromCaps` — Tests/CapDAGTests/CSLiveCapFabTests.m:124
- `testURLEncodesQuotedMediaUrns` — Tests/CapDAGTests/CSFabricRegistryTests.m:74
- `testURLFormatIsValid` — Tests/CapDAGTests/CSFabricRegistryTests.m:85
- `testURLKeepsCapPrefixLiteral` — Tests/CapDAGTests/CSFabricRegistryTests.m:63
- `testValidateCapCanonical` — Tests/CapDAGTests/CSFabricRegistryTests.m:135
- `testValidateNoMediaSpecDuplicatesEmpty` — Tests/CapDAGTests/CSMediaSpecTests.m:241
- `testValidateNoMediaSpecDuplicatesFail` — Tests/CapDAGTests/CSMediaSpecTests.m:224
- `testValidateNoMediaSpecDuplicatesNil` — Tests/CapDAGTests/CSMediaSpecTests.m:250
- `testValidateNoMediaSpecDuplicatesPass` — Tests/CapDAGTests/CSMediaSpecTests.m:210
- `testWildcard001EmptyCapDefaultsToMediaWildcard` — Tests/CapDAGTests/CSCapUrnTests.m:1008
- `testWildcard002InOnlyDefaultsOutToMedia` — Tests/CapDAGTests/CSCapUrnTests.m:1019
- `testWildcard003OutOnlyDefaultsInToMedia` — Tests/CapDAGTests/CSCapUrnTests.m:1028
- `testWildcard004InOutNoValuesBecomeMedia` — Tests/CapDAGTests/CSCapUrnTests.m:1037
- `testWildcard005ExplicitAsteriskBecomesMedia` — Tests/CapDAGTests/CSCapUrnTests.m:1046
- `testWildcard006SpecificInWildcardOut` — Tests/CapDAGTests/CSCapUrnTests.m:1055
- `testWildcard007WildcardInSpecificOut` — Tests/CapDAGTests/CSCapUrnTests.m:1064
- `testWildcard008InvalidInSpecFails` — Tests/CapDAGTests/CSCapUrnTests.m:1073
- `testWildcard009InvalidOutSpecFails` — Tests/CapDAGTests/CSCapUrnTests.m:1082
- `testWildcard010WildcardAcceptsSpecific` — Tests/CapDAGTests/CSCapUrnTests.m:1091
- `testWildcard011SpecificityScoring` — Tests/CapDAGTests/CSCapUrnTests.m:1101
- `testWildcard012PreserveOtherTags` — Tests/CapDAGTests/CSCapUrnTests.m:1111
- `test_csCapManifestRejectsUnknownChannel` — Tests/BifaciTests/ManifestTests.swift:247
- `test_csCapManifestWithPageUrl` — Tests/BifaciTests/ManifestTests.swift:231
- `test_glob_pattern_detection` — Tests/CapDAGTests/CSInputResolverTests.m:477
- `test_resolved_input_set_total_size` — Tests/CapDAGTests/CSInputResolverTests.m:486
- `testconcatenatedVsFinalPayloadDivergence` — Tests/BifaciTests/RuntimeTests.swift:1105
- `testmanifestEnsureIdentityIdempotent` — Tests/BifaciTests/StandardCapsTests.swift:71
- `testparseFanInPattern` — Tests/BifaciTests/OrchestratorTests.swift:138
- `testrejectCycles` — Tests/BifaciTests/OrchestratorTests.swift:163

---

## Numbered Tests Missing Descriptions

These tests still participate in numeric indexing, but the cataloger did not find an authoritative immediate comment/docstring description for them. This is reported explicitly so intentional blank-description parity and accidental comment drift are both visible.

- `test1830` / `test1830_canonicalize_no_constraint` — Tests/CapDAGTests/CSCapUrnTests.m:1631
- `test1832` / `test1832_canonicalize_must_have_any` — Tests/CapDAGTests/CSCapUrnTests.m:1664
- `test1834` / `test1834_canonicalize_exact_value` — Tests/CapDAGTests/CSCapUrnTests.m:1697
- `test1835` / `test1835_canonicalize_must_not_have` — Tests/CapDAGTests/CSCapUrnTests.m:1704

---

*Generated from Swift/ObjC source tree*
*Total tests: 785*
*Total numbered tests: 658*
*Total unnumbered tests: 127*
*Total numbered tests missing descriptions: 4*
*Total numbering mismatches: 0*
