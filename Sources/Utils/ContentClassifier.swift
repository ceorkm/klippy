import Foundation

class ContentClassifier {
    
    // MARK: - Regex Patterns
    private struct Patterns {
        // URL patterns
        static let url = try! NSRegularExpression(
            pattern: #"https?://[^\s/$.?#].[^\s]*"#,
            options: [.caseInsensitive]
        )
        
        static let urlSimple = try! NSRegularExpression(
            pattern: #"(?:www\.)?[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?"#,
            options: [.caseInsensitive]
        )
        
        // Email patterns
        static let email = try! NSRegularExpression(
            pattern: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#,
            options: [.caseInsensitive]
        )
        
        // Phone number patterns (various formats)
        static let phone = try! NSRegularExpression(
            pattern: #"(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}"#,
            options: []
        )
        
        static let phoneInternational = try! NSRegularExpression(
            pattern: #"\+[1-9]\d{1,14}"#,
            options: []
        )
        
        // Address patterns
        static let address = try! NSRegularExpression(
            pattern: #"\d+\s+[A-Za-z0-9\s,.-]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Place|Pl|Way|Circle|Cir)"#,
            options: [.caseInsensitive]
        )
        
        static let zipCode = try! NSRegularExpression(
            pattern: #"\b\d{5}(?:-\d{4})?\b"#,
            options: []
        )
        
        // Code patterns
        static let codeBlock = try! NSRegularExpression(
            pattern: #"```[\s\S]*?```|`[^`]+`"#,
            options: []
        )
        
        static let htmlTag = try! NSRegularExpression(
            pattern: #"<[^>]+>"#,
            options: []
        )
        
        static let functionCall = try! NSRegularExpression(
            pattern: #"\b[a-zA-Z_][a-zA-Z0-9_]*\s*\([^)]*\)"#,
            options: []
        )
        
        static let variableDeclaration = try! NSRegularExpression(
            pattern: #"\b(?:var|let|const|int|string|bool|float|double)\s+[a-zA-Z_][a-zA-Z0-9_]*"#,
            options: []
        )
        
        // Number patterns
        static let number = try! NSRegularExpression(
            pattern: #"^\s*-?\d+(?:\.\d+)?\s*$"#,
            options: []
        )
        
        static let currency = try! NSRegularExpression(
            pattern: #"[$€£¥]\s*\d+(?:\.\d{2})?"#,
            options: []
        )
        
        // Date patterns
        static let date = try! NSRegularExpression(
            pattern: #"\b(?:\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})\b"#,
            options: []
        )
        
        static let dateWords = try! NSRegularExpression(
            pattern: #"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b"#,
            options: [.caseInsensitive]
        )
        
        // Color patterns
        static let hexColor = try! NSRegularExpression(
            pattern: #"#[0-9A-Fa-f]{3,8}\b"#,
            options: []
        )
        
        static let rgbColor = try! NSRegularExpression(
            pattern: #"rgb\s*\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)"#,
            options: [.caseInsensitive]
        )
        
        // File path patterns
        static let filePath = try! NSRegularExpression(
            pattern: #"(?:[a-zA-Z]:\\|/)[^\s<>:"|?*]+\.[a-zA-Z0-9]+"#,
            options: []
        )
        
        static let fileName = try! NSRegularExpression(
            pattern: #"[a-zA-Z0-9_.-]+\.[a-zA-Z0-9]{1,10}\b"#,
            options: []
        )
        
        // Payment card patterns
        static let paymentCardCandidate = try! NSRegularExpression(
            pattern: #"\b(?:\d[ -]?){13,19}\b"#,
            options: []
        )
        
        // API key patterns
        static let apiKeyAssignment = try! NSRegularExpression(
            pattern: #"(?i)\b(?:api[_-]?key|access[_-]?key|secret|token|client[_-]?secret|private[_-]?key)\b\s*[:=]\s*["']?([A-Za-z0-9._\-]{16,})["']?"#,
            options: []
        )
        
        static let jwt = try! NSRegularExpression(
            pattern: #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
            options: []
        )
        
