// NaturalLanguageProcessor.swift
// MTRX Apple Integration — Intelligence
// On-device NLP preprocessing before every Trinity response

import NaturalLanguage
import Foundation

// MARK: - Natural Language Processor

final class NaturalLanguageProcessor {

    // MARK: - Shared Instance

    static let shared = NaturalLanguageProcessor()

    // MARK: - Properties

    private let sentimentPredictor: NLModel?
    private let entityRecognizer: NLTagger
    private let tokenizer: NLTokenizer
    private let languageRecognizer: NLLanguageRecognizer

    // MARK: - Analysis Result

    struct NLPAnalysis {
        let sentiment: SentimentResult
        let entities: [ExtractedEntity]
        let intent: DetectedIntent
        let language: NLLanguage
        let tokens: [String]
        let keyPhrases: [String]
    }

    struct SentimentResult {
        let score: Double      // -1.0 (negative) to 1.0 (positive)
        let label: SentimentLabel
        let confidence: Double
    }

    enum SentimentLabel: String {
        case veryNegative = "very_negative"
        case negative = "negative"
        case neutral = "neutral"
        case positive = "positive"
        case veryPositive = "very_positive"
    }

    struct ExtractedEntity {
        let text: String
        let type: EntityType
        let range: Range<String.Index>
    }

    enum EntityType: String {
        case person
        case organization
        case place
        case tokenSymbol
        case walletAddress
        case amount
        case date
        case contractAddress
        case transactionHash
    }

    struct DetectedIntent {
        let primary: IntentCategory
        let confidence: Double
        let parameters: [String: String]
    }

    enum IntentCategory: String {
        case sendPayment
        case checkBalance
        case swapTokens
        case stakeTokens
        case viewTransaction
        case askQuestion
        case setAlert
        case unknown
    }

    // MARK: - Initialization

    private init() {
        sentimentPredictor = try? NLModel(mlModel: CoreMLManager.shared.loadedModelCount > 0 ? CoreMLManager.TrinityModel.sentimentAnalysis as! MLModel : NLModel.self as! MLModel)
        entityRecognizer = NLTagger(tagSchemes: [.nameType, .tokenType, .lexicalClass])
        tokenizer = NLTokenizer(unit: .word)
        languageRecognizer = NLLanguageRecognizer()
    }

    // MARK: - Full Analysis Pipeline

    /// Performs complete NLP analysis on user input before Trinity processes it.
    func analyze(_ text: String) -> NLPAnalysis {
        let sentiment = analyzeSentiment(text)
        let entities = extractEntities(text)
        let intent = detectIntent(text, entities: entities)
        let language = detectLanguage(text)
        let tokens = tokenize(text)
        let keyPhrases = extractKeyPhrases(text)

        return NLPAnalysis(
            sentiment: sentiment,
            entities: entities,
            intent: intent,
            language: language,
            tokens: tokens,
            keyPhrases: keyPhrases
        )
    }

    // MARK: - Sentiment Analysis

    func analyzeSentiment(_ text: String) -> SentimentResult {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        var totalScore: Double = 0
        var count = 0

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .paragraph, scheme: .sentimentScore) { tag, _ in
            if let tag = tag, let score = Double(tag.rawValue) {
                totalScore += score
                count += 1
            }
            return true
        }

        let averageScore = count > 0 ? totalScore / Double(count) : 0

        let label: SentimentLabel
        switch averageScore {
        case ..<(-0.6): label = .veryNegative
        case -0.6..<(-0.2): label = .negative
        case -0.2..<0.2: label = .neutral
        case 0.2..<0.6: label = .positive
        default: label = .veryPositive
        }

