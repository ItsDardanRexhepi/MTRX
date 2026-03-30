// PDFManager.swift
// MTRX Apple Integration — Computation
//
// PDFKit + QuickLook for contract document viewing and generation

import PDFKit
import QuickLook
import Foundation

// MARK: - PDFManager

final class PDFManager: ObservableObject {

    static let shared = PDFManager()

    @Published private(set) var isGenerating: Bool = false

    // MARK: - Document Loading

    func loadDocument(from url: URL) -> PDFDocument? {
        PDFDocument(url: url)
    }

    func loadDocument(from data: Data) -> PDFDocument? {
        PDFDocument(data: data)
    }

    // MARK: - Text Extraction

    func extractText(from document: PDFDocument) -> String {
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        return text
    }

    func extractTextFromPage(_ document: PDFDocument, pageIndex: Int) -> String? {
        document.page(at: pageIndex)?.string
    }

    // MARK: - Contract PDF Generation

    func generateContractPDF(title: String, parties: [String], terms: [String], date: Date) -> Data? {
        isGenerating = true
        defer { isGenerating = false }

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()

            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let titleRect = CGRect(x: 50, y: 50, width: 512, height: 40)
            title.draw(in: titleRect, withAttributes: titleAttributes)

            // Date
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            let dateString = "Date: \(formatter.string(from: date))"
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
            dateString.draw(at: CGPoint(x: 50, y: 100), withAttributes: dateAttributes)

            // Parties
            var yPos: CGFloat = 140
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.black
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]

            "Parties".draw(at: CGPoint(x: 50, y: yPos), withAttributes: sectionAttributes)
            yPos += 25
            for party in parties {
                party.draw(at: CGPoint(x: 70, y: yPos), withAttributes: bodyAttributes)
                yPos += 20
            }

            // Terms
            yPos += 20
            "Terms and Conditions".draw(at: CGPoint(x: 50, y: yPos), withAttributes: sectionAttributes)
            yPos += 25
            for (index, term) in terms.enumerated() {
                let termText = "\(index + 1). \(term)"
                let termRect = CGRect(x: 70, y: yPos, width: 472, height: 60)
                termText.draw(in: termRect, withAttributes: bodyAttributes)
                yPos += 70

                if yPos > 700 {
                    context.beginPage()
                    yPos = 50
                }
            }
        }
    }

    // MARK: - Search

    func searchText(in document: PDFDocument, query: String) -> [PDFSelection] {
        document.findString(query, withOptions: .caseInsensitive)
    }

    // MARK: - Page Operations

    func pageCount(of document: PDFDocument) -> Int {
        document.pageCount
    }

    func getPageImage(document: PDFDocument, pageIndex: Int, size: CGSize) -> UIImage? {
        guard let page = document.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: size.width / bounds.width, y: -size.height / bounds.height)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    // MARK: - Annotations

    func addAnnotation(to document: PDFDocument, pageIndex: Int, text: String, bounds: CGRect) {
        guard let page = document.page(at: pageIndex) else { return }
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = UIFont.systemFont(ofSize: 12)
        annotation.color = .yellow.withAlphaComponent(0.3)
        page.addAnnotation(annotation)
    }
}
