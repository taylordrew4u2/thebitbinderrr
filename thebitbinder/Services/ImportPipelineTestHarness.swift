//
//  ImportPipelineTestHarness.swift
//  thebitbinder
//
//  Internal test harness for import pipeline evaluation
//  Run tests via: await ImportPipelineTestHarness.shared.runAllTests()
//

import Foundation
import CoreGraphics

/// Internal test harness for evaluating import pipeline performance
/// This class provides manual testing utilities without requiring XCTest framework
final class ImportPipelineTestHarness {
    
    private let coordinator = ImportPipelineCoordinator.shared
    private let router = ImportRouter.shared
    private let validator = JokeBlockValidator.shared
    
    static let shared = ImportPipelineTestHarness()
    private init() {}
    
    private var passCount = 0
    private var failCount = 0
    
    // MARK: - Test Runner
    
    func runAllTests() async {
        print("🧪 Starting Import Pipeline Tests...")
        passCount = 0
        failCount = 0
        
        await testSingleJokeBlock()
        await testMultipleJokesSeparatedByGaps()
        await testBulletedJokeList()
        testSingleJokeValidation()
        testMultipleJokeDetection()
        testLongJokeValidation()
        await testAllTestCases()
        
        print("\n🧪 Test Results: \(passCount) passed, \(failCount) failed")
    }
    
    // MARK: - Assertion Helpers
    
