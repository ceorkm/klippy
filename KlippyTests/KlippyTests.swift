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
    // MARK: - Regressions found 2026-09-17

    /// Merging used to take every clip's raw content. A picture's content is
    /// its label, so two photographs merged into two lines of text and no
    /// pictures; a file clip's content is the encoded bundle, so merging one
    /// pasted base64.
    func testMergeLeavesPicturesOutAndUsesFilePaths() {
        let first = ClipboardItemViewModel(content: "first line", category: .text)
        let second = ClipboardItemViewModel(content: "second line", category: .text)
        let picture = ClipboardItemViewModel(content: "Image (764x1024)",
                                             category: .image, isImage: true,
                                             imageWidth: 764, imageHeight: 1024)
        let json = #"{"version":2,"entries":[{"url":"file:///Users/example/report.pdf"}]}"#
        let bundle = "klippy-file-bundle-v2:" + Data(json.utf8).base64EncodedString()
        let fileClip = ClipboardItemViewModel(content: bundle, category: .file)

        let parts = KlippyPanel.mergeComponents(from: [first, picture, second, fileClip])

        XCTAssertEqual(parts, ["first line", "second line", "/Users/example/report.pdf"])
        XCTAssertFalse(parts.contains { $0.hasPrefix("klippy-file-bundle") },
                       "the encoded bundle must never become merged text")
    }

    /// Selecting two pictures and pressing Merge has nothing to join, so the
    /// panel must say so rather than build a clip of their labels.
    func testMergingOnlyPicturesHasNothingToJoin() {
        let one = ClipboardItemViewModel(content: "Image (10x10)", category: .image, isImage: true)
        let two = ClipboardItemViewModel(content: "Image (20x20)", category: .image, isImage: true)
        XCTAssertTrue(KlippyPanel.mergeComponents(from: [one, two]).isEmpty)
    }

    // MARK: - Regressions found 2026-09-17

    /// Previews used to load every copied URL, which consumes one-time links.
    /// The first fix over-corrected and refused anything with a query, which
    /// silently killed previews for YouTube, Google, Amazon and Hacker News.
    func testLinkPreviewsRefuseTokenBearingURLs() {
        let safe = [
            "https://example.com/blog/post",
            "http://github.com/ceorkm/klippy",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://news.ycombinator.com/item?id=41234567",
            "https://www.google.com/search?q=swift+actor",
            "https://developer.apple.com/documentation/swiftui/view#overview",
            "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"
        ]
        let unsafe = [
            "https://x.com/reset?token=abc",
            "https://x.com/login/aB3dE5fG7hI9jK1lM3nO5pQ7",
            "https://app.example.com/#access_token=abc123",
            "https://example.com/unsubscribe?u=99&id=12",
            "https://mail.example.com/verify/a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
            "https://example.com/callback?code=4AX4XfWh",
            "ftp://x.com/a"
        ]
        for value in safe {
            XCTAssertTrue(LinkPreviewStore.isSafeToLoad(URL(string: value)!), value)
        }
        for value in unsafe {
            XCTAssertFalse(LinkPreviewStore.isSafeToLoad(URL(string: value)!), value)
        }
    }

    /// Transient and auto-generated writes are never the user copying
    /// something, so they are skipped whatever the password-manager toggle says.
    func testTransientPasteboardIsSkippedEvenWithConcealedToggleOff() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ClipboardPrivacy.ignoreConcealedKey)
        defaults.set(false, forKey: ClipboardPrivacy.ignoreConcealedKey)
        defer { defaults.set(previous, forKey: ClipboardPrivacy.ignoreConcealedKey) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("klippy.tests.transient"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
        pasteboard.setString("scratch", forType: .string)

        XCTAssertTrue(ClipboardPrivacy.shouldSkip(pasteboard))
    }

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

// MARK: - Image capture

/// Klippy dropped copied pictures in three separate ways and none of them said
/// anything on screen, so these put a real picture on a real NSPasteboard and
/// check the reader gets it back.
final class ImageCaptureTests: XCTestCase {

    private var board: NSPasteboard!
    private var manager: ClipboardManager!

    override func setUp() {
        super.setUp()
        board = NSPasteboard(name: NSPasteboard.Name("klippy.tests.\(UUID().uuidString)"))
        manager = ClipboardManager.shared
        manager.pasteboard = board
    }

    override func tearDown() {
        board.releaseGlobally()
        manager.pasteboard = NSPasteboard.general
        super.tearDown()
    }

    private func swatch(_ colour: NSColor, size: NSSize = NSSize(width: 40, height: 30)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        colour.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private func pngData(_ image: NSImage) -> Data {
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    func testFindsAnImageWrittenAsAnObject() {
        board.clearContents()
        board.writeObjects([swatch(.systemRed)])
        XCTAssertNotNil(manager.getImageFromPasteboard(),
                        "an NSImage on the pasteboard must come back as image data")
    }

    func testFindsPNGBytes() {
        board.clearContents()
        board.setData(pngData(swatch(.systemBlue)), forType: .png)
        let found = manager.getImageFromPasteboard()
        XCTAssertNotNil(found, "raw PNG bytes must be captured")
        XCTAssertNotNil(NSImage(data: found ?? Data()), "and must decode back to a picture")
    }

    func testFindsTIFFBytes() {
        board.clearContents()
        board.setData(swatch(.systemGreen).tiffRepresentation!, forType: .tiff)
        XCTAssertNotNil(manager.getImageFromPasteboard(), "TIFF bytes must be captured")
    }

    /// The regression that made images vanish: a picture arriving alongside its
    /// filename used to fall through to being stored as that text.
    func testImageWinsOverAccompanyingText() {
        board.clearContents()
        board.setData(pngData(swatch(.systemOrange)), forType: .png)
        board.setString("Screenshot 2026-09-15 at 10.00.00.png", forType: .string)
        XCTAssertNotNil(manager.getImageFromPasteboard(),
                        "text sitting next to an image must not hide the image")
    }

    func testUndecodablePNGBytesAreStillKept() {
        board.clearContents()
        // A real PNG magic number, then rubbish. Nothing can decode it, and the
        // old reader returned nil for the whole pasteboard because of it.
        var bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        bytes.append(Data(repeating: 0x42, count: 512))
        board.setData(bytes, forType: .png)
        XCTAssertEqual(manager.getImageFromPasteboard(), bytes,
                       "bytes that really are a PNG must be kept even if they will not decode")
    }

    func testEmptyPasteboardYieldsNothing() {
        board.clearContents()
        board.setString("just some text", forType: .string)
        XCTAssertNil(manager.getImageFromPasteboard(),
                     "plain text must not be mistaken for a picture")
    }
}

/// The pasteboard placeholder problem: bytes that are not a picture must never
/// be filed as one.
final class ImageValidationTests: XCTestCase {

    func testRealPNGIsAccepted() {
        let image = NSImage(size: NSSize(width: 20, height: 12))
        image.lockFocus(); NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 12).fill(); image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        let size = ClipboardManager.isRealImage(png)
        XCTAssertNotNil(size, "a real PNG must be accepted")
        XCTAssertEqual(size?.width, 20)
        XCTAssertEqual(size?.height, 12)
    }

    /// The exact bytes found in the real database, stored as a 341x1024 image.
    func testPasteboardPlaceholderIsRejected() {
        var bytes = Data([0x02])
        bytes.append("61F61361-FF76-45EB-993C-C1613AE223D1".data(using: .utf8)!)
        bytes.append(0x00)
        XCTAssertEqual(bytes.count, 38, "same shape as the clip in the real database")
        XCTAssertNil(ClipboardManager.isRealImage(bytes),
                     "a pasteboard placeholder must never be filed as an image")
    }

    func testTruncatedPNGIsRejected() {
        // A PNG magic number and nothing behind it.
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertNil(ClipboardManager.isRealImage(bytes),
                     "a header with no picture behind it is not a picture")
    }

    func testEmptyDataIsRejected() {
        XCTAssertNil(ClipboardManager.isRealImage(Data()))
    }
}

/// Twelve clips in the real database are filed as colours. Some are, most are
/// not: "Admin#12345", "Customer#123" and three multi-paragraph prompts.
final class ColourClassificationTests: XCTestCase {
    private let classifier = ContentClassifier()

    func testRealColoursAreColours() {
        for value in ["#1A6FED", "#5c0818", "#F5F7FA", "#fff", "rgb(12, 34, 56)"] {
            XCTAssertEqual(classifier.classify(value), .color, "\(value) is a colour")
        }
    }

    func testAWordWithAHashIsNotAColour() {
        XCTAssertNotEqual(classifier.classify("Admin#12345"), .color)
        XCTAssertNotEqual(classifier.classify("Customer#123"), .color)
        XCTAssertNotEqual(classifier.classify("issue #abc123"), .color)
    }

    func testProseIsNotAColour() {
        let prompt = """
        Create a premium background image for ENA's landing page. Use #1A6FED as \
        the accent and keep the composition airy, with plenty of negative space \
        so the headline can breathe.
        """
        XCTAssertNotEqual(classifier.classify(prompt), .color)
    }
}

/// Every switch in Settings, checked by flipping it and watching the behaviour
/// change. A setting that reads back correctly but changes nothing is the worst
/// kind of bug: it looks like it worked.
final class SettingsHonourTests: XCTestCase {

    private var board: NSPasteboard!

    override func setUp() {
        super.setUp()
        board = NSPasteboard(name: NSPasteboard.Name("klippy.settings.\(UUID().uuidString)"))
    }

    override func tearDown() {
        board.releaseGlobally()
        UserDefaults.standard.removeObject(forKey: ClipboardPrivacy.ignoreConcealedKey)
        UserDefaults.standard.removeObject(forKey: LinkPreviewStore.enabledKey)
        UserDefaults.standard.removeObject(forKey: "klippy.feedback.hapticsEnabled")
        UserDefaults.standard.removeObject(forKey: ClipboardManager.listLimitKey)
        super.tearDown()
    }

    /// The History list used to stop at a thousand clips no matter how many you
    /// had, with no way to change it. The number is now the user's.
    func testHistorySizeSettingIsWhatTheListActuallyUses() {
        let manager = ClipboardManager.shared

        UserDefaults.standard.removeObject(forKey: ClipboardManager.listLimitKey)
        XCTAssertEqual(manager.listLimit, 1000, "unset means the old default")

        UserDefaults.standard.set(200, forKey: ClipboardManager.listLimitKey)
        XCTAssertEqual(manager.listFetchLimit, 200)

        UserDefaults.standard.set(5000, forKey: ClipboardManager.listLimitKey)
        XCTAssertEqual(manager.listFetchLimit, 5000)
    }

    /// "All" is stored as zero, which a fetch request would read as "none".
    func testAllMeansEveryClipAndNotNone() {
        UserDefaults.standard.set(0, forKey: ClipboardManager.listLimitKey)
        XCTAssertEqual(ClipboardManager.shared.listLimit, 0)
        XCTAssertGreaterThan(ClipboardManager.shared.listFetchLimit, 100_000,
                             "zero must become a ceiling nobody reaches, not an empty list")
    }

    private func concealedBoard() -> NSPasteboard {
        board.clearContents()
        board.setString("hunter2", forType: .string)
        board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        return board
    }

    func testIgnorePasswordManagersOnSkipsTheClip() {
        UserDefaults.standard.set(true, forKey: ClipboardPrivacy.ignoreConcealedKey)
        XCTAssertTrue(ClipboardPrivacy.shouldSkip(concealedBoard()),
                      "switch ON must skip a password manager's copy")
    }

    func testIgnorePasswordManagersOffCapturesTheClip() {
        UserDefaults.standard.set(false, forKey: ClipboardPrivacy.ignoreConcealedKey)
        XCTAssertFalse(ClipboardPrivacy.shouldSkip(concealedBoard()),
                       "switch OFF must let it through, not quietly keep skipping")
    }

    func testPasswordManagersAreProtectedBeforeAnyoneOpensSettings() {
        UserDefaults.standard.removeObject(forKey: ClipboardPrivacy.ignoreConcealedKey)
        XCTAssertTrue(ClipboardPrivacy.shouldSkip(concealedBoard()),
                      "a fresh install must protect passwords by default")
    }

    /// 1Password marks its copies inconsistently, so it is skipped whatever the
    /// switch says. That is deliberate, and worth a test so nobody 'fixes' it.
    func testOnePasswordIsSkippedEvenWithTheSwitchOff() {
        UserDefaults.standard.set(false, forKey: ClipboardPrivacy.ignoreConcealedKey)
        board.clearContents()
        board.setString("secret", forType: .string)
        board.setString("", forType: NSPasteboard.PasteboardType("com.agilebits.onepassword"))
        XCTAssertTrue(ClipboardPrivacy.shouldSkip(board))
    }

    func testLinkPreviewsSwitchIsHonoured() {
        UserDefaults.standard.set(false, forKey: LinkPreviewStore.enabledKey)
        XCTAssertFalse(LinkPreviewStore.isEnabled, "switch OFF must stop the only network call in the app")
        UserDefaults.standard.set(true, forKey: LinkPreviewStore.enabledKey)
        XCTAssertTrue(LinkPreviewStore.isEnabled)
        UserDefaults.standard.removeObject(forKey: LinkPreviewStore.enabledKey)
        XCTAssertTrue(LinkPreviewStore.isEnabled, "on by default")
    }

    func testHapticsSwitchIsHonoured() {
        FeedbackManager.hapticsEnabled = false
        XCTAssertFalse(FeedbackManager.hapticsEnabled)
        FeedbackManager.hapticsEnabled = true
        XCTAssertTrue(FeedbackManager.hapticsEnabled)
        UserDefaults.standard.removeObject(forKey: "klippy.feedback.hapticsEnabled")
        XCTAssertTrue(FeedbackManager.hapticsEnabled, "on by default")
    }

    func testPanelWidthMatchesTheChoice() {
        let store = SkinStore.shared
        let original = store.isWide
        store.isWide = false
        XCTAssertEqual(store.panelWidth, 430, "Compact must be 430, the number on the button")
        store.isWide = true
        XCTAssertEqual(store.panelWidth, 640, "Wide must be 640")
        store.isWide = original
    }

    func testEverySkinInSettingsCanBeSelectedAndReadBack() {
        let store = SkinStore.shared
        let original = store.skin
        for skin in Skin.all {
            store.select(skin)
            XCTAssertEqual(store.skin.id, skin.id, "\(skin.label) must stick")
            XCTAssertEqual(Skin.named(skin.id).id, skin.id, "\(skin.label) must survive a relaunch")
        }
        store.select(original)
    }

    func testAnUnknownSavedSkinFallsBackInsteadOfBreaking() {
        XCTAssertEqual(Skin.named("wheat").id, "dark", "a removed skin must fall back, not crash")
    }
}

/// Using your own picture as the background.
final class CustomSkinTests: XCTestCase {

    private var scratch: URL!
    /// These tests drive the real SkinStore, which writes to the real app
    /// container. Without putting it back, running the suite would quietly
    /// delete whatever picture the owner of the machine had chosen.
    private var previousSkin: Skin!
    private var previousImage: URL?

    override func setUp() {
        super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("klippy-custom-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        previousSkin = SkinStore.shared.skin
        if let existing = SkinStore.shared.customImage,
           let png = existing.tiffRepresentation
            .flatMap(NSBitmapImageRep.init(data:))?
            .representation(using: .png, properties: [:]) {
            let backup = scratch.appendingPathComponent("previous-custom.png")
            try? png.write(to: backup)
            previousImage = backup
        }
    }

    override func tearDown() {
        SkinStore.shared.clearCustomImage()
        if let previousImage { SkinStore.shared.setCustomImage(from: previousImage) }
        SkinStore.shared.select(previousSkin)
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    private func write(_ colour: NSColor, name: String,
                       size: NSSize = NSSize(width: 60, height: 90)) -> URL {
        let image = NSImage(size: size)
        image.lockFocus(); colour.setFill()
        NSRect(origin: .zero, size: size).fill(); image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        let url = scratch.appendingPathComponent("\(name).png")
        try! png.write(to: url)
        return url
    }

    /// Switching to a built-in skin and back used to land you on Dark, because
    /// the built-in list has no "custom" entry to look up.
    func testGoingBackToYourOwnPictureActuallyReturnsToIt() {
        let store = SkinStore.shared
        store.setCustomImage(from: write(.systemIndigo, name: "mine"))
        let chosenScrim = store.skin.scrimTop

        store.select(.meadow)
        XCTAssertEqual(store.skin.id, "meadow")

        store.select(store.customSkin)
        XCTAssertEqual(store.skin.id, "custom", "must come back to the user's picture, not Dark")
        XCTAssertTrue(store.skin.isCustom)
        XCTAssertEqual(store.skin.scrimTop, chosenScrim, accuracy: 0.0001,
                       "the wash measured off the picture must survive the round trip")
    }

    /// A photo off a phone is thousands of pixels across. Stored whole it is
    /// read off disk and decoded at every launch to fill a 640 point panel.
    func testAnOversizedPictureIsShrunkOnTheWayIn() {
        let store = SkinStore.shared
        let huge = NSSize(width: 3200, height: 2400)
        XCTAssertTrue(store.setCustomImage(from: write(.systemOrange, name: "huge", size: huge)))

        let stored = store.customImage
        XCTAssertNotNil(stored)
        let widest = max(stored!.size.width, stored!.size.height)
        XCTAssertLessThanOrEqual(widest, 1600,
                                 "a 3200px picture must not be kept at full size")
        XCTAssertGreaterThan(widest, 1000, "shrinking must not leave a thumbnail")
    }

    /// Anything already small enough is left alone rather than resampled.
    func testASmallPictureIsKeptAtItsOwnSize() {
        let store = SkinStore.shared
        store.setCustomImage(from: write(.systemGreen, name: "small",
                                         size: NSSize(width: 800, height: 600)))
        XCTAssertEqual(store.customImage?.size.width ?? 0, 800, accuracy: 1)
    }

    func testChoosingAPictureSelectsItAndNamesIt() {
        let store = SkinStore.shared
        XCTAssertTrue(store.setCustomImage(from: write(.systemTeal, name: "beach")))
        XCTAssertTrue(store.hasCustomImage)
        XCTAssertEqual(store.customName, "beach", "the swatch should be named after the file")
        XCTAssertEqual(store.skin.id, "custom", "picking a picture must switch to it")
        XCTAssertTrue(store.skin.isCustom)
        XCTAssertTrue(store.skin.isImageBacked)
    }

    /// The wash over the picture is measured off the picture, not guessed, so
    /// white text stays readable on a bright photo.
    func testABrightPictureGetsAHeavierWashThanADarkOne() {
        let store = SkinStore.shared
        store.setCustomImage(from: write(.white, name: "bright"))
        let bright = store.skin.scrimTop
        store.setCustomImage(from: write(.black, name: "dark"))
        let dark = store.skin.scrimTop
        XCTAssertGreaterThan(bright, dark,
                             "a white picture needs more wash than a black one")
        XCTAssertLessThanOrEqual(bright, 0.72)
        XCTAssertGreaterThanOrEqual(dark, 0.15)
    }

    func testRemovingThePictureFallsBackInsteadOfShowingNothing() {
        let store = SkinStore.shared
        store.setCustomImage(from: write(.systemPink, name: "pink"))
        store.clearCustomImage()
        XCTAssertFalse(store.hasCustomImage)
        XCTAssertNil(store.customName)
        XCTAssertEqual(store.skin.id, "dark", "must not leave the panel with no background")
    }

    func testAFileThatIsNotAPictureIsRefused() {
        let url = scratch.appendingPathComponent("notes.png")
        try! "this is not a picture".data(using: .utf8)!.write(to: url)
        XCTAssertFalse(SkinStore.shared.setCustomImage(from: url))
        XCTAssertFalse(SkinStore.shared.hasCustomImage)
    }
}

/// The "never record" list. It exists because "Ignore password managers" only
/// covers apps that mark their copies as concealed, and a tool that handles
/// secrets but copies as plain text slips straight past it.
final class ExclusionTests: XCTestCase {

    private let store = ExclusionStore.shared

    override func tearDown() {
        for kind in ContentCategory.allCases { store.setExcluded(false, kind: kind) }
        super.tearDown()
    }

    func testAKindCanBeExcluded() {
        XCTAssertFalse(store.excludes(category: .paymentCard))
        store.setExcluded(true, kind: .paymentCard)
        XCTAssertTrue(store.excludes(category: .paymentCard))
        XCTAssertFalse(store.excludes(category: .apiKey),
                       "ticking one kind must not tick the others")
    }

    /// The choice has to survive a relaunch, which means it has to be in
    /// UserDefaults rather than only in memory.
    func testTheChoiceIsWrittenDown() {
        store.setExcluded(true, kind: .apiKey)

        let kinds = UserDefaults.standard.array(forKey: "klippy.privacy.excludedKinds") as? [Int] ?? []
        XCTAssertTrue(kinds.contains(Int(ContentCategory.apiKey.rawValue)))
    }

    /// Switching everything off must not leave the app unable to record.
    func testNothingIsExcludedByDefault() {
        for kind in ContentCategory.allCases {
            store.setExcluded(false, kind: kind)
        }
        XCTAssertTrue(ExclusionStore.offerable.allSatisfy { !store.excludes(category: $0) })
    }

    /// The list offered in Settings must not contain a kind that would switch
    /// off most of the app, or one that is not a thing you copy.
    func testTheOfferedKindsAreSane() {
        XCTAssertFalse(ExclusionStore.offerable.contains(.all))
        XCTAssertFalse(ExclusionStore.offerable.contains(.text))
        XCTAssertFalse(ExclusionStore.offerable.contains(.merged))
        XCTAssertTrue(ExclusionStore.offerable.contains(.paymentCard))
        XCTAssertTrue(ExclusionStore.offerable.contains(.apiKey))
    }
}
