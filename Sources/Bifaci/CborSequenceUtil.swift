//
//  CborSequenceUtil.swift
//  Bifaci
//
//  RFC 8742 CBOR Sequence split/assemble utilities.
//
//  A CBOR sequence is a concatenation of independently-encoded CBOR data items
//  with no array wrapper. Each item is a complete, self-delimiting CBOR value.
//  This is the canonical format for list-tagged media URN data in the DAG.

import Foundation
@preconcurrency import SwiftCBOR

/// Errors from CBOR sequence operations.
public enum CborSequenceError: Error, LocalizedError {
    case emptySequence
    case deserializationError(String)
    case serializationError(String)

    public var errorDescription: String? {
        switch self {
        case .emptySequence: return "Empty CBOR sequence — nothing to split"
        case .deserializationError(let msg): return "CBOR deserialization error: \(msg)"
        case .serializationError(let msg): return "CBOR serialization error: \(msg)"
        }
    }
}

/// Split an RFC 8742 CBOR sequence into individually-serialized CBOR items.
///
/// A CBOR sequence is a concatenation of independently-encoded CBOR data items.
/// This function iterates through the sequence by decoding values one at a time
/// from the byte stream, tracking exact byte consumption.
///
/// Returns each item as its independent CBOR-encoded `Data`.
///
/// - Parameter data: The raw bytes of a CBOR sequence
/// - Returns: Array of individually-encoded CBOR items
/// - Throws: `CborSequenceError.emptySequence` if input is empty,
///           `CborSequenceError.deserializationError` if any value is malformed
public func splitCborSequence(_ data: Data) throws -> [Data] {
    if data.isEmpty {
        throw CborSequenceError.emptySequence
    }

    let bytes = [UInt8](data)
    var items: [Data] = []
    var offset = 0

    while offset < bytes.count {
        let remaining = Array(bytes[offset...])
        let decoder = CBORDecoder(input: remaining)

        let decoded: CBOR?
        do {
            decoded = try decoder.decodeItem()
        } catch {
            throw CborSequenceError.deserializationError(
                "Failed to decode CBOR value at offset \(offset) (\(bytes.count - offset) bytes remaining): \(error)"
            )
        }

        guard let value = decoded else {
            throw CborSequenceError.deserializationError(
                "Unexpected nil CBOR item at offset \(offset)"
            )
        }

        // Re-encode the decoded value to get the canonical serialized form
        let encoded = value.encode()
        items.append(Data(encoded))
        offset += encoded.count
    }

    if items.isEmpty {
        throw CborSequenceError.emptySequence
    }

    return items
}

/// Assemble individually-serialized CBOR items into an RFC 8742 CBOR sequence.
///
/// Each input item must be a complete CBOR value. The result is their raw
/// concatenation (no array wrapper). This is the inverse of `splitCborSequence`.
///
/// - Parameter items: Array of individually-encoded CBOR items
/// - Returns: The concatenated CBOR sequence bytes
/// - Throws: `CborSequenceError.deserializationError` if any item is not valid CBOR
public func assembleCborSequence(_ items: [Data]) throws -> Data {
    var result = Data()
    for (i, item) in items.enumerated() {
        // Validate each item is valid CBOR
        guard let _ = try? CBOR.decode([UInt8](item)) else {
            throw CborSequenceError.deserializationError("Item \(i): not valid CBOR")
        }
        result.append(item)
    }
    return result
}
