import Foundation

/// Per-token USD prices for one model family.
struct ModelPrice {
    let input: Double
    let output: Double
    let cacheCreation: Double
    let cacheRead: Double
}

/// Static pricing table, snapshotted from LiteLLM's
/// `model_prices_and_context_window.json` (2026-06-13). Values are USD per token.
///
/// Lookup uses longest-prefix matching on the model id (after stripping provider /
/// region prefixes such as `anthropic.` or `us.anthropic.`), so dated ids like
/// `claude-haiku-4-5-20251001` resolve through the `claude-haiku-4-5` prefix.
/// Unknown models price at $0 and are surfaced as "unpriced" in the UI.
enum PricingTable {
    static let prices: [String: ModelPrice] = [
        "claude-fable-5": ModelPrice(input: 1e-05, output: 5e-05, cacheCreation: 1.25e-05, cacheRead: 1e-06),
        "claude-opus-4-8": ModelPrice(input: 5e-06, output: 2.5e-05, cacheCreation: 6.25e-06, cacheRead: 5e-07),
        "claude-opus-4-7": ModelPrice(input: 5e-06, output: 2.5e-05, cacheCreation: 6.25e-06, cacheRead: 5e-07),
        "claude-opus-4-6": ModelPrice(input: 5e-06, output: 2.5e-05, cacheCreation: 6.25e-06, cacheRead: 5e-07),
        "claude-opus-4-5": ModelPrice(input: 5e-06, output: 2.5e-05, cacheCreation: 6.25e-06, cacheRead: 5e-07),
        "claude-opus-4-1": ModelPrice(input: 1.5e-05, output: 7.5e-05, cacheCreation: 1.875e-05, cacheRead: 1.5e-06),
        "claude-opus-4": ModelPrice(input: 1.5e-05, output: 7.5e-05, cacheCreation: 1.875e-05, cacheRead: 1.5e-06),
        "claude-sonnet-4-6": ModelPrice(input: 3e-06, output: 1.5e-05, cacheCreation: 3.75e-06, cacheRead: 3e-07),
        "claude-sonnet-4-5": ModelPrice(input: 3e-06, output: 1.5e-05, cacheCreation: 3.75e-06, cacheRead: 3e-07),
        "claude-sonnet-4": ModelPrice(input: 3e-06, output: 1.5e-05, cacheCreation: 3.75e-06, cacheRead: 3e-07),
        "claude-haiku-4-5": ModelPrice(input: 1e-06, output: 5e-06, cacheCreation: 1.25e-06, cacheRead: 1e-07),
        "claude-3-7-sonnet": ModelPrice(input: 3e-06, output: 1.5e-05, cacheCreation: 3.75e-06, cacheRead: 3e-07),
        "claude-3-5-sonnet": ModelPrice(input: 3e-06, output: 1.5e-05, cacheCreation: 3.75e-06, cacheRead: 3e-07),
        "claude-3-5-haiku": ModelPrice(input: 8e-07, output: 4e-06, cacheCreation: 1e-06, cacheRead: 8e-08),
        "claude-3-opus": ModelPrice(input: 1.5e-05, output: 7.5e-05, cacheCreation: 1.875e-05, cacheRead: 1.5e-06),
        "claude-3-sonnet": ModelPrice(input: 3e-06, output: 1.5e-05, cacheCreation: 3.75e-06, cacheRead: 3e-07),
        "claude-3-haiku": ModelPrice(input: 2.5e-07, output: 1.25e-06, cacheCreation: 3e-07, cacheRead: 3e-08),
        
        // Gemini Models
        "gemini-3.5-flash": ModelPrice(input: 7.5e-08, output: 3e-07, cacheCreation: 0, cacheRead: 0),
        "gemini-2.5-pro": ModelPrice(input: 1.25e-06, output: 1e-05, cacheCreation: 0, cacheRead: 0),
        "gemini-2.5-flash": ModelPrice(input: 7.5e-08, output: 3e-07, cacheCreation: 0, cacheRead: 0),

        // OpenAI Models
        "gpt-5.5": ModelPrice(input: 2.5e-06, output: 1e-05, cacheCreation: 0, cacheRead: 0),
        "gpt-5.4": ModelPrice(input: 2.5e-06, output: 1e-05, cacheCreation: 0, cacheRead: 0),
        "gpt-4o": ModelPrice(input: 2.5e-06, output: 1e-05, cacheCreation: 0, cacheRead: 0),
        "gpt-4o-mini": ModelPrice(input: 1.5e-07, output: 6e-07, cacheCreation: 0, cacheRead: 0),
    ]

    /// Longest-prefix lookup. Returns nil for unknown models.
    static func price(for model: String) -> ModelPrice? {
        var normalized = model.lowercased()
        // Strip provider/region prefixes: keep from first "claude", "gemini", or "gpt" occurrence.
        if let range = normalized.range(of: "claude") {
            normalized = String(normalized[range.lowerBound...])
        } else if let range = normalized.range(of: "gemini") {
            normalized = String(normalized[range.lowerBound...])
        } else if let range = normalized.range(of: "gpt") {
            normalized = String(normalized[range.lowerBound...])
        }
        var best: (key: String, price: ModelPrice)?
        for (key, price) in prices where normalized.hasPrefix(key) {
            if best == nil || key.count > best!.key.count {
                best = (key, price)
            }
        }
        return best?.price
    }

    /// Computed cost for one usage entry; (cost, priced) where priced is false for unknown models.
    static func cost(
        model: String, input: Int, output: Int, cacheCreation: Int, cacheRead: Int
    ) -> (cost: Double, priced: Bool) {
        guard let p = price(for: model) else { return (0, false) }
        let cost = Double(input) * p.input
            + Double(output) * p.output
            + Double(cacheCreation) * p.cacheCreation
            + Double(cacheRead) * p.cacheRead
        return (cost, true)
    }

    // MARK: - Non-Claude agents

    /// Approximate cost for Codex (OpenAI) usage using gpt-4o pricing as a baseline.
    /// USD per token: input $2.50/M, output $10/M.
    static func openAICost(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost  = Double(inputTokens)  * 2.50 / 1_000_000
        let outputCost = Double(outputTokens) * 10.0 / 1_000_000
        return inputCost + outputCost
    }

    /// Approximate cost for Antigravity (Gemini) usage using Gemini 2.5 Pro pricing.
    /// USD per token: input $1.25/M (≤200k), output $10/M.
    static func geminiCost(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost  = Double(inputTokens)  * 1.25 / 1_000_000
        let outputCost = Double(outputTokens) * 10.0 / 1_000_000
        return inputCost + outputCost
    }
}