    private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            print("    ✅ PASS: \(message)")
            passCount += 1
        } else {
            print("    ❌ FAIL: \(message) - Expected \(expected), got \(actual)")
            failCount += 1
        }
    }
    
    private func assertTrue(_ condition: Bool, _ message: String) {
        if condition {
            print("    ✅ PASS: \(message)")
            passCount += 1
        } else {
            print("    ❌ FAIL: \(message)")
            failCount += 1
        }
    }
    
    private func assertFalse(_ condition: Bool, _ message: String) {
        assertTrue(!condition, message)
    }
    
    private func assertGreaterThan(_ actual: Int, _ expected: Int, _ message: String) {
        if actual > expected {
            print("    ✅ PASS: \(message)")
            passCount += 1
        } else {
            print("    ❌ FAIL: \(message) - Expected > \(expected), got \(actual)")
            failCount += 1
        }
    }
    
    private func assertGreaterThanOrEqual(_ actual: Int, _ expected: Int, _ message: String) {
        if actual >= expected {
            print("    ✅ PASS: \(message)")
            passCount += 1
        } else {
            print("    ❌ FAIL: \(message) - Expected >= \(expected), got \(actual)")
            failCount += 1
        }
    }
    
    // MARK: - Block Building Tests
    
    private func testSingleJokeBlock() async {
        print("\n  📋 Testing: Single Joke Block")
        
        let lines = createMockLines(texts: [
            "My Wife's Cooking",
            "",
            "My wife's cooking is so bad, even the smoke alarm cheers when she orders takeout.",
            "Last night she made dinner and the food poisoned itself!"
        ])
        
        let page = NormalizedPage(
            pageNumber: 1,
            lines: lines,
            hasRepeatingHeader: false,
            hasRepeatingFooter: false,
            averageLineHeight: 20.0,
            pageHeight: 400.0
        )
        
        let blocks = LayoutBlockBuilder.shared.buildBlocks(from: [page])
        
        assertEqual(blocks.count, 1, "Should create single block for single joke")
    }
    
    private func testMultipleJokesSeparatedByGaps() async {
        print("\n  📋 Testing: Multiple Jokes Separated By Gaps")
        
        let lines = createMockLines(texts: [
            "First joke about cats",
            "Why do cats make terrible comedians?",
            "Because they always land on their feet!",
            "", "", // Large gap
            "Second joke about dogs", 
            "My dog is a magician.",
            "He's a labracadabrador!"
        ])
        
        let page = NormalizedPage(
            pageNumber: 1,
            lines: lines,
            hasRepeatingHeader: false,
            hasRepeatingFooter: false,
            averageLineHeight: 20.0,
            pageHeight: 400.0
        )
        
        let blocks = LayoutBlockBuilder.shared.buildBlocks(from: [page])
        
        assertGreaterThanOrEqual(blocks.count, 2, "Should split jokes separated by large gaps")
    }
    
    private func testBulletedJokeList() async {
        print("\n  📋 Testing: Bulleted Joke List")
        
        let lines = createMockLines(texts: [
            "• Why don't scientists trust atoms? Because they make up everything!",
            "• I told my wife she was drawing her eyebrows too high. She looked surprised.",
            "• Parallel lines have so much in common. It's a shame they'll never meet."
        ])
        
        let page = NormalizedPage(
            pageNumber: 1,
            lines: lines,
            hasRepeatingHeader: false,
            hasRepeatingFooter: false,
            averageLineHeight: 20.0,
            pageHeight: 400.0
        )
        
        let blocks = LayoutBlockBuilder.shared.buildBlocks(from: [page])
        
        assertEqual(blocks.count, 3, "Should create separate blocks for each bulleted joke")
    }
    
    // MARK: - Validation Tests
    
    private func testSingleJokeValidation() {
        print("\n  📋 Testing: Single Joke Validation")
        
        let block = createMockBlock(text: "Why don't scientists trust atoms? Because they make up everything!")
        let validation = validator.validateBlock(block)
        
        switch validation.result {
        case .singleJoke:
            print("    ✅ PASS: Correctly identified as single joke")
            passCount += 1
        default:
            print("    ❌ FAIL: Should be identified as single joke")
            failCount += 1
        }
        
        assertTrue(validation.issues.isEmpty, "Should have no validation issues")
    }
    
    private func testMultipleJokeDetection() {
        print("\n  📋 Testing: Multiple Joke Detection")
        
        let multiJokeText = """
        Why don't scientists trust atoms? Because they make up everything!
        
        I told my wife she was drawing her eyebrows too high. She looked surprised.
        
        Parallel lines have so much in common. It's a shame they'll never meet.
        """
        
        let block = createMockBlock(text: multiJokeText)
        let validation = validator.validateBlock(block)
        
        switch validation.result {
        case .multipleJokes(let count, _):
            assertGreaterThan(count, 1, "Should detect multiple jokes")
        case .requiresReview:
            print("    ✅ PASS: Flagged for review (acceptable)")
            passCount += 1
        default:
            print("    ❌ FAIL: Should detect multiple jokes or flag for review")
            failCount += 1
        }
    }
    
    private func testLongJokeValidation() {
        print("\n  📋 Testing: Long Joke Validation")
        
        let longText = String(repeating: "This is a very long joke that goes on and on. ", count: 50)
        let block = createMockBlock(text: longText)
        let validation = validator.validateBlock(block)
        
        assertFalse(validation.shouldAutoSave, "Very long blocks should not auto-save")
    }
    
    // MARK: - Test Cases
    
    struct TestCase {
        let fileName: String
        let content: String
        let expectedJokeCount: Int
        let description: String
    }
    
    static let testCases = [
        TestCase(
            fileName: "single_joke.txt",
            content: """
            My Computer Skills
            
            I'm so bad with computers, I still press the elevator button twice to make it go faster.
            """,
            expectedJokeCount: 1,
            description: "Simple single joke with title"
        ),
        
        TestCase(
            fileName: "multiple_jokes_with_gaps.txt",
            content: """
            Why don't scientists trust atoms?
            Because they make up everything!
            
            
            I told my wife she was drawing her eyebrows too high.
            She looked surprised.
            
            
            Parallel lines have so much in common.
            It's a shame they'll never meet.
            """,
            expectedJokeCount: 3,
            description: "Three jokes separated by double line breaks"
        ),
        
        TestCase(
            fileName: "bulleted_list.txt",
            content: """
            • Why don't eggs tell jokes? They'd crack each other up!
            • I used to hate facial hair, but then it grew on me.
            • What's orange and sounds like a parrot? A carrot!
            """,
            expectedJokeCount: 3,
            description: "Bulleted joke list"
        )
    ]
    
    private func testAllTestCases() async {
        print("\n  📋 Testing: All Test Cases")
        
        for testCase in Self.testCases {
            print("    Testing: \(testCase.description)")
            
            let tempURL = createTempFile(content: testCase.content, name: testCase.fileName)
            
            do {
                let result = try await coordinator.processFile(url: tempURL)
                let totalJokes = result.autoSavedJokes.count + result.reviewQueueJokes.count
                
                let tolerance = max(1, testCase.expectedJokeCount / 2)
                let inRange = abs(totalJokes - testCase.expectedJokeCount) <= tolerance
                
                if inRange {
                    print("      ✅ Expected ~\(testCase.expectedJokeCount) jokes, got \(totalJokes)")
                    passCount += 1
                } else {
                    print("      ❌ Expected ~\(testCase.expectedJokeCount) jokes, got \(totalJokes)")
                    failCount += 1
                }
                
                try? FileManager.default.removeItem(at: tempURL)
                
            } catch {
                print("      ❌ Error: \(error)")
                failCount += 1
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createMockLines(texts: [String]) -> [ExtractedLine] {
        return texts.enumerated().map { index, text in
            ExtractedLine(
                rawText: text,
                normalizedText: text,
                pageNumber: 1,
                lineNumber: index + 1,
                boundingBox: CGRect(x: 0, y: CGFloat(index * 20), width: 400, height: 20),
                confidence: 1.0,
                estimatedFontSize: 12.0,
                indentationLevel: 0,
                yPosition: Float(index * 20),
                method: .documentText
            )
        }
    }
    
    private func createMockBlock(text: String) -> LayoutBlock {
        let lines = createMockLines(texts: text.components(separatedBy: "\n"))
        
        return LayoutBlock(
            lines: lines,
            blockType: .unknown,
            separatorBefore: nil,
            separatorAfter: nil,
            averageLineSpacing: 20.0,
            totalHeight: Float(lines.count * 20),
            indentationPattern: Array(repeating: 0, count: lines.count),
            containsTitle: false,
            pageNumber: 1,
            orderInPage: 0
        )
    }
    
    private func createTempFile(content: String, name: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(name)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to create temp file: \(error)")
        }
        
        return fileURL
    }
}

// MARK: - Metrics Collection

class ImportPipelineMetrics {
    
    struct ImportMetric {
        let fileName: String
        let processingTimeSeconds: Double
        let expectedJokeCount: Int
        let actualJokeCount: Int
        let autoSavedCount: Int
        let reviewQueueCount: Int
        let accuracy: Float
    }
    
    private var metrics: [ImportMetric] = []
    
    func addMetric(_ metric: ImportMetric) {
        metrics.append(metric)
    }
    
    func generateReport() -> String {
        guard !metrics.isEmpty else { return "No metrics collected" }
        
        let avgAccuracy = metrics.reduce(0.0) { sum, metric in sum + metric.accuracy } / Float(metrics.count)
        let avgProcessingTime = metrics.reduce(0.0) { sum, metric in sum + metric.processingTimeSeconds } / Double(metrics.count)
        
        let totalExpected = metrics.reduce(0) { sum, metric in sum + metric.expectedJokeCount }
        let totalActual = metrics.reduce(0) { sum, metric in sum + metric.actualJokeCount }
        
        return """
        Import Pipeline Performance Report
        =================================
        
        Total Test Cases: \(metrics.count)
        Average Accuracy: \(String(format: "%.2f", avgAccuracy * 100))%
        Average Processing Time: \(String(format: "%.2f", avgProcessingTime))s
        
        Total Expected Jokes: \(totalExpected)
        Total Actual Jokes: \(totalActual)
        Overall Accuracy: \(String(format: "%.2f", Float(totalActual) / Float(totalExpected) * 100))%
        
        Detailed Results:
        \(metrics.map(formatMetric).joined(separator: "\n"))
        """
    }
    
    private func formatMetric(_ metric: ImportMetric) -> String {
        return "  \(metric.fileName): \(metric.actualJokeCount)/\(metric.expectedJokeCount) jokes, \(String(format: "%.1f", metric.accuracy * 100))% accuracy"
    }
}