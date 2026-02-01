//
//  RomanceG2PProcessor.swift
//  KokoroSwift
//
//  Rule-based G2P processor for Romance languages (Spanish, Italian, Portuguese).
//  Produces IPA phonemes compatible with Kokoro's vocabulary.
//

import Foundation
import MLXUtilsLibrary

/// Rule-based G2P processor for Romance languages.
/// Converts Spanish, Italian, and Portuguese text to IPA phonemes.
final class RomanceG2PProcessor: G2PProcessor {
    private var currentLanguage: Language?

    func setLanguage(_ language: Language) throws {
        guard language.usesRomanceG2P else {
            throw G2PProcessorError.unsupportedLanguageCode(language.rawValue)
        }
        currentLanguage = language
    }

    func process(input: String) throws -> (String, [MToken]?) {
        guard let language = currentLanguage else {
            throw G2PProcessorError.processorNotInitialized
        }

        let phonemes: String
        switch language {
        case .spanish:
            phonemes = processSpanish(input)
        case .italian:
            phonemes = processItalian(input)
        case .brazilianPortuguese:
            phonemes = processPortuguese(input)
        default:
            throw G2PProcessorError.unsupportedLanguageCode(language.rawValue)
        }

        return (phonemes, nil)
    }

    // MARK: - Spanish G2P

    /// Process Spanish text to IPA phonemes.
    /// Spanish has nearly 1:1 grapheme-to-phoneme mapping.
    private func processSpanish(_ text: String) -> String {
        var phonemes: [String] = []
        let chars = Array(text.lowercased())
        var i = 0

        while i < chars.count {
            let char = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            let nextNext = i + 2 < chars.count ? chars[i + 2] : nil

            switch char {
            // Vowels (with accent handling)
            case "a", "á": phonemes.append("a"); i += 1
            case "e", "é": phonemes.append("e"); i += 1
            case "i", "í": phonemes.append("i"); i += 1
            case "o", "ó": phonemes.append("o"); i += 1
            case "u", "ú", "ü": phonemes.append("u"); i += 1

            // Digraphs (check first)
            case "c":
                if next == "h" {
                    phonemes.append("tʃ"); i += 2  // ch → tʃ
                } else if next == "e" || next == "i" || next == "é" || next == "í" {
                    phonemes.append("θ"); i += 1   // ce, ci → θ (Castilian)
                } else {
                    phonemes.append("k"); i += 1
                }
            case "l":
                if next == "l" {
                    phonemes.append("ʎ"); i += 2  // ll → ʎ
                } else {
                    phonemes.append("l"); i += 1
                }
            case "r":
                if next == "r" {
                    phonemes.append("r"); i += 2   // rr → trilled r
                } else if i == 0 || (i > 0 && (chars[i-1] == " " || chars[i-1] == "n" || chars[i-1] == "l" || chars[i-1] == "s")) {
                    phonemes.append("r"); i += 1   // Initial or post-consonant r → trilled
                } else {
                    phonemes.append("ɾ"); i += 1   // Intervocalic r → flapped
                }
            case "g":
                if next == "u" && (nextNext == "e" || nextNext == "i" || nextNext == "é" || nextNext == "í") {
                    phonemes.append("g"); i += 2   // gue, gui → g (u silent)
                } else if next == "e" || next == "i" || next == "é" || next == "í" {
                    phonemes.append("x"); i += 1   // ge, gi → x (Spanish j sound)
                } else if next == "ü" {
                    phonemes.append("g"); i += 1   // gü → gw (handled by ü → u)
                } else {
                    phonemes.append("g"); i += 1
                }
            case "q":
                if next == "u" {
                    phonemes.append("k"); i += 2   // qu → k
                } else {
                    phonemes.append("k"); i += 1
                }

            // Consonants with special rules
            case "j": phonemes.append("x"); i += 1
            case "ñ": phonemes.append("ɲ"); i += 1
            case "v", "b": phonemes.append("b"); i += 1
            case "z": phonemes.append("θ"); i += 1   // Castilian

            // Standard consonants
            case "d": phonemes.append("d"); i += 1
            case "f": phonemes.append("f"); i += 1
            case "k": phonemes.append("k"); i += 1
            case "m": phonemes.append("m"); i += 1
            case "n": phonemes.append("n"); i += 1
            case "p": phonemes.append("p"); i += 1
            case "s": phonemes.append("s"); i += 1
            case "t": phonemes.append("t"); i += 1
            case "x": phonemes.append("ks"); i += 1
            case "y":
                if i == chars.count - 1 || next == " " {
                    phonemes.append("i"); i += 1  // Final y → i
                } else {
                    phonemes.append("ʝ"); i += 1  // Consonant y
                }
            case "w": phonemes.append("w"); i += 1

            // Silent letters
            case "h": i += 1  // Silent

            // Spaces and punctuation
            case " ": phonemes.append(" "); i += 1
            case ",", ".": phonemes.append(" "); i += 1
            case "¿", "¡": i += 1  // Skip inverted punctuation

            default: i += 1
            }
        }

        return phonemes.joined()
    }

