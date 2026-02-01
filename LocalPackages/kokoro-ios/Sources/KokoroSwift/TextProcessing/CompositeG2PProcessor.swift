//
//  CompositeG2PProcessor.swift
//  KokoroSwift
//
//  Hybrid G2P processor that routes to Misaki (English) or RomanceG2P
//  (Spanish/Italian/Portuguese) based on the selected language.
//

import Foundation
import MLXUtilsLibrary

/// Composite G2P processor that routes to the appropriate processor based on language.
/// - English (en-US, en-GB): Uses MisakiG2PProcessor
/// - Romance (es-ES, it-IT, pt-BR): Uses RomanceG2PProcessor
///
/// This processor is created per-synthesis request (not shared), so mutable state is safe.
final class CompositeG2PProcessor: G2PProcessor {
    #if canImport(MisakiSwift)
    private var misakiProcessor: MisakiG2PProcessor?
    #endif
    private var romanceProcessor: RomanceG2PProcessor?
    private var currentLanguage: Language?

    func setLanguage(_ language: Language) throws {
        currentLanguage = language

        switch language {
        case .enUS, .enGB:
            #if canImport(MisakiSwift)
            if misakiProcessor == nil {
                misakiProcessor = MisakiG2PProcessor()
            }
            try misakiProcessor?.setLanguage(language)
            #else
            throw G2PProcessorError.unsupportedLanguageCode("MisakiSwift not available for \(language.rawValue)")
            #endif

        case .spanish, .italian, .brazilianPortuguese:
            if romanceProcessor == nil {
                romanceProcessor = RomanceG2PProcessor()
            }
            try romanceProcessor?.setLanguage(language)

        case .none:
            throw G2PProcessorError.unsupportedLanguageCode("no language specified")
        }
    }

    func process(input: String) throws -> (String, [MToken]?) {
        guard let language = currentLanguage else {
            throw G2PProcessorError.processorNotInitialized
        }

        switch language {
        case .enUS, .enGB:
            #if canImport(MisakiSwift)
            guard let processor = misakiProcessor else {
                throw G2PProcessorError.processorNotInitialized
            }
            return try processor.process(input: input)
            #else
            throw G2PProcessorError.unsupportedLanguageCode("MisakiSwift not available")
            #endif

        case .spanish, .italian, .brazilianPortuguese:
            guard let processor = romanceProcessor else {
                throw G2PProcessorError.processorNotInitialized
            }
            let (phonemes, tokens) = try processor.process(input: input)
            // Normalize phonemes to Kokoro vocabulary (throws on unrecognized phonemes)
            let normalized = try PhonemeNormalizer.normalize(phonemes)
            return (normalized, tokens)

        case .none:
            throw G2PProcessorError.unsupportedLanguageCode("no language specified")
        }
    }
}
