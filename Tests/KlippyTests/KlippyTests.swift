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

    private func createTestDataModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Create ClipboardItem entity
        let clipboardItemEntity = NSEntityDescription()
        clipboardItemEntity.name = "ClipboardItem"
        clipboardItemEntity.managedObjectClassName = "ClipboardItem"

        // Add attributes (simplified for testing)
        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .UUIDAttributeType
        idAttribute.isOptional = true

        let contentAttribute = NSAttributeDescription()
        contentAttribute.name = "content"
        contentAttribute.attributeType = .stringAttributeType
        contentAttribute.isOptional = true

        let contentTypeAttribute = NSAttributeDescription()
        contentTypeAttribute.name = "contentType"
        contentTypeAttribute.attributeType = .integer16AttributeType
        contentTypeAttribute.defaultValue = 0

        let contentHashAttribute = NSAttributeDescription()
        contentHashAttribute.name = "contentHash"
        contentHashAttribute.attributeType = .stringAttributeType
        contentHashAttribute.isOptional = true

        let searchableContentAttribute = NSAttributeDescription()
        searchableContentAttribute.name = "searchableContent"
        searchableContentAttribute.attributeType = .stringAttributeType
        searchableContentAttribute.isOptional = true

        let createdAtAttribute = NSAttributeDescription()
        createdAtAttribute.name = "createdAt"
        createdAtAttribute.attributeType = .dateAttributeType
        createdAtAttribute.isOptional = true

        let lastAccessedAtAttribute = NSAttributeDescription()
        lastAccessedAtAttribute.name = "lastAccessedAt"
        lastAccessedAtAttribute.attributeType = .dateAttributeType
        lastAccessedAtAttribute.isOptional = true

        let usageCountAttribute = NSAttributeDescription()
        usageCountAttribute.name = "usageCount"
        usageCountAttribute.attributeType = .integer32AttributeType
        usageCountAttribute.defaultValue = 0

        let sourceApplicationAttribute = NSAttributeDescription()
        sourceApplicationAttribute.name = "sourceApplication"
        sourceApplicationAttribute.attributeType = .stringAttributeType
        sourceApplicationAttribute.isOptional = true

        let tagsAttribute = NSAttributeDescription()
        tagsAttribute.name = "tags"
        tagsAttribute.attributeType = .stringAttributeType
        tagsAttribute.isOptional = true

        let imageDataAttribute = NSAttributeDescription()
        imageDataAttribute.name = "imageData"
        imageDataAttribute.attributeType = .binaryDataAttributeType
        imageDataAttribute.isOptional = true

        let imageWidthAttribute = NSAttributeDescription()
        imageWidthAttribute.name = "imageWidth"
        imageWidthAttribute.attributeType = .integer32AttributeType
        imageWidthAttribute.defaultValue = 0

        let imageHeightAttribute = NSAttributeDescription()
        imageHeightAttribute.name = "imageHeight"
        imageHeightAttribute.attributeType = .integer32AttributeType
        imageHeightAttribute.defaultValue = 0

        let isImageAttribute = NSAttributeDescription()
        isImageAttribute.name = "isImage"
        isImageAttribute.attributeType = .booleanAttributeType
        isImageAttribute.defaultValue = false

        clipboardItemEntity.properties = [
            idAttribute,
            contentAttribute,
            contentTypeAttribute,
            contentHashAttribute,
            searchableContentAttribute,
            createdAtAttribute,
            lastAccessedAtAttribute,
            usageCountAttribute,
            sourceApplicationAttribute,
            tagsAttribute,
            imageDataAttribute,
            imageWidthAttribute,
            imageHeightAttribute,
            isImageAttribute
        ]

        model.entities = [clipboardItemEntity]
        return model
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
