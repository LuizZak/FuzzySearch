//
//  FuzzySearch.swift
//  FuzzySearch
//
//  Created by Viktoras Laukevičius on 05/08/16.
//  Copyright © 2016 Treatwell. All rights reserved.
//

import Foundation

/// For objc_setAssociatedObject
private var _fuzzyCache: Int = 0

struct CharOpts {
    let ch: String
    let normalized: String
}

/// A private cache containing pre-parsed metadata from a previous `.fuzzyMatch`
/// call.
class FuzzyCache {
    /// Hash of last fuzzed string
    internal var hash: Int?
    
    /// Array of last parsed fuzzy characters
    internal var lastTokenization: [CharOpts] = []
    
    init() {
        
    }
}

/// Opaque struct containing the results of a pre-tokenization phase that is
/// applied to a fuzzy searchable value.
struct FuzzyTokens {
    var tokens: [CharOpts]
}

private extension String {
    subscript(i: Int) -> Character? {
        guard i >= 0 && i < characters.count else { return nil }
        return self[characters.index(startIndex, offsetBy: i)]
    }
    
    func tokenize() -> [CharOpts] {
        return characters.map{
            let str = String($0).lowercased()
            guard let data = str.data(using: .ascii, allowLossyConversion: true),
                let accentFoldedStr = String(data: data, encoding: .ascii) else {
                return CharOpts(ch: str, normalized: str)
            }
            return CharOpts(ch: str, normalized: accentFoldedStr)
        }
    }
    
    // checking if string has prefix and returning prefix length on success
    func hasPrefix(_ prefix: CharOpts, atIndex index: Int) -> Int? {
        for pfx in [prefix.ch, prefix.normalized] {
            if (self as NSString).substring(from: index).hasPrefix(pfx) {
                return pfx.characters.count
            }
        }
        return nil
    }
}

public struct FuzzySearchResult {
    public let weight: Int
    public let parts: [NSRange]
}

public protocol FuzzySearchable {
    var fuzzyStringToMatch: String { get }
}

extension FuzzySearchable {
    var fuzzyCache: FuzzyCache {
        // Create cache, if not available yet
        let cache: FuzzyCache
        if let _cache = objc_getAssociatedObject(self, &_fuzzyCache) as? FuzzyCache {
            cache = _cache
        } else {
            cache = FuzzyCache()
            objc_setAssociatedObject(self, &_fuzzyCache, cache, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        return cache
    }
    
    func fuzzyTokenized() -> FuzzyTokens {
        let cache = fuzzyCache
        
        // Re-create fuzzy cache, if stale
        if cache.hash == nil || cache.hash != fuzzyStringToMatch.hashValue {
            let tokens = fuzzyStringToMatch.tokenize()
            cache.hash = fuzzyStringToMatch.hashValue
            cache.lastTokenization = tokens
        }
        
        return FuzzyTokens(tokens: cache.lastTokenization)
    }
}

public extension FuzzySearchable {
    func fuzzyMatch(_ pattern: String) -> FuzzySearchResult {
        let compareString = fuzzyTokenized().tokens
        
        let pattern = pattern.lowercased()
        
        var totalScore = 0
        var parts: [NSRange] = []
        
        var patternIdx = 0
        var currScore = 0
        var currPart = NSRange(location: 0, length: 0)
        
        for (idx, strChar) in compareString.enumerated() {
            if let prefixLength = pattern.hasPrefix(strChar, atIndex: patternIdx) {
                patternIdx += prefixLength
                currScore += 1 + currScore
                currPart.length += 1
            } else {
                currScore = 0
                if currPart.length != 0 {
                    parts.append(currPart)
                }
                currPart = NSRange(location: idx + 1, length: 0)
            }
            totalScore += currScore
        }
        if currPart.length != 0 {
            parts.append(currPart)
        }
        
        if patternIdx == pattern.characters.count {
            // if all pattern chars were found
            return FuzzySearchResult(weight: totalScore, parts: parts)
        } else {
            return FuzzySearchResult(weight: 0, parts: [])
        }
    }
}

public extension Collection where Iterator.Element: FuzzySearchable {
    func fuzzyMatch(_ pattern: String) -> [(item: Iterator.Element, result: FuzzySearchResult)] {
        return map{
            (item: $0, result: $0.fuzzyMatch(pattern))
        }.filter{
            $0.result.weight > 0
        }.sorted{
            $0.result.weight > $1.result.weight
        }
    }
}
