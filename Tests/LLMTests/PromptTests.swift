import XCTest
@testable import LLM

/// Pin the prompt-classification contract. Mirror of
/// `capdag_cartridge_sdk::prompt::tests` on the Rust side.
/// Misclassification produces seed-locked degenerate output:
///   - templated-as-raw → instruct model collapses to its high-prior
///     continuation (PDF-page summarisation produced math-problem
///     completions because the prompt body was missing or replaced
///     by a numeric default; both ends of that bug exist
///     independently).
///   - raw-as-templated → base model tokenizes `<|im_start|>` etc.
///     as plain characters and corrupts the completion.
final class PromptTests: XCTestCase {

    private func dims(chatTemplate: String) -> RefinedDims {
        RefinedDims(chatTemplate: chatTemplate, family: "", modelTask: "")
    }

    // TEST0004: Jinja template routes to chat templated
    func test0004_JinjaTemplateRoutesToChatTemplated() {
        let s = classifyPrompt(
            dims: dims(chatTemplate: "chat-template-jinja"),
            user: "summarise this",
            system: "you are helpful"
        )
        if case .chatTemplated(let system, let user) = s {
            XCTAssertEqual(system, "you are helpful")
            XCTAssertEqual(user, "summarise this")
        } else {
            XCTFail("expected chatTemplated, got \(s)")
        }
    }

    // TEST0005: Short name template routes to chat templated
    func test0005_ShortNameTemplateRoutesToChatTemplated() {
        let s = classifyPrompt(
            dims: dims(chatTemplate: "chat-template-short"),
            user: "input",
            system: nil
        )
        if case .chatTemplated(let system, let user) = s {
            XCTAssertNil(system)
            XCTAssertEqual(user, "input")
        } else {
            XCTFail("expected chatTemplated, got \(s)")
        }
    }

    /// **Core regression guard.** Empty `chat_template` means a
    /// base / completion model — the cartridge MUST NOT
    /// chat-template the input. Routing the other way (raw model
    /// into chat-template rendering) would corrupt the completion.
    func test0006_AbsentTemplateRoutesToRaw() {
        let s = classifyPrompt(
            dims: dims(chatTemplate: ""),
            user: "the rest of the story is",
            system: "ignored — base models have no system slot"
        )
        if case .raw(let text) = s {
            XCTAssertEqual(text, "the rest of the story is")
        } else {
            XCTFail("expected raw, got \(s)")
        }
    }

    // TEST0007: Whitespace only system prompt dropped
    func test0007_WhitespaceOnlySystemPromptDropped() {
        for sysIn in ["", "   ", "\n\t\n"] {
            let s = classifyPrompt(
                dims: dims(chatTemplate: "chat-template-jinja"),
                user: "u",
                system: sysIn
            )
            if case .chatTemplated(let system, _) = s {
                XCTAssertNil(
                    system,
                    "whitespace-only system='\(sysIn)' must drop to nil so the chat template doesn't render an empty system envelope"
                )
            } else {
                XCTFail("expected chatTemplated, got \(s)")
            }
        }
    }

    // TEST0008: Unknown chat template tag routes to raw
    func test0008_UnknownChatTemplateTagRoutesToRaw() {
        let s = classifyPrompt(
            dims: dims(chatTemplate: "chat-template-some-future-tag"),
            user: "u",
            system: "s"
        )
        if case .raw(let text) = s {
            XCTAssertEqual(text, "u")
        } else {
            XCTFail("expected raw for unknown tag, got \(s)")
        }
    }

    /// `DEFAULT_SYSTEM_PROMPT` must remain task-agnostic — biases
    /// toward code / summarisation / translation would silently
    /// derail unrelated downstream uses. Mirrors the parallel test
    /// in the Rust SDK so drift between the two literals is caught.
    func test0009_DefaultSystemPromptIsTaskAgnostic() {
        XCTAssertTrue(DEFAULT_SYSTEM_PROMPT.contains("helpful"))
        XCTAssertTrue(DEFAULT_SYSTEM_PROMPT.contains("respond"))
        let lower = DEFAULT_SYSTEM_PROMPT.lowercased()
        XCTAssertFalse(
            lower.contains("code"),
            "default prompt must NOT bias toward code: '\(DEFAULT_SYSTEM_PROMPT)'"
        )
        XCTAssertFalse(
            lower.contains("summari"),
            "default prompt must NOT bias toward summarisation: '\(DEFAULT_SYSTEM_PROMPT)'"
        )
        XCTAssertFalse(
            lower.contains("translat"),
            "default prompt must NOT bias toward translation: '\(DEFAULT_SYSTEM_PROMPT)'"
        )
    }
}
