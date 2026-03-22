//
//  JokeExtractor.swift
//  thebitbinder
//
//  ⚠️  This file is intentionally a thin shim.
//  All real extraction is handled by GeminiJokeExtractor.
//  Kept here so existing call-sites that import this symbol still compile
//  while we migrate them to call GeminiJokeExtractor directly.
//

import Foundation

/// Deprecated shim — use `GeminiJokeExtractor.shared` directly.
@available(*, deprecated, renamed: "GeminiJokeExtractor")
final class JokeExtractor {
    static let shared = JokeExtractor()
    private init() {}
}
