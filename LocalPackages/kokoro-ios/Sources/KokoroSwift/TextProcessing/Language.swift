//
//  Kokoro-tts-lib
//
import Foundation

/// Supported languages for text-to-speech synthesis.
/// This enum defines the available language variants that can be used with the Kokoro TTS engine.
public enum Language: String, CaseIterable {
  /// No language specified or language-independent processing.
  case none = ""
  /// US English (American English).
  case enUS = "en-US"
  /// GB English (British English).
  case enGB = "en-GB"
  /// Spanish (Spain).
  case spanish = "es-ES"
  /// Italian.
  case italian = "it-IT"
  /// Brazilian Portuguese.
  case brazilianPortuguese = "pt-BR"

  /// Check if language uses English G2P (Misaki)
  public var usesEnglishG2P: Bool {
    switch self {
    case .enUS, .enGB:
      return true
    default:
      return false
    }
  }

  /// Check if language uses Romance G2P (rule-based)
  public var usesRomanceG2P: Bool {
    switch self {
    case .spanish, .italian, .brazilianPortuguese:
      return true
    default:
      return false
    }
  }
}
