# CapDag-ObjC/Swift Test Catalog

**Total Tests:** 386

All test numbers are unique.

This catalog lists all numbered tests in the CapDag-ObjC/Swift codebase.

| Test # | Function Name | Description | File |
|--------|---------------|-------------|------|
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
| test839 | `test839_peerResponseDeliversLogsBeforeStreamStart` | TEST839: LOG frames arriving BEFORE StreamStart are delivered immediately | Tests/BifaciTests/StreamingAPITests.swift:662 |
| test840 | `test840_peerResponseCollectBytesDiscardsLogs` | TEST840: PeerResponse.collectBytes() discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:733 |
| test841 | `test841_peerResponseCollectValueDiscardsLogs` | TEST841: PeerResponse.collectValue() discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:763 |
| test842 | `test842_runWithKeepaliveReturnsResult` | TEST842: runWithKeepalive returns closure result (fast operation, no keepalive frames) | Tests/BifaciTests/StreamingAPITests.swift:794 |
| test843 | `test843_runWithKeepaliveReturnsResultType` | TEST843: runWithKeepalive returns Ok/Err from closure | Tests/BifaciTests/StreamingAPITests.swift:817 |
| test844 | `test844_runWithKeepalivePropagatesError` | TEST844: runWithKeepalive propagates error from closure | Tests/BifaciTests/StreamingAPITests.swift:835 |
| test845 | `test845_progressSenderEmitsFrames` | TEST845: ProgressSender emits progress and log frames independently of OutputStream | Tests/BifaciTests/StreamingAPITests.swift:863 |
| test846 | `test846_progressFrameRoundtrip` | TEST846: Progress LOG frame encode/decode roundtrip preserves progress float | Tests/BifaciTests/FrameTests.swift:1715 |
| test847 | `test847_progressDoubleRoundtrip` | TEST847: Double roundtrip (encode→decode→modify→encode→decode) preserves progress float | Tests/BifaciTests/FrameTests.swift:1752 |
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

---

*Generated from CapDag-ObjC/Swift source tree*
*Total numbered tests: 386*
