//
//  PhonemeNormalizer.swift
//  KokoroSwift
//
//  Normalizes IPA phonemes to Kokoro's 178-phoneme vocabulary.
//  Validates output from rule-based G2P processors.
//

import Foundation

/// Errors that can occur during phoneme normalization.
public enum PhonemeNormalizationError: Error, CustomStringConvertible {
    /// The phoneme string contains symbols not in Kokoro's vocabulary.
    case unrecognizedPhonemes(Set<String>)

    public var description: String {
        switch self {
        case .unrecognizedPhonemes(let phonemes):
            return "Unrecognized phonemes: \(phonemes.sorted().joined(separator: ", "))"
        }
    }
}

/// Normalizes IPA phonemes to Kokoro's vocabulary.
/// Kokoro was trained with espeak-ng IPA phonemes, so rule-based
/// G2P output must be mapped to compatible symbols.
struct PhonemeNormalizer {

    /// Kokoro's phoneme vocabulary (common subset for Romance languages)
    /// Full vocabulary contains 178 symbols from espeak-ng training.
    static let kokoroVocabulary: Set<String> = [
        // Basic vowels
        "a", "e", "i", "o", "u",
        // Extended vowels
        "ɐ", "ɐ̃", "ɑ", "ɔ", "ə", "ɛ", "ɪ", "ʊ", "ʌ", "æ", "ø", "y",
        // Nasal vowels
        "ã", "ẽ", "ĩ", "õ", "ũ", "ɐ̃",
        // Consonants - basic
        "b", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "w", "z",
        // Consonants - extended
        "ɲ", "ɾ", "ʁ", "ʎ", "ʝ", "x", "θ", "ð",
        // Affricates
        "tʃ", "dʒ", "ts", "dz",
        // Fricatives
        "ʃ", "ʒ", "ç",
        // Clusters
        "ks", "gz",
        // Space
        " "
    ]

    /// Mapping from common IPA variants to Kokoro-compatible phonemes
    static let phonemeMapping: [String: String] = [
        // Vowel variants
        "ɐ̃": "ɐ̃",  // Keep nasal a
        "ã": "ɐ̃",   // Alternative nasal a
        "ĩ": "ĩ",    // Nasal i
        "ũ": "ũ",    // Nasal u
        "ẽ": "ẽ",    // Nasal e
        "õ": "õ",    // Nasal o

        // Consonant variants
        "ɟ": "ʝ",    // Voiced palatal → approximant
        "ʀ": "ʁ",    // Uvular trill → uvular fricative
        "ɽ": "ɾ",    // Retroflex flap → alveolar flap
        "r̥": "r",    // Voiceless trill → trill
        "c": "k",    // Voiceless palatal → k (in some contexts)
        "ɡ": "g",    // Unicode g variant

        // Length markers (remove)
        "ː": "",     // Long vowel marker
        "ˑ": "",     // Half-long marker

        // Stress markers (keep for now, may be processed separately)
        "ˈ": "",     // Primary stress
        "ˌ": "",     // Secondary stress
    ]

    /// Normalize a phoneme string to Kokoro vocabulary.
    /// - Parameter phonemes: Raw IPA phoneme string from G2P
    /// - Returns: Normalized phoneme string compatible with Kokoro
    /// - Throws: PhonemeNormalizationError.unrecognizedPhonemes if any phonemes are not in vocabulary
    static func normalize(_ phonemes: String) throws -> String {
        var result = phonemes

        // Apply phoneme mappings
        for (from, replacement) in phonemeMapping {
            result = result.replacingOccurrences(of: from, with: replacement)
        }

        // Validate that all phonemes are recognized
        let unrecognized = findUnrecognizedPhonemes(result)
        if !unrecognized.isEmpty {
            throw PhonemeNormalizationError.unrecognizedPhonemes(unrecognized)
        }

        return result
    }

    /// Validate that all phonemes in a string are in Kokoro's vocabulary.
    /// - Parameter phonemes: Phoneme string to validate
    /// - Returns: Set of unrecognized phonemes (empty if all valid)
    static func findUnrecognizedPhonemes(_ phonemes: String) -> Set<String> {
        var unrecognized = Set<String>()

        // Tokenize by splitting on known phonemes
        // This is a simplified check - actual implementation would need
        // proper phoneme boundary detection
        let chars = Array(phonemes)
        var i = 0

        while i < chars.count {
            var found = false

            // Check multi-character phonemes first (longest match)
            for length in stride(from: min(3, chars.count - i), through: 1, by: -1) {
                let candidate = String(chars[i..<(i + length)])
                if kokoroVocabulary.contains(candidate) {
                    found = true
                    i += length
                    break
                }
            }

            if !found {
                let char = String(chars[i])
                if !char.trimmingCharacters(in: .whitespaces).isEmpty {
                    unrecognized.insert(char)
                }
                i += 1
            }
        }

        return unrecognized
    }

    /// Check if a phoneme string is valid for Kokoro.
    /// - Parameter phonemes: Phoneme string to validate
    /// - Returns: True if all phonemes are recognized
    static func isValid(_ phonemes: String) -> Bool {
        return findUnrecognizedPhonemes(phonemes).isEmpty
    }
}
