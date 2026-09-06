// Prompt preparation for instruction-tuned ML models with a textual
// prompt surface (LLMs, vision-language models, OCR models that accept
// chat-formatted directives).
//
// Mirror of the Rust SDK's `capdag_cartridge_sdk::prompt` module.
// Every change here MUST be reflected on the Rust side and
// vice-versa — drift between the two implementations re-opens the
// gibberish-output bug class (instruct model fed raw text falling
// back to its high-prior continuation, which produced the original
// "all outputs are math problems" failure on PDF-page summarisation).
//
// The decision layer is shared. Rendering is per-cartridge because
// each backend's chat-template machinery differs:
//   - llama.cpp's `apply_chat_template` (gguf)
//   - tokenizers crate / minijinja (candle)
//   - MLXLMCommon's `Chat.Message` + per-architecture `MessageGenerator`
//
// This file defines the dispatch contract. Cartridges read the
// model's refined dim profile from the `cap:download-model`
// response, build a `RefinedDims` view, call `classifyPrompt(_,_,_)`,
// and dispatch on the returned `PromptStrategy`.

import Foundation

/// Default system prompt baked into every text-generation /
/// vision-describe cap when the operator doesn't supply one. Generic
/// enough to frame any input — code, prose, JSON, transcripts,
/// images — as a request for a useful response. Concrete prompts
/// (summarise, translate, explain, transcribe) belong in the
/// user-message turn.
///
/// Kept in sync with `capdag_cartridge_sdk::prompt::DEFAULT_SYSTEM_PROMPT`
/// on the Rust side. Swift cartridges can't depend on the Rust SDK
/// so the constant is duplicated as a literal — the Swift SDK
/// `PromptTests.test0009_DefaultSystemPromptIsTaskAgnostic` and the Rust
/// SDK test of the same name catch drift.
public let DEFAULT_SYSTEM_PROMPT =
    "You are a helpful assistant. Respond to the user's input with a useful, accurate, " +
    "and concise reply. If the input is a document or excerpt, treat it as the subject " +
    "of the user's request and respond about it."

/// The dim profile of a downloaded model — the subset of the
/// `RefinedModelSpec` wire response that affects prompt preparation.
///
/// Constructed by the consumer cartridge from the response it gets
/// back from `cap:download-model`. Strings are the kebab-case dim
/// values (`"chat-template-jinja"`, `"chat-template-short"`, `""`
/// for absent) — same wire form as the `media:model-spec` URN tags.
public struct RefinedDims: Sendable {
    /// `chat_template` field from the wire `RefinedModelSpec`. Empty
    /// string means the model carries no chat template (a base /
    /// completion model).
    public let chatTemplate: String

    /// `family` field — used by future family-specific quirks. Not
    /// consulted by `classifyPrompt` today; carried so cartridges
    /// can branch on family without re-deriving it.
    public let family: String

    /// `model_task` field — `llm` / `vision` / `embeddings` / etc.
    /// `classifyPrompt` doesn't read it; carried for completeness
    /// and future use.
    public let modelTask: String

    public init(chatTemplate: String, family: String, modelTask: String) {
        self.chatTemplate = chatTemplate
        self.family = family
        self.modelTask = modelTask
    }
}

/// What `classifyPrompt` says the cartridge should do with the
/// user's prompt before feeding it to the model's tokenizer.
///
/// The variant carries everything the renderer needs; the cartridge
/// hands the rendered string (or, for MLX, a `Chat.Message` array)
/// to its backend's tokenizer with the matching special-token-parsing
/// flag.
public enum PromptStrategy: Sendable {
    /// The model expects chat-formatted input. The cartridge MUST
    /// render the system + user messages through the model's
    /// chat-template machinery, then tokenize the rendered string
    /// with `parse_specials = true`. The shared classifier returns
    /// the raw turn texts; the cartridge owns the rendering surface
    /// because each backend's API differs.
    case chatTemplated(system: String?, user: String)

    /// The model has no chat template. Tokenize the user's text as
    /// a raw completion prompt. A system prompt (if any) is dropped
    /// — base models have no notion of system messages, and
    /// prepending one as plain text would corrupt the
    /// completion-style invocation.
    case raw(text: String)
}

/// Classify how to prepare a user prompt given the model's detected
/// dims and an optional system prompt. Mirrors
/// `capdag_cartridge_sdk::prompt::classify_prompt`.
///
/// `system` is the system prompt to use:
///   - non-nil and non-whitespace — render as the system turn
///     (chat-templated path) or drop (raw path).
///   - `nil`, `""`, or whitespace-only — no system message; the
///     caller did not want one. The cap surface should fall back
///     to `DEFAULT_SYSTEM_PROMPT` before calling here when it does
///     want one.
///
/// `user` is the user's prompt text. Empty `user` is the caller's
/// bug; this function does not check for it because the cap surface
/// already declares the prompt arg as required.
///
/// The chat-template axis values that route to `chatTemplated`:
///   - `"chat-template-jinja"`
///   - `"chat-template-short"`
///
/// Empty (`""`, including the catalog's `"chat-template-absent"`
/// value being normalised to empty before classification) routes to
/// `raw`. Any other value also routes to `raw` on conservative
/// grounds: an unknown future template tag must NOT silently get
/// fed through chat-formatting that doesn't apply.
public func classifyPrompt(dims: RefinedDims, user: String, system: String?) -> PromptStrategy {
    switch dims.chatTemplate {
    case "chat-template-jinja", "chat-template-short":
        let cleaned: String? = {
            guard let s = system else { return nil }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : s
        }()
        return .chatTemplated(system: cleaned, user: user)
    default:
        return .raw(text: user)
    }
}