    // MARK: - Italian G2P

    /// Process Italian text to IPA phonemes.
    /// Italian is very regular with some digraph rules.
    private func processItalian(_ text: String) -> String {
        var phonemes: [String] = []
        let chars = Array(text.lowercased())
        var i = 0

        while i < chars.count {
            let char = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            let nextNext = i + 2 < chars.count ? chars[i + 2] : nil

            switch char {
            // Vowels (with accent handling)
            case "a", "à": phonemes.append("a"); i += 1
            case "e", "è", "é": phonemes.append("e"); i += 1
            case "i", "ì", "í": phonemes.append("i"); i += 1
            case "o", "ò", "ó": phonemes.append("o"); i += 1
            case "u", "ù", "ú": phonemes.append("u"); i += 1

            // Digraphs and trigraphs
            case "c":
                if next == "h" {
                    phonemes.append("k"); i += 2   // ch → k
                } else if next == "i" && (nextNext == "a" || nextNext == "o" || nextNext == "u" || nextNext == "e") {
                    phonemes.append("tʃ"); i += 2  // cia, cio, ciu, cie → tʃ + vowel (i silent)
                } else if next == "e" || next == "i" || next == "è" || next == "ì" {
                    phonemes.append("tʃ"); i += 1  // ce, ci → tʃ
                } else {
                    phonemes.append("k"); i += 1
                }
            case "g":
                if next == "h" {
                    phonemes.append("g"); i += 2   // gh → g
                } else if next == "l" && nextNext == "i" {
                    phonemes.append("ʎ"); i += 3   // gli → ʎ
                } else if next == "n" {
                    phonemes.append("ɲ"); i += 2   // gn → ɲ
                } else if next == "i" && (nextNext == "a" || nextNext == "o" || nextNext == "u" || nextNext == "e") {
                    phonemes.append("dʒ"); i += 2  // gia, gio, giu, gie → dʒ + vowel
                } else if next == "e" || next == "i" || next == "è" || next == "ì" {
                    phonemes.append("dʒ"); i += 1  // ge, gi → dʒ
                } else {
                    phonemes.append("g"); i += 1
                }
            case "s":
                if next == "c" && (nextNext == "e" || nextNext == "i") {
                    phonemes.append("ʃ"); i += 2   // sce, sci → ʃ
                } else {
                    phonemes.append("s"); i += 1
                }
            case "z":
                // Italian z can be /ts/ or /dz/ - default to /ts/
                phonemes.append("ts"); i += 1
            case "q":
                if next == "u" {
                    phonemes.append("k"); phonemes.append("w"); i += 2
                } else {
                    phonemes.append("k"); i += 1
                }

            // Double consonants (gemination) - simplified
            case "l":
                if next == "l" {
                    phonemes.append("l"); phonemes.append("l"); i += 2
                } else {
                    phonemes.append("l"); i += 1
                }
            case "r":
                if next == "r" {
                    phonemes.append("r"); phonemes.append("r"); i += 2
                } else {
                    phonemes.append("r"); i += 1
                }

            // Standard consonants
            case "b": phonemes.append("b"); i += 1
            case "d": phonemes.append("d"); i += 1
            case "f": phonemes.append("f"); i += 1
            case "k": phonemes.append("k"); i += 1
            case "m": phonemes.append("m"); i += 1
            case "n": phonemes.append("n"); i += 1
            case "p": phonemes.append("p"); i += 1
            case "t": phonemes.append("t"); i += 1
            case "v": phonemes.append("v"); i += 1
            case "j": phonemes.append("j"); i += 1
            case "w": phonemes.append("w"); i += 1
            case "x": phonemes.append("ks"); i += 1
            case "y": phonemes.append("i"); i += 1

            // Silent h
            case "h": i += 1

            // Spaces and punctuation
            case " ": phonemes.append(" "); i += 1
            case ",", ".": phonemes.append(" "); i += 1

            default: i += 1
            }
        }

        return phonemes.joined()
    }

    // MARK: - Portuguese G2P

