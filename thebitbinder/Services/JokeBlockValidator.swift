//
//  JokeBlockValidator.swift
//  thebitbinder
//
//  ⚠️  Replaced by Gemini-based extraction.
//  This shim keeps the `BlockValidation` / `JokeBlockValidator` symbols alive
//  so any remaining call-sites compile while migration is completed.
//

import Foundation

/// Deprecated — block validation is no longer needed; Gemini handles structured extraction.
@available(*, deprecated, message: "Use GeminiJokeExtractor instead.")
final class JokeBlockValidator {
    static let shared = JokeBlockValidator()
    private init() {}

    func validateBlock(_ block: LayoutBlock) -> BlockValidation {
        BlockValidation(
            block: block,
            result: .singleJoke,
            confidence: .high,
            issues: []
        )
    }

    func validateBlocks(_ blocks: [LayoutBlock]) -> [BlockValidation] {
        blocks.map { validateBlock($0) }
    }
}