        static let strongAPIKeys: [NSRegularExpression] = [
            try! NSRegularExpression(pattern: #"\bsk-proj-[A-Za-z0-9_\-]{20,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bsk-[A-Za-z0-9]{20,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bsk-ant-(?:api\d{2}-)?[A-Za-z0-9_\-]{20,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bfc-[A-Za-z0-9_\-]{16,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bAIza[0-9A-Za-z_-]{35}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{16,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bxox[baprs]-[0-9A-Za-z-]{10,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bhf_[A-Za-z0-9]{30,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bSG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bsq0(?:atp|csp)-[A-Za-z0-9_-]{20,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bxai-[A-Za-z0-9_-]{20,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bnpm_[A-Za-z0-9]{30,}\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bya29\.[0-9A-Za-z\-_]+\b"#, options: []),
            try! NSRegularExpression(pattern: #"\bSK[0-9a-fA-F]{32}\b"#, options: [])
        ]
    }
    
    private static let instagramDomains = [
        "instagram.com"
    ]
    
    private static let tiktokDomains = [
        "tiktok.com",
        "vm.tiktok.com"
    ]
    
    private static let socialDomains = [
        "facebook.com",
        "fb.com",
        "x.com",
        "twitter.com",
        "t.co",
        "linkedin.com",
        "youtube.com",
        "youtu.be",
        "reddit.com",
        "threads.net",
        "pinterest.com",
        "snapchat.com",
        "instagram.com",
        "tiktok.com",
        "vm.tiktok.com"
    ]
    
    private static let apiKeyPlaceholderWords = [
        "your_api_key",
        "your-token",
        "replace_me",
        "changeme",
        "example",
        "sample",
        "test_key"
    ]
    
    // MARK: - Classification Logic
    
    func classify(_ content: String) -> ContentCategory {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Early return for empty content
        guard !trimmedContent.isEmpty else { return .other }
        
        // Sensitive values are checked first so they are not hidden by generic categories.
        if isAPIKey(trimmedContent) { return .apiKey }
        if isPaymentCard(trimmedContent) { return .paymentCard }
        
        // Check for structured data formats first
        if isJSON(trimmedContent) { return .json }
        if isXML(trimmedContent) { return .xml }
        if isMarkdown(trimmedContent) { return .markdown }
        
        // Check for specific content types
        if isEmail(trimmedContent) { return .email }
        if isInstagramURL(trimmedContent) { return .instagramURL }
        if isTikTokURL(trimmedContent) { return .tiktokURL }
        if isSocialMediaURL(trimmedContent) { return .socialMedia }
        if isURL(trimmedContent) { return .url }
        if isPhoneNumber(trimmedContent) { return .phone }
        if isAddress(trimmedContent) { return .address }
        if isCode(trimmedContent) { return .code }
        if isNumber(trimmedContent) { return .number }
        if isDate(trimmedContent) { return .date }
        if isColor(trimmedContent) { return .color }
        if isFilePath(trimmedContent) { return .file }
        
        // Default to text
        return .text
    }
    
    // MARK: - Specific Type Checkers
    
    private func isURL(_ content: String) -> Bool {
        extractPrimaryURL(from: content) != nil
    }
    
    private func isInstagramURL(_ content: String) -> Bool {
        guard let host = primaryURLHost(from: content) else { return false }
        return hostMatchesDomain(host, domains: Self.instagramDomains)
    }
    
    private func isTikTokURL(_ content: String) -> Bool {
        guard let host = primaryURLHost(from: content) else { return false }
        return hostMatchesDomain(host, domains: Self.tiktokDomains)
    }
    
    private func isSocialMediaURL(_ content: String) -> Bool {
        guard let host = primaryURLHost(from: content) else { return false }
        return hostMatchesDomain(host, domains: Self.socialDomains)
    }
    
    private func isEmail(_ content: String) -> Bool {
        let matches = Patterns.email.matches(in: content, range: NSRange(content.startIndex..., in: content))
        
        // Should contain an email and be mostly email content
        if let match = matches.first {
            let matchLength = match.range.length
            let contentLength = max(content.count, 1)
            return Double(matchLength) / Double(contentLength) > 0.8
        }
        
        return false
    }
    
    private func isPhoneNumber(_ content: String) -> Bool {
        // Remove common separators and check if it's mostly digits
        let digitsOnly = content.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digitsOnly.count >= 10 && digitsOnly.count <= 15 {
            return Patterns.phone.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil ||
                   Patterns.phoneInternational.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
        }
        
        return false
    }
    
    private func isAddress(_ content: String) -> Bool {
        let hasAddressPattern = Patterns.address.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
        let hasZipCode = Patterns.zipCode.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
        
        // Look for address keywords
        let addressKeywords = ["street", "avenue", "road", "boulevard", "lane", "drive", "court", "place", "way", "apt", "suite", "unit"]
        let lowercaseContent = content.lowercased()
        let hasAddressKeywords = addressKeywords.contains { lowercaseContent.contains($0) }
        
        return hasAddressPattern || (hasZipCode && hasAddressKeywords)
    }
    
    private func isCode(_ content: String) -> Bool {
        let range = NSRange(content.startIndex..., in: content)

        // Code block markers (``` fences) are a strong signal
        if Patterns.codeBlock.firstMatch(in: content, range: range) != nil {
            return true
        }

        // Score-based: need multiple real signals
        var score = 0

        // HTML — only count if it looks like actual markup (matching open/close tags)
        // not stray angle brackets or browser-injected tags
        let htmlMatches = Patterns.htmlTag.matches(in: content, range: range)
        let htmlTagCount = htmlMatches.count
        let hasClosingTags = content.contains("</")
        if htmlTagCount >= 4 && hasClosingTags { score += 2 }

        // Function calls — filter out English parentheticals like "video (not an...)"
        let functionMatches = Patterns.functionCall.matches(in: content, range: range).filter { match in
            guard let matchRange = Range(match.range, in: content) else { return true }
            let matched = String(content[matchRange])
            // Real function calls don't have spaces before the paren
            return !matched.contains(" (")
        }
        if functionMatches.count >= 3 { score += 1 }
        if functionMatches.count >= 6 { score += 1 }

        // Variable declarations — filter out English "let"
        let variableMatches = Patterns.variableDeclaration.matches(in: content, range: range)
        let realVarMatches = variableMatches.filter { match in
            guard let matchRange = Range(match.range, in: content) else { return true }
            let matched = String(content[matchRange])
            let lower = matched.lowercased()

            // "var" and "int" at start of a sentence in natural language is unlikely.
            if lower.hasPrefix("var ") || lower.hasPrefix("int ") {
                return true
            }

            // "let" is common in English, so reject only known non-code phrases by word.
            if lower.hasPrefix("let ") {
                let tokens = lower.split(whereSeparator: \.isWhitespace)
                guard tokens.count > 1 else { return true }
                let secondWord = String(tokens[1])
                let disallowedEnglishSecondWords = [
                    "me", "the", "it", "us", "them",
                    "him", "her", "your", "this", "that",
                    "a", "an", "all", "each", "every"
                ]
                return !disallowedEnglishSecondWords.contains(secondWord)
            }

            return true
        }
        if realVarMatches.count >= 2 { score += 1 }
        if realVarMatches.count >= 4 { score += 1 }
        let hasAssignment = content.contains("=")
        if realVarMatches.count >= 1 && hasAssignment { score += 2 }

        // Code symbols — strong signal
        let codeSymbols = [";", "=>", "->", "==", "!=", "&&", "||"]
        let symbolCount = codeSymbols.reduce(0) { count, symbol in
            count + content.components(separatedBy: symbol).count - 1
        }
        // Braces only count as pairs
        let openBraces = content.filter { $0 == "{" }.count
        let closeBraces = content.filter { $0 == "}" }.count
        let bracePairs = min(openBraces, closeBraces)
        let totalCodeSymbols = symbolCount + bracePairs

        if totalCodeSymbols >= 3 { score += 1 }
        if totalCodeSymbols >= 6 { score += 1 }

        // Short function snippets are common clipboard code; treat as code when paired with braces/semicolon.
        let hasFunctionKeyword = content.range(of: #"\b(?:function|func|def)\b"#, options: .regularExpression) != nil
        if hasFunctionKeyword && (bracePairs >= 1 || content.contains(";")) { score += 2 }

        return score >= 2
    }
    
    private func isNumber(_ content: String) -> Bool {
        // Check for pure numbers
        if Patterns.number.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
            return true
        }
        
        // Check for currency
        return Patterns.currency.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
    }
    
    private func isDate(_ content: String) -> Bool {
        return Patterns.date.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil ||
               Patterns.dateWords.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
    }
    
    private func isColor(_ content: String) -> Bool {
        return Patterns.hexColor.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil ||
               Patterns.rgbColor.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
    }
    
    private func isFilePath(_ content: String) -> Bool {
        if Patterns.filePath.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
            return true
        }
        
        // Check for simple file names
        let matches = Patterns.fileName.matches(in: content, range: NSRange(content.startIndex..., in: content))
        if let match = matches.first, matches.count == 1 {
            let matchLength = match.range.length
            let contentLength = max(content.count, 1)
            return Double(matchLength) / Double(contentLength) > 0.8
        }
        
        return false
    }
    