    /// Process Brazilian Portuguese text to IPA phonemes.
    /// Portuguese has nasal vowels and some complex rules.
    private func processPortuguese(_ text: String) -> String {
        var phonemes: [String] = []
        let chars = Array(text.lowercased())
        var i = 0

        while i < chars.count {
            let char = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            let nextNext = i + 2 < chars.count ? chars[i + 2] : nil

            switch char {
            // Vowels (with nasal and accent handling)
            case "a", "á", "à": phonemes.append("a"); i += 1
            case "ã": phonemes.append("ɐ̃"); i += 1  // Nasal a
            case "e", "é": phonemes.append("e"); i += 1
            case "ê": phonemes.append("e"); i += 1   // Closed e
            case "i", "í": phonemes.append("i"); i += 1
            case "o", "ó": phonemes.append("o"); i += 1
            case "ô": phonemes.append("o"); i += 1   // Closed o
            case "õ": phonemes.append("õ"); i += 1   // Nasal o
            case "u", "ú": phonemes.append("u"); i += 1

            // Digraphs
            case "c":
                if next == "h" {
                    phonemes.append("ʃ"); i += 2   // ch → ʃ
                } else if next == "e" || next == "i" || next == "é" || next == "í" {
                    phonemes.append("s"); i += 1    // ce, ci → s
                } else if next == "ç" {
                    i += 1  // Skip, ç will handle it
                } else {
                    phonemes.append("k"); i += 1
                }
            case "ç": phonemes.append("s"); i += 1  // ç → s
            case "g":
                if next == "e" || next == "i" || next == "é" || next == "í" {
                    phonemes.append("ʒ"); i += 1   // ge, gi → ʒ
                } else {
                    phonemes.append("g"); i += 1
                }
            case "l":
                if next == "h" {
                    phonemes.append("ʎ"); i += 2   // lh → ʎ
                } else {
                    phonemes.append("l"); i += 1
                }
            case "n":
                if next == "h" {
                    phonemes.append("ɲ"); i += 2   // nh → ɲ
                } else {
                    phonemes.append("n"); i += 1
                }
            case "q":
                if next == "u" && (nextNext == "e" || nextNext == "i") {
                    phonemes.append("k"); i += 2   // que, qui → k (u silent)
                } else if next == "u" {
                    phonemes.append("k"); phonemes.append("w"); i += 2
                } else {
                    phonemes.append("k"); i += 1
                }
            case "r":
                if next == "r" {
                    phonemes.append("ʁ"); i += 2   // rr → ʁ (uvular)
                } else if i == 0 || (i > 0 && chars[i-1] == " ") {
                    phonemes.append("ʁ"); i += 1   // Initial r → ʁ
                } else {
                    phonemes.append("ɾ"); i += 1   // Intervocalic r → flapped
                }
            case "s":
                if i == 0 || (i > 0 && chars[i-1] == " ") {
                    phonemes.append("s"); i += 1   // Initial s
                } else if next == "s" {
                    phonemes.append("s"); i += 2   // ss → s
                } else if next != nil && "aeiouáéíóúãõâêô".contains(next!) && i > 0 && "aeiouáéíóúãõâêô".contains(chars[i-1]) {
                    phonemes.append("z"); i += 1   // Intervocalic s → z
                } else {
                    phonemes.append("s"); i += 1
                }
            case "x":
                // X has multiple sounds in Portuguese - default to ʃ
                phonemes.append("ʃ"); i += 1
            case "z":
                phonemes.append("z"); i += 1

            // Consonants
            case "b": phonemes.append("b"); i += 1
            case "d":
                // Brazilian: d before i often → dʒ
                if next == "i" || next == "í" {
                    phonemes.append("dʒ"); i += 1
                } else {
                    phonemes.append("d"); i += 1
                }
            case "f": phonemes.append("f"); i += 1
            case "h": i += 1  // Silent
            case "j": phonemes.append("ʒ"); i += 1
            case "k": phonemes.append("k"); i += 1
            case "m": phonemes.append("m"); i += 1
            case "p": phonemes.append("p"); i += 1
            case "t":
                // Brazilian: t before i often → tʃ
                if next == "i" || next == "í" {
                    phonemes.append("tʃ"); i += 1
                } else {
                    phonemes.append("t"); i += 1
                }
            case "v": phonemes.append("v"); i += 1
            case "w": phonemes.append("w"); i += 1
            case "y": phonemes.append("i"); i += 1

            // Spaces and punctuation
            case " ": phonemes.append(" "); i += 1
            case ",", ".": phonemes.append(" "); i += 1

            default: i += 1
            }
        }

        return phonemes.joined()
    }
}
