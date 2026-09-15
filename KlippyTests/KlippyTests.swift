import XCTest
import CoreData
@testable import Klippy

final class KlippyTests: XCTestCase {
    
    var testContext: NSManagedObjectContext!
    var contentClassifier: ContentClassifier!
    
    override func setUpWithError() throws {
        // Create in-memory Core Data stack for testing
        testContext = createTestContext()
        contentClassifier = ContentClassifier()
    }

    private func createTestContext() -> NSManagedObjectContext {
        let model = createTestDataModel()
        let container = NSPersistentContainer(name: "TestDataModel", managedObjectModel: model)

        // Use in-memory store for testing
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Test Core Data error: \(error)")
            }
        }

        return container.viewContext
    }

    /// The app's real Core Data model, loaded from the built bundle.
    ///
    /// This used to be a hand-written NSManagedObjectModel. It silently drifted
    /// from DataModel.xcdatamodeld, so tests failed on attributes the real app
    /// has had for months. Loading the shipped model means it cannot drift.
    // MARK: - Regressions found 2026-09-14

    /// A phone number has to be the whole clip, not a ten digit run inside it.
    func testTextContainingDigitsIsNotAPhoneNumber() {
        let notPhones = [
            "sandbox capture test 1789405469",
            "order 4155552671 shipped on Tuesday",
            "1789405469",
            "Janine Powell is inviting you to a Zoom meeting 8161692183"
        ]
        for value in notPhones {
            XCTAssertNotEqual(contentClassifier.classify(value), .phone,
                              "\(value) should not be filed as a phone number")
        }
    }

    func testRealPhoneNumbersStillClassify() {
        for value in ["+1 (555) 123-4567", "555-123-4567", "+447911123456"] {
            XCTAssertEqual(contentClassifier.classify(value), .phone,
                           "\(value) should be a phone number")
        }
    }

    /// Telegram bot tokens start with digits, so they were read as phone
    /// numbers and shown in the clear instead of being treated as secrets.
    func testTelegramBotTokenIsASecret() {
        let token = "7574611370:AAH3ogS5NFpd64OT-pshCcJ1jZeWadZpudYxx"
        XCTAssertEqual(contentClassifier.classify(token), .apiKey)
    }

    /// Text that is not a path must never be turned into a file reference.
    /// URL(fileURLWithPath:) accepts anything and resolves it relative to the
    /// working directory, which produced files inside the app's own container.
    func testNonPathContentYieldsNoFileReferences() {
        for value in ["Image (764\u{00D7}1024)", "python /workspace/abliterate.py", "heretic \\"] {
            let item = ClipboardItemViewModel(id: UUID(),
                                              content: value,
                                              category: .file,
                                              createdAt: Date(),
                                              lastAccessedAt: Date())
            XCTAssertTrue(item.fileReferences.isEmpty,
                          "\(value) should not look like a file")
        }
    }

    func testAbsolutePathsStillResolve() {
        let item = ClipboardItemViewModel(id: UUID(),
                                          content: "/Users/someone/Downloads/photo.png",
                                          category: .file,
                                          createdAt: Date(),
                                          lastAccessedAt: Date())
        XCTAssertEqual(item.fileReferences.count, 1)
        XCTAssertEqual(item.fileReferences.first?.url.path,
                       "/Users/someone/Downloads/photo.png")
    }

    /// Truncation must not walk the whole string to decide it is long.
    func testDisplayTextTruncatesLargeContentQuickly() {
        let huge = String(repeating: "a", count: 4_000_000)
        let item = ClipboardItemViewModel(id: UUID(),
                                          content: huge,
                                          category: .text,
                                          createdAt: Date(),
                                          lastAccessedAt: Date())
        let started = Date()
        let shown = item.displayText
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(shown.count, 203)
        XCTAssertLessThan(elapsed, 0.01, "displayText should not scan the whole clip")
    }

    /// Prose is not an address. "St" used to match inside "first" and "just",
    /// and the pattern spanned newlines, so whole documents became addresses.
    func testProseIsNotAnAddress() {
        let notAddresses = [
            "I found out that I wasn't able to drag an image from the app, it must be 2 things",
            "design a mobile app onboarding and home, use iphone 16 pro, 3 screens first",
            "We have 1 hundred users and I just replaced the placeholder always",
            "Order 12345 shipped, opportunity to always replace the driver"
        ]
        for value in notAddresses {
            XCTAssertNotEqual(contentClassifier.classify(value), .address,
                              "\(value) should not be an address")
        }
    }

    func testRealAddressesStillClassify() {
        for value in ["1600 Pennsylvania Avenue", "221B Baker Street", "350 Fifth Ave"] {
            XCTAssertEqual(contentClassifier.classify(value), .address,
                           "\(value) should be an address")
        }
    }

    /// A document must never be classified as a single value, and deciding
    /// that must not require scanning the whole thing.
    func testLargeDocumentIsNotASingleValue() {
        let emails = (0..<20_000).map { "person\($0)@example.com" }.joined(separator: "\n")
        let started = Date()
        let category = contentClassifier.classify(emails)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertFalse([.phone, .address, .color, .number, .date, .email, .file]
            .contains(category), "a 20k line dump should not be a single value")
        XCTAssertLessThan(elapsed, 1.0, "classifying a large clip should not be slow")
    }

    /// Every platform people actually share from must land under Social, not
    /// plain URLs. The list started with fifteen domains and missed Telegram,
    /// WhatsApp, Discord, Twitch, Bluesky, Threads and more.
    func testSocialPlatformsAreSocial() {
        let social = [
            "https://www.tiktok.com/@nasa", "https://vm.tiktok.com/ZP8srKfMD/",
            "https://youtu.be/dQw4w9WgXcQ", "https://m.youtube.com/watch?v=x",
            "https://www.reddit.com/r/macapps", "https://redd.it/abc123",
            "https://x.com/user/status/1", "https://twitter.com/user",
            "https://www.instagram.com/p/abc/", "https://www.threads.com/@user",
            "https://t.me/somechannel", "https://wa.me/15551234567",
            "https://discord.gg/abcdef", "https://www.twitch.tv/someone",
            "https://bsky.app/profile/someone", "https://www.tumblr.com/blog",
            "https://www.linkedin.com/in/someone", "https://lnkd.in/abc",
            "https://snapchat.com/t/kCfypmbw", "https://www.facebook.com/profile.php?id=1",
            "https://kick.com/someone", "https://rumble.com/v1.html",
            "https://www.pinterest.com/pin/1/", "https://vk.com/id1",
            "https://www.quora.com/q", "https://mastodon.social/@user"
        ]
        for link in social {
            let category = contentClassifier.classify(link)
            XCTAssertTrue(ContentCategory.socialCategories.contains(category),
                          "\(link) should be social, got \(category)")
        }
    }

    /// Work tools and ordinary sites must stay out of Social.
    func testNonSocialLinksStayUnderURLs() {
        let plain = [
            "https://github.com/ceorkm/klippy",
            "https://stackoverflow.com/questions/12345",
            "https://www.bbc.com/news",
            "https://klippy.slack.com/archives/C1",
            "https://docs.google.com/document/d/1/edit"
        ]
        for link in plain {
            XCTAssertEqual(contentClassifier.classify(link), .url,
                           "\(link) should be a plain URL")
        }
    }

    /// The Social tab groups the three social link kinds, which have no tab
    /// of their own. Pinned, Merged and Saved filter through matches(), so a
    /// TikTok or Instagram link must match the Social filter or it vanishes
    /// from those views. Plain URLs must stay out to keep the tabs disjoint.
    func testSocialLinkKindsMatchSocialFilter() {
        XCTAssertTrue(ContentCategory.tiktokURL.matches(.socialMedia))
        XCTAssertTrue(ContentCategory.instagramURL.matches(.socialMedia))
        XCTAssertTrue(ContentCategory.socialMedia.matches(.socialMedia))
        XCTAssertFalse(ContentCategory.url.matches(.socialMedia))
        XCTAssertFalse(ContentCategory.text.matches(.socialMedia))
        XCTAssertTrue(ContentCategory.tiktokURL.matches(.all))
    }

    // MARK: - Audit against a real library

    /// Runs the classifier over every clip in a real database and writes a
    /// report of what lands where, with samples.
    ///
    /// Skipped unless KLIPPY_AUDIT_DB points at a copy of a store. This is not
    /// a pass/fail test: it is how we check the classifier against real content
    /// instead of against the handful of strings we thought to write down.
    func testAuditRealLibrary() throws {
        // A fixed location rather than an environment variable: xcodebuild does
        // not forward the environment to an app-hosted test process.
        let documents = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = documents.appendingPathComponent("audit.sqlite")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Drop a store at \(source.path) to audit a real library")
        }
        let path = source.path

        let model = createTestDataModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                           configurationName: nil,
                                           at: URL(fileURLWithPath: path),
                                           options: [NSReadOnlyPersistentStoreOption: true])
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        let request = NSFetchRequest<NSManagedObject>(entityName: "ClipboardItem")
        request.returnsObjectsAsFaults = false
        let rows = try context.fetch(request)

        var counts: [ContentCategory: Int] = [:]
        var samples: [ContentCategory: [String]] = [:]
        let classifier = ContentClassifier()

        for row in rows {
            guard let content = row.value(forKey: "content") as? String,
                  !content.isEmpty else { continue }
            if (row.value(forKey: "isImage") as? Bool) == true { continue }

            let category = classifier.classify(content)
            counts[category, default: 0] += 1
            if samples[category, default: []].count < 25 {
                let oneLine = content
                    .replacingOccurrences(of: "\n", with: " / ")
                    .replacingOccurrences(of: "\r", with: " ")
                samples[category, default: []].append(String(oneLine.prefix(110)))
            }
        }

        var report = "AUDIT of \(rows.count) clips\n\n"
        for (category, count) in counts.sorted(by: { $0.value > $1.value }) {
            report += "=== \(category) (\(count)) ===\n"
            for sample in samples[category] ?? [] {
                report += "    \(sample)\n"
            }
            report += "\n"
        }

        let out = documents.appendingPathComponent("klippy-audit.txt")
        try report.write(to: out, atomically: true, encoding: .utf8)
        print("AUDIT WRITTEN TO \(out.path)")
    }

    private func createTestDataModel() -> NSManagedObjectModel {
        let bundle = Bundle(for: type(of: self))
        let candidates = [bundle, Bundle.main] + Bundle.allBundles
        for candidate in candidates {
            if let url = candidate.url(forResource: "DataModel", withExtension: "momd"),
               let model = NSManagedObjectModel(contentsOf: url) {
                return model
            }
        }
        fatalError("DataModel.momd not found in any loaded bundle")
    }
    
    override func tearDownWithError() throws {
        testContext = nil
        contentClassifier = nil
    }
    
    // MARK: - Content Classification Tests
    
    func testURLClassification() throws {
        let urls = [
            "https://www.apple.com",
            "http://github.com/user/repo",
            "www.google.com",
            "apple.com/support"
        ]
        
        for url in urls {
            let category = contentClassifier.classify(url)
            XCTAssertEqual(category, .url, "Failed to classify '\(url)' as URL")
        }
    }
    
    func testEmailClassification() throws {
        let emails = [
            "user@example.com",
            "test.email+tag@domain.co.uk",
            "simple@test.org"
        ]
        
        for email in emails {
            let category = contentClassifier.classify(email)
            XCTAssertEqual(category, .email, "Failed to classify '\(email)' as email")
        }
    }
    
    func testPhoneNumberClassification() throws {
        let phones = [
            "(555) 123-4567",
            "555-123-4567",
            "+1-555-123-4567",
            "+44 20 7946 0958"
        ]
        
        for phone in phones {
            let category = contentClassifier.classify(phone)
            XCTAssertEqual(category, .phone, "Failed to classify '\(phone)' as phone number")
        }
    }
    
    func testCodeClassification() throws {
        let codeSnippets = [
            "function test() { return true; }",
            "var name = 'John';",
            "let items = [1, 2, 3];"
        ]

        for code in codeSnippets {
            let category = contentClassifier.classify(code)
            XCTAssertEqual(category, .code, "Failed to classify '\(code)' as code")
        }

        // Test HTML (should be classified as XML due to priority)
        let htmlCode = "<div class='container'>Hello</div>"
        let htmlCategory = contentClassifier.classify(htmlCode)
        XCTAssertEqual(htmlCategory, .xml, "HTML should be classified as XML")

        // Test Markdown code blocks (should be classified as Markdown due to priority)
        let markdownCode = "```swift\nprint('Hello')\n```"
        let markdownCategory = contentClassifier.classify(markdownCode)
        XCTAssertEqual(markdownCategory, .markdown, "Markdown code blocks should be classified as Markdown")
    }
    
    func testJSONClassification() throws {
        let jsonStrings = [
            #"{"name": "John", "age": 30}"#,
            #"[{"id": 1}, {"id": 2}]"#,
            #"{"nested": {"value": true}}"#
        ]
        
        for json in jsonStrings {
            let category = contentClassifier.classify(json)
            XCTAssertEqual(category, .json, "Failed to classify '\(json)' as JSON")
        }
    }
    
    func testNumberClassification() throws {
        let numbers = [
            "42",
            "3.14159",
            "-123",
            "$29.99",
            "€15.50"
        ]
        
        for number in numbers {
            let category = contentClassifier.classify(number)
            XCTAssertEqual(category, .number, "Failed to classify '\(number)' as number")
        }
    }
    
    func testPaymentCardClassification() throws {
        let validCardNumbers = [
            "4111 1111 1111 1111",  // Visa test card
            "5555 5555 5555 4444",  // MasterCard test card
            "378282246310005"       // Amex test card
        ]
        
        for cardNumber in validCardNumbers {
            let category = contentClassifier.classify(cardNumber)
            XCTAssertEqual(category, .paymentCard, "Failed to classify '\(cardNumber)' as payment card")
        }
        
        // Should not classify non-Luhn 16-digit values as cards
        let invalidCardLike = "1234 5678 9012 3456"
        XCTAssertNotEqual(contentClassifier.classify(invalidCardLike), .paymentCard)
    }
    
    func testAPIKeyClassification() throws {
        let apiLikeValues = [
            "sk-proj-abcdefghijklmnopqrstuvwxyz123456",
            "sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890",
            "fc-abcdefghijklmnopqrstuvwxyz123456",
            "ghp_1234567890abcdefghijklmnopqrstuvwxyz",
            "AKIAIOSFODNN7EXAMPLE",
            "hf_abcdefghijklmnopqrstuvwxyzABCDEFGH123456",
            "SG.qwertyuiopasdfghjklzxcvbnm123456.ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",
            "sq0atp-abcdefghijklmnopqrstuvwxyz1234567890",
            "xai-abcdefghijklmnopqrstuvwxyz1234567890",
            "npm_abcdefghijklmnopqrstuvwxyz1234567890",
            "ya29.a0AfH6SMBEXAMPLE1234567890abcdefghijklmnopqrstuvwxyz",
            "api_key = \"mySecretToken1234567890abcd\""
        ]
        
        for value in apiLikeValues {
            let category = contentClassifier.classify(value)
            XCTAssertEqual(category, .apiKey, "Failed to classify '\(value)' as API key")
        }
        
        let placeholder = "YOUR_API_KEY_HERE"
        XCTAssertNotEqual(contentClassifier.classify(placeholder), .apiKey)
    }
    
    func testSocialURLClassification() throws {
        let instagramURL = "https://www.instagram.com/p/C12345xyz/"
        XCTAssertEqual(contentClassifier.classify(instagramURL), .instagramURL)
        
        let tiktokURL = "https://vm.tiktok.com/ZMExample123/"
        XCTAssertEqual(contentClassifier.classify(tiktokURL), .tiktokURL)
        
        let socialURL = "https://x.com/klippy/status/123456789"
        XCTAssertEqual(contentClassifier.classify(socialURL), .socialMedia)
        
        let regularURL = "https://developer.apple.com/documentation"
        XCTAssertEqual(contentClassifier.classify(regularURL), .url)
    }
    
    // MARK: - Core Data Tests
    
    func testClipboardItemCreation() throws {
        let content = "Test clipboard content"
        let category = ContentCategory.text
        
        let item = ClipboardItem.create(
            content: content,
            category: category,
            sourceApp: "TestApp",
            context: testContext
        )
        
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.content, content)
        XCTAssertEqual(item.categoryEnum, category)
        XCTAssertEqual(item.sourceApplication, "TestApp")
        XCTAssertNotNil(item.createdAt)
        XCTAssertNotNil(item.contentHash)
        XCTAssertEqual(item.usageCount, 0)
    }
    
    func testClipboardItemUsageUpdate() throws {
        let item = ClipboardItem.create(
            content: "Test content",
            category: .text,
            context: testContext
        )
        
        let originalUsageCount = item.usageCount
        let originalLastAccessed = item.lastAccessedAt
        
        // Wait a moment to ensure timestamp difference
        Thread.sleep(forTimeInterval: 0.01)
        
        item.updateLastAccessed()
        
        XCTAssertEqual(item.usageCount, originalUsageCount + 1)
        XCTAssertGreaterThan(item.lastAccessedAt!, originalLastAccessed!)
    }

    func testFileBundleViewModelParsing() throws {
        let file1 = URL(fileURLWithPath: "/tmp/Quarterly Report.pdf")
        let file2 = URL(fileURLWithPath: "/tmp/Mockup.png")
        let serialized = [file1.absoluteString, file2.absoluteString].joined(separator: "\n")

        let viewModel = ClipboardItemViewModel(
            content: serialized,
            category: .file
        )

        XCTAssertTrue(viewModel.isFileReference)
        XCTAssertEqual(viewModel.fileURLs.count, 2)
        XCTAssertEqual(viewModel.fileURLs[0], file1)
        XCTAssertEqual(viewModel.fileURLs[1], file2)
        XCTAssertEqual(viewModel.fileDisplayText, "Quarterly Report.pdf +1 more")
    }

    func testFileBundlePathFallbackParsing() throws {
        let viewModel = ClipboardItemViewModel(
            content: "/tmp/notes.txt",
            category: .file
        )

        XCTAssertTrue(viewModel.isFileReference)
        XCTAssertEqual(viewModel.fileURLs.count, 1)
        XCTAssertEqual(viewModel.fileURLs[0], URL(fileURLWithPath: "/tmp/notes.txt"))
        XCTAssertEqual(viewModel.fileDisplayText, "notes.txt")
    }
    
    // MARK: - Performance Tests
    
    func testLargeDatasetCreation() throws {
        let itemCount = 1000 // Reduced for faster testing
        let startTime = Date()
        
        for i in 0..<itemCount {
            let content = "Test item \(i) with some content to simulate real clipboard data"
            let category = ContentCategory.allCases.randomElement() ?? .text
            
            _ = ClipboardItem.create(
                content: content,
                category: category,
                sourceApp: "TestApp",
                context: testContext
            )
        }
        
        try testContext.save()
        
        let creationTime = Date().timeIntervalSince(startTime)
        print("Created \(itemCount) items in \(creationTime) seconds")
        
        // Verify creation was reasonably fast (should be under 2 seconds)
        XCTAssertLessThan(creationTime, 2.0, "Large dataset creation took too long")
        
        // Verify all items were created
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        let count = try testContext.count(for: request)
        XCTAssertEqual(count, itemCount)
    }
    
    // MARK: - Content Hash Tests
    
    func testContentHashing() throws {
        let content1 = "This is test content"
        let content2 = "This is test content"
        let content3 = "This is different content"
        
        let hash1 = content1.sha256
        let hash2 = content2.sha256
        let hash3 = content3.sha256
        
        XCTAssertEqual(hash1, hash2, "Same content should produce same hash")
        XCTAssertNotEqual(hash1, hash3, "Different content should produce different hash")
        XCTAssertEqual(hash1.count, 64, "SHA256 hash should be 64 characters")
    }
    
    // MARK: - Category Tests
    
    func testCategoryProperties() throws {
        for category in ContentCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "Category should have display name")
            XCTAssertFalse(category.iconName.isEmpty, "Category should have icon name")
            // Color property should not crash
            _ = category.color
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyContentClassification() throws {
        let category = contentClassifier.classify("")
        XCTAssertEqual(category, .other, "Empty content should be classified as other")
    }
    
    func testWhitespaceContentClassification() throws {
        let category = contentClassifier.classify("   \n\t   ")
        XCTAssertEqual(category, .other, "Whitespace-only content should be classified as other")
    }
    
    func testVeryLongContentClassification() throws {
        let longContent = String(repeating: "a", count: 10000)
        let category = contentClassifier.classify(longContent)
        XCTAssertEqual(category, .text, "Very long content should be classified as text")
    }
}