    private func isPaymentCard(_ content: String) -> Bool {
        let matches = Patterns.paymentCardCandidate.matches(in: content, range: NSRange(content.startIndex..., in: content))
        guard !matches.isEmpty else { return false }
        
        let lowercaseContent = content.lowercased()
        let cardKeywords = ["card", "credit", "debit", "visa", "mastercard", "amex", "expiry", "exp", "cvv"]
        let hasCardKeywords = cardKeywords.contains { lowercaseContent.contains($0) }
        
        for match in matches {
            guard let range = Range(match.range, in: content) else { continue }
            let candidate = String(content[range])
            let digits = candidate.filter { $0.isNumber }
            
            guard (13...19).contains(digits.count) else { continue }
            guard hasKnownCardPrefix(digits) else { continue }
            guard passesLuhnCheck(digits) else { continue }
            
            let coverage = Double(match.range.length) / Double(max(content.count, 1))
            let nearStandalone = content.count <= match.range.length + 12
            if coverage > 0.45 || nearStandalone || hasCardKeywords {
                return true
            }
        }
        
        return false
    }
    
    private func isAPIKey(_ content: String) -> Bool {
        let searchRange = NSRange(content.startIndex..., in: content)
        
        // Strong provider-specific patterns first.
        for regex in Patterns.strongAPIKeys {
            if regex.firstMatch(in: content, range: searchRange) != nil {
                return true
            }
        }
        
        // JWT-like tokens often represent auth secrets.
        if Patterns.jwt.firstMatch(in: content, range: searchRange) != nil {
            return true
        }
        
        // Generic key=value/token assignments with sanity checks.
        let assignmentMatches = Patterns.apiKeyAssignment.matches(in: content, range: searchRange)
        for match in assignmentMatches {
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: content) else { continue }
            
            let value = String(content[valueRange])
            if looksLikeSecretValue(value) {
                return true
            }
        }
        
        return false
    }
    
    private func looksLikeSecretValue(_ value: String) -> Bool {
        guard value.count >= 16 else { return false }
        
        let lowered = value.lowercased()
        if Self.apiKeyPlaceholderWords.contains(where: { lowered.contains($0) }) {
            return false
        }
        
        let hasLetters = value.contains { $0.isLetter }
        let hasDigits = value.contains { $0.isNumber }
        guard hasLetters && hasDigits else { return false }
        
        let uniqueCharacterCount = Set(value).count
        return uniqueCharacterCount >= 8
    }
    
    private func hasKnownCardPrefix(_ digits: String) -> Bool {
        let length = digits.count
        
        guard let firstTwo = Int(digits.prefix(2)) else { return false }
        let firstThree = Int(digits.prefix(3)) ?? 0
        let firstFour = Int(digits.prefix(4)) ?? 0
        
        // Visa
        if digits.hasPrefix("4") {
            return [13, 16, 19].contains(length)
        }
        
        // MasterCard (including 2-series)
        if (51...55).contains(firstTwo) || (2221...2720).contains(firstFour) {
            return length == 16
        }
        
        // American Express
        if [34, 37].contains(firstTwo) {
            return length == 15
        }
        
        // Discover
        if digits.hasPrefix("6011") || digits.hasPrefix("65") || (644...649).contains(firstThree) {
            return [16, 19].contains(length)
        }
        
        // Diners Club
        if (300...305).contains(firstThree) || [36, 38, 39].contains(firstTwo) {
            return length == 14
        }
        
        // JCB
        if (3528...3589).contains(firstFour) {
            return (16...19).contains(length)
        }
        
        return false
    }
    
    private func passesLuhnCheck(_ digits: String) -> Bool {
        let reversedDigits = digits.reversed().compactMap { Int(String($0)) }
        guard reversedDigits.count == digits.count else { return false }
        
        let sum = reversedDigits.enumerated().reduce(0) { partial, element in
            let (index, digit) = element
            if index % 2 == 1 {
                let doubled = digit * 2
                return partial + (doubled > 9 ? doubled - 9 : doubled)
            }
            return partial + digit
        }
        
        return sum % 10 == 0
    }
    
    private func isJSON(_ content: String) -> Bool {
        // Quick check for JSON structure
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            
            // Try to parse as JSON
            if let data = content.data(using: .utf8) {
                do {
                    _ = try JSONSerialization.jsonObject(with: data)
                    return true
                } catch {
                    return false
                }
            }
        }
        return false
    }
    
    private func isXML(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for XML declaration or root element
        if trimmed.hasPrefix("<?xml") ||
           (trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && trimmed.contains("</")) {

            // Basic XML validation
            let openTags = content.components(separatedBy: "<").count - 1
            let closeTags = content.components(separatedBy: "</").count - 1

            // Should have roughly matching open/close tags
            return abs(openTags - closeTags * 2) <= 2
        }

        // Self-closing XML tags like <add key="foo" />
        if trimmed.hasPrefix("<") && trimmed.hasSuffix("/>") {
            return true
        }

        return false
    }
    
    private func isMarkdown(_ content: String) -> Bool {
        let markdownPatterns = [
            "^#{1,6}\\s+", // Headers
            "\\*\\*.*\\*\\*", // Bold
            "\\*.*\\*", // Italic
            "^\\s*[-*+]\\s+", // Lists
            "^\\s*\\d+\\.\\s+", // Numbered lists
            "```", // Code blocks
            "\\[.*\\]\\(.*\\)", // Links
            "^>\\s+" // Blockquotes
        ]
        
        let markdownCount = markdownPatterns.reduce(0) { count, pattern in
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                return count + regex.matches(in: content, range: NSRange(content.startIndex..., in: content)).count
            }
            return count
        }
        
        return markdownCount >= 2
    }
    
    private func extractPrimaryURL(from content: String) -> URL? {
        let fullRange = NSRange(content.startIndex..., in: content)
        
        if let urlMatch = Patterns.url.firstMatch(in: content, range: fullRange),
           let range = Range(urlMatch.range, in: content) {
            let rawCandidate = String(content[range])
            if isDominantMatch(urlMatch.range, in: content, threshold: 0.55) {
                return normalizedURL(from: rawCandidate)
            }
        }
        
        let simpleMatches = Patterns.urlSimple.matches(in: content, range: fullRange)
        if let match = simpleMatches.max(by: { $0.range.length < $1.range.length }),
           let range = Range(match.range, in: content) {
            let rawCandidate = String(content[range])
            if isDominantMatch(match.range, in: content, threshold: 0.70) {
                return normalizedURL(from: rawCandidate)
            }
        }
        
        return nil
    }
    
    private func isDominantMatch(_ range: NSRange, in content: String, threshold: Double) -> Bool {
        let contentLength = max(content.count, 1)
        let coverage = Double(range.length) / Double(contentLength)
        
        if coverage >= threshold {
            return true
        }
        
        // Prevent email addresses (user@domain.com) from being treated as URLs.
        if content.contains("@") {
            return false
        }
        
        // Allow slightly lower coverage for short one-line inputs.
        return content.count <= 48 && coverage >= threshold - 0.15
    }
    
    private func normalizedURL(from rawValue: String) -> URL? {
        let trimmedCandidate = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)\"]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "([\""))
        
        let candidate: String
        if trimmedCandidate.lowercased().hasPrefix("http://") || trimmedCandidate.lowercased().hasPrefix("https://") {
            candidate = trimmedCandidate
        } else {
            candidate = "https://\(trimmedCandidate)"
        }
        
        return URL(string: candidate)
    }
    
    private func primaryURLHost(from content: String) -> String? {
        guard let url = extractPrimaryURL(from: content), var host = url.host?.lowercased() else {
            return nil
        }
        
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        
        return host
    }
    
    private func hostMatchesDomain(_ host: String, domains: [String]) -> Bool {
        for domain in domains {
            if host == domain || host.hasSuffix(".\(domain)") {
                return true
            }
        }
        return false
    }
}