        return SentimentResult(score: averageScore, label: label, confidence: min(abs(averageScore) + 0.5, 1.0))
    }

    // MARK: - Entity Extraction

    func extractEntities(_ text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        // Standard NL entity recognition
        entityRecognizer.string = text
        let tags: [NLTag] = [.personalName, .organizationName, .placeName]

        entityRecognizer.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if let tag = tag, tags.contains(tag) {
                let entityType: EntityType
                switch tag {
                case .personalName: entityType = .person
                case .organizationName: entityType = .organization
                case .placeName: entityType = .place
                default: return true
                }
                entities.append(ExtractedEntity(text: String(text[range]), type: entityType, range: range))
            }
            return true
        }

        // Custom crypto entity extraction
        entities.append(contentsOf: extractCryptoEntities(text))

        return entities
    }

    // MARK: - Custom Crypto Entity Extraction

    private func extractCryptoEntities(_ text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        // Wallet addresses (0x...)
        let addressPattern = "0x[0-9a-fA-F]{40}"
        if let regex = try? NSRegularExpression(pattern: addressPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    entities.append(ExtractedEntity(text: String(text[range]), type: .walletAddress, range: range))
                }
            }
        }

        // Transaction hashes (0x + 64 hex chars)
        let txPattern = "0x[0-9a-fA-F]{64}"
        if let regex = try? NSRegularExpression(pattern: txPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    entities.append(ExtractedEntity(text: String(text[range]), type: .transactionHash, range: range))
                }
            }
        }

        // Token symbols (uppercase 2-6 chars)
        let tokenPattern = "\\b[A-Z]{2,6}\\b"
        let knownTokens = Set(["ETH", "BTC", "USDC", "USDT", "DAI", "WETH", "WBTC", "LINK", "UNI", "AAVE", "COMP", "MKR", "SNX", "CRV", "MATIC"])
        if let regex = try? NSRegularExpression(pattern: tokenPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let symbol = String(text[range])
                    if knownTokens.contains(symbol) {
                        entities.append(ExtractedEntity(text: symbol, type: .tokenSymbol, range: range))
                    }
                }
            }
        }

        // Amounts (numbers with optional decimals)
        let amountPattern = "\\b\\d+\\.?\\d*\\s*(ETH|BTC|USDC|USDT|DAI|USD|\\$)"
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    entities.append(ExtractedEntity(text: String(text[range]), type: .amount, range: range))
                }
            }
        }

        return entities
    }

    // MARK: - Intent Detection

    func detectIntent(_ text: String, entities: [ExtractedEntity]) -> DetectedIntent {
        let lowered = text.lowercased()
        var parameters: [String: String] = [:]

        // Extract parameters from entities
        for entity in entities {
            switch entity.type {
            case .walletAddress: parameters["address"] = entity.text
            case .tokenSymbol: parameters["token"] = entity.text
            case .amount: parameters["amount"] = entity.text
            default: break
            }
        }

        // Rule-based intent classification
        if lowered.contains("send") || lowered.contains("transfer") || lowered.contains("pay") {
            return DetectedIntent(primary: .sendPayment, confidence: 0.9, parameters: parameters)
        }
        if lowered.contains("balance") || lowered.contains("portfolio") || lowered.contains("how much") {
            return DetectedIntent(primary: .checkBalance, confidence: 0.9, parameters: parameters)
        }
        if lowered.contains("swap") || lowered.contains("exchange") || lowered.contains("convert") {
            return DetectedIntent(primary: .swapTokens, confidence: 0.9, parameters: parameters)
        }
        if lowered.contains("stake") || lowered.contains("yield") || lowered.contains("deposit") {
            return DetectedIntent(primary: .stakeTokens, confidence: 0.85, parameters: parameters)
        }
        if lowered.contains("transaction") || lowered.contains("tx") || lowered.contains("history") {
            return DetectedIntent(primary: .viewTransaction, confidence: 0.85, parameters: parameters)
        }
        if lowered.contains("alert") || lowered.contains("notify") || lowered.contains("remind") {
            return DetectedIntent(primary: .setAlert, confidence: 0.8, parameters: parameters)
        }

        return DetectedIntent(primary: .askQuestion, confidence: 0.5, parameters: parameters)
    }

    // MARK: - Language Detection

    func detectLanguage(_ text: String) -> NLLanguage {
        languageRecognizer.reset()
        languageRecognizer.processString(text)
        return languageRecognizer.dominantLanguage ?? .english
    }

    // MARK: - Tokenization

    func tokenize(_ text: String) -> [String] {
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]))
            return true
        }
        return tokens
    }

    // MARK: - Key Phrase Extraction

    func extractKeyPhrases(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var phrases: [String] = []
        var currentPhrase: [String] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if let tag = tag, tag == .noun || tag == .adjective {
                currentPhrase.append(String(text[range]))
            } else {
                if !currentPhrase.isEmpty {
                    phrases.append(currentPhrase.joined(separator: " "))
                    currentPhrase = []
                }
            }
            return true
        }
        if !currentPhrase.isEmpty {
            phrases.append(currentPhrase.joined(separator: " "))
        }
        return phrases
    }
}
