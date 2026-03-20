//
//  PDFExportService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import UIKit
import PDFKit

class PDFExportService {
    
    static func exportJokesToPDF(jokes: [Joke], fileName: String = "BitBinder_Jokes") -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "The BitBinder",
            kCGPDFContextAuthor: "The BitBinder App",
            kCGPDFContextTitle: fileName
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11.0 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfURL = documentsURL.appendingPathComponent("\(fileName).pdf")
        
        do {
            try renderer.writePDF(to: pdfURL) { context in
                let margin: CGFloat = 72.0 // 1 inch margin
                let contentWidth = pageWidth - (2 * margin)
                var yPosition: CGFloat = margin
                
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 24),
                    .foregroundColor: UIColor.black
                ]
                
                let jokeNumberAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.black
                ]
                
                let jokeContentAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.black
                ]
                
                // Start first page
                context.beginPage()
                
                // Draw title
                let title = "The BitBinder - Jokes"
                let titleSize = title.size(withAttributes: titleAttributes)
                title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
                yPosition += titleSize.height + 30
                
                // Draw jokes
                for (index, joke) in jokes.enumerated() {
                    let jokeNumber = "\(index + 1). \(joke.title)"
                    let jokeNumberSize = jokeNumber.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: jokeNumberAttributes,
                        context: nil
                    ).size
                    
                    // Check if we need a new page
                    if yPosition + jokeNumberSize.height > pageHeight - margin {
                        context.beginPage()
                        yPosition = margin
                    }
                    
                    // Draw joke number/title
                    jokeNumber.draw(
                        in: CGRect(x: margin, y: yPosition, width: contentWidth, height: jokeNumberSize.height),
                        withAttributes: jokeNumberAttributes
                    )
                    yPosition += jokeNumberSize.height + 10
                    
                    // Draw joke content
                    let jokeContentSize = joke.content.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: jokeContentAttributes,
                        context: nil
                    ).size
                    
                    // Check if we need a new page for content
                    if yPosition + jokeContentSize.height > pageHeight - margin {
                        context.beginPage()
                        yPosition = margin
                    }
                    
                    joke.content.draw(
                        in: CGRect(x: margin, y: yPosition, width: contentWidth, height: jokeContentSize.height),
                        withAttributes: jokeContentAttributes
                    )
                    yPosition += jokeContentSize.height + 30
                }
            }
            
            return pdfURL
        } catch {
            print("Error creating PDF: \(error)")
            return nil
        }
    }
    
    // MARK: - Roast Export
    
    static func exportRoastsToPDF(targets: [RoastTarget], fileName: String = "BitBinder_Roasts") -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "The BitBinder",
            kCGPDFContextAuthor: "The BitBinder App",
            kCGPDFContextTitle: fileName
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11.0 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfURL = documentsURL.appendingPathComponent("\(fileName).pdf")
        
        do {
            try renderer.writePDF(to: pdfURL) { context in
                let margin: CGFloat = 72.0
                let contentWidth = pageWidth - (2 * margin)
                var yPosition: CGFloat = margin
                
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 24),
                    .foregroundColor: UIColor.black
                ]
                
                let targetNameAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1.0)
                ]
                
                let jokeNumberAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.darkGray
                ]
                
                let jokeContentAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.black
                ]
                
                let dividerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.lightGray
                ]
                
                // Start first page
                context.beginPage()
                
                // Draw title
                let title = "🔥 The BitBinder - Roasts"
                let titleSize = title.size(withAttributes: titleAttributes)
                title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
                yPosition += titleSize.height + 10
                
                // Subtitle with count
                let totalRoasts = targets.reduce(0) { $0 + $1.jokeCount }
                let subtitle = "\(targets.count) target\(targets.count == 1 ? "" : "s") · \(totalRoasts) roast\(totalRoasts == 1 ? "" : "s")"
                let subtitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.gray
                ]
                subtitle.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttrs)
                yPosition += 30
                
                // Draw each target and their roasts
                for target in targets {
                    let jokes = target.sortedJokes
                    guard !jokes.isEmpty else { continue }
                    
                    // Target name header
                    let targetHeader = "🎯 \(target.name)"
                    let targetHeaderSize = targetHeader.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: targetNameAttributes,
                        context: nil
                    ).size
                    
                    // Need space for header + at least one joke
                    if yPosition + targetHeaderSize.height + 60.0 > pageHeight - margin {
                        context.beginPage()
                        yPosition = margin
                    }
                    
                    // Draw target name
                    targetHeader.draw(
                        in: CGRect(x: margin, y: yPosition, width: contentWidth, height: targetHeaderSize.height),
                        withAttributes: targetNameAttributes
                    )
                    yPosition += targetHeaderSize.height + 5.0
                    
                    // Target notes if any
                    if !target.notes.isEmpty {
                        let notesAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.italicSystemFont(ofSize: 12),
                            .foregroundColor: UIColor.gray
                        ]
                        let notesSize = target.notes.boundingRect(
                            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: notesAttrs,
                            context: nil
                        ).size
                        target.notes.draw(
                            in: CGRect(x: margin, y: yPosition, width: contentWidth, height: notesSize.height),
                            withAttributes: notesAttrs
                        )
                        yPosition += notesSize.height + 5.0
                    }
                    
                    yPosition += 10.0
                    
                    // Draw jokes for this target
                    for (index, joke) in jokes.enumerated() {
                        let jokeLabel = "\(index + 1)."
                        let jokeLabelSize = jokeLabel.size(withAttributes: jokeNumberAttributes)
                        
                        let jokeContentSize = joke.content.boundingRect(
                            with: CGSize(width: contentWidth - 25.0, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: jokeContentAttributes,
                            context: nil
                        ).size
                        
                        let totalHeight = max(jokeLabelSize.height, jokeContentSize.height) + 20.0
                        
                        if yPosition + totalHeight > pageHeight - margin {
                            context.beginPage()
                            yPosition = margin
                        }
                        
                        // Draw joke number
                        jokeLabel.draw(
                            at: CGPoint(x: margin, y: yPosition),
                            withAttributes: jokeNumberAttributes
                        )
                        
                        // Draw joke content
                        joke.content.draw(
                            in: CGRect(x: margin + 25.0, y: yPosition, width: contentWidth - 25.0, height: jokeContentSize.height),
                            withAttributes: jokeContentAttributes
                        )
                        yPosition += max(jokeLabelSize.height, jokeContentSize.height) + 15.0
                    }
                    
                    // Divider between targets
                    let divider = String(repeating: "─", count: 40)
                    if yPosition + 30.0 > pageHeight - margin {
                        context.beginPage()
                        yPosition = margin
                    } else {
                        yPosition += 10.0
                        divider.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dividerAttributes)
                        yPosition += 25.0
                    }
                }
            }
            
            return pdfURL
        } catch {
            print("Error creating roast PDF: \(error)")
            return nil
        }
    }
    
    // MARK: - Brainstorm Export
    
    static func exportBrainstormToPDF(ideas: [BrainstormIdea], fileName: String = "BitBinder_Brainstorm") -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "The BitBinder",
            kCGPDFContextAuthor: "The BitBinder App",
            kCGPDFContextTitle: fileName
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11.0 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfURL = documentsURL.appendingPathComponent("\(fileName).pdf")
        
        do {
            try renderer.writePDF(to: pdfURL) { context in
                let margin: CGFloat = 72.0
                let contentWidth = pageWidth - (2 * margin)
                var yPosition: CGFloat = margin
                
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 24),
                    .foregroundColor: UIColor.black
                ]
                let subtitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.gray
                ]
                let contentAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.black
                ]
                let numberAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.darkGray
                ]
                
                context.beginPage()
                
                let title = "💡 The BitBinder - Brainstorm"
                let titleSize = title.size(withAttributes: titleAttrs)
                title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttrs)
                yPosition += titleSize.height + 8
                
                let subtitle = "\(ideas.count) idea\(ideas.count == 1 ? "" : "s")"
                subtitle.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttrs)
                yPosition += 30
                
                for (index, idea) in ideas.enumerated() {
                    let number = "\(index + 1)."
                    let numberSize = number.size(withAttributes: numberAttrs)
                    
                    let contentSize = idea.content.boundingRect(
                        with: CGSize(width: contentWidth - 30, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: contentAttrs,
                        context: nil
                    ).size
                    
                    let totalHeight = max(numberSize.height, contentSize.height) + 16
                    if yPosition + totalHeight > pageHeight - margin {
                        context.beginPage()
                        yPosition = margin
                    }
                    
                    number.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: numberAttrs)
                    idea.content.draw(
                        in: CGRect(x: margin + 30, y: yPosition, width: contentWidth - 30, height: contentSize.height),
                        withAttributes: contentAttrs
                    )
                    yPosition += totalHeight
                }
            }
            return pdfURL
        } catch {
            print("Error creating brainstorm PDF: \(error)")
            return nil
        }
    }
    
    // MARK: - Export Everything (Jokes + Brainstorm)
    
    static func exportEverythingToPDF(jokes: [Joke], ideas: [BrainstormIdea], fileName: String = "BitBinder_Export") -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "The BitBinder",
            kCGPDFContextAuthor: "The BitBinder App",
            kCGPDFContextTitle: fileName
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11.0 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfURL = documentsURL.appendingPathComponent("\(fileName).pdf")
        
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.black]
        let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray]
        let numberAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.darkGray]
        let contentAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black]
        let dividerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.lightGray]
        
        func drawText(_ text: String, attrs: [NSAttributedString.Key: Any], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
            let size = text.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs, context: nil
            ).size
            text.draw(in: CGRect(x: x, y: y, width: width, height: size.height), withAttributes: attrs)
            return size.height
        }
        
        do {
            try renderer.writePDF(to: pdfURL) { context in
                let margin: CGFloat = 72.0
                let contentWidth = pageWidth - (2 * margin)
                var y: CGFloat = margin
                
                context.beginPage()
                
                // Cover title
                let cover = "The BitBinder - Full Export"
                y += drawText(cover, attrs: titleAttrs, x: margin, y: y, width: contentWidth) + 8
                let date = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
                y += drawText(date, attrs: subtitleAttrs, x: margin, y: y, width: contentWidth) + 6
                let summary = "\(jokes.count) joke\(jokes.count == 1 ? "" : "s") · \(ideas.count) brainstorm idea\(ideas.count == 1 ? "" : "s")"
                y += drawText(summary, attrs: subtitleAttrs, x: margin, y: y, width: contentWidth) + 40
                
                // ── JOKES SECTION ──
                if !jokes.isEmpty {
                    if y + 40 > pageHeight - margin { context.beginPage(); y = margin }
                    y += drawText("✍️ Jokes", attrs: sectionAttrs, x: margin, y: y, width: contentWidth) + 20
                    
                    for (index, joke) in jokes.enumerated() {
                        let number = "\(index + 1)."
                        let numSize = number.size(withAttributes: numberAttrs)
                        let contentSize = joke.content.boundingRect(
                            with: CGSize(width: contentWidth - 30, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: contentAttrs, context: nil
                        ).size
                        let totalH = max(numSize.height, contentSize.height) + 16
                        if y + totalH > pageHeight - margin { context.beginPage(); y = margin }
                        number.draw(at: CGPoint(x: margin, y: y), withAttributes: numberAttrs)
                        joke.content.draw(
                            in: CGRect(x: margin + 30, y: y, width: contentWidth - 30, height: contentSize.height),
                            withAttributes: contentAttrs
                        )
                        y += totalH
                    }
                }
                
                // ── BRAINSTORM SECTION ──
                if !ideas.isEmpty {
                    // Always start brainstorm on a new page
                    context.beginPage(); y = margin
                    y += drawText("💡 Brainstorm Ideas", attrs: sectionAttrs, x: margin, y: y, width: contentWidth) + 20
                    
                    for (index, idea) in ideas.enumerated() {
                        let number = "\(index + 1)."
                        let numSize = number.size(withAttributes: numberAttrs)
                        let contentSize = idea.content.boundingRect(
                            with: CGSize(width: contentWidth - 30, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: contentAttrs, context: nil
                        ).size
                        let totalH = max(numSize.height, contentSize.height) + 16
                        if y + totalH > pageHeight - margin { context.beginPage(); y = margin }
                        number.draw(at: CGPoint(x: margin, y: y), withAttributes: numberAttrs)
                        idea.content.draw(
                            in: CGRect(x: margin + 30, y: y, width: contentWidth - 30, height: contentSize.height),
                            withAttributes: contentAttrs
                        )
                        y += totalH
                    }
                }
                
                // Ignore unused variable warnings
                _ = dividerAttrs
            }
            return pdfURL
        } catch {
            print("Error creating full export PDF: \(error)")
            return nil
        }
    }
}
