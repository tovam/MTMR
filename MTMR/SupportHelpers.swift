//
//  SupportHelpers.swift
//  MTMR
//
//  Created by Anton Palgunov on 13/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import AppKit
import Foundation

extension String {
    func trim() -> String {
        return trimmingCharacters(in: NSCharacterSet.whitespaces)
    }

    func stripComments() -> String {
        // ((\s|,)\/\*[\s\S]*?\*\/)|(( |, ")\/\/.*)
        return replacingOccurrences(of: "((\\s|,)\\/\\*[\\s\\S]*?\\*\\/)|(( |, \\\")\\/\\/.*)", with: "", options: .regularExpression)
    }

    var hexColor: NSColor? {
        let hex = trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt32()
        Scanner(string: hex).scanHexInt32(&int)
        let a, r, g, b: UInt32
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        return NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

extension NSImage {
    func resize(maxSize: NSSize) -> NSImage? {
        guard size.width.isFinite,
              size.height.isFinite,
              maxSize.width.isFinite,
              maxSize.height.isFinite,
              size.width > 0,
              size.height > 0,
              maxSize.width > 0,
              maxSize.height > 0
        else {
            return nil
        }

        let ratio = min(maxSize.width / size.width, maxSize.height / size.height)
        guard ratio.isFinite, ratio > 0 else {
            return nil
        }

        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        guard newSize.width.isFinite,
              newSize.height.isFinite,
              newSize.width > 0,
              newSize.height > 0
        else {
            return nil
        }

        var imageRect = NSRect(origin: .zero, size: size)
        guard let imageRef = cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else {
            return nil
        }

        return NSImage(cgImage: imageRef, size: newSize)
    }

    func rotateByDegreess(degrees: CGFloat) -> NSImage {
        var imageBounds = NSZeroRect; imageBounds.size = size
        let pathBounds = NSBezierPath(rect: imageBounds)
        var transform = NSAffineTransform()
        transform.rotate(byDegrees: degrees)
        pathBounds.transform(using: transform as AffineTransform)
        let rotatedBounds: NSRect = NSMakeRect(NSZeroPoint.x, NSZeroPoint.y, size.width, size.height)
        let rotatedImage = NSImage(size: rotatedBounds.size)

        // Center the image within the rotated bounds
        imageBounds.origin.x = NSMidX(rotatedBounds) - (NSWidth(imageBounds) / 2)
        imageBounds.origin.y = NSMidY(rotatedBounds) - (NSHeight(imageBounds) / 2)

        // Start a new transform
        transform = NSAffineTransform()
        // Move coordinate system to the center (since we want to rotate around the center)
        transform.translateX(by: +(NSWidth(rotatedBounds) / 2), yBy: +(NSHeight(rotatedBounds) / 2))
        transform.rotate(byDegrees: degrees)
        // Move the coordinate system bak to normal
        transform.translateX(by: -(NSWidth(rotatedBounds) / 2), yBy: -(NSHeight(rotatedBounds) / 2))
        // Draw the original image, rotated, into the new image
        rotatedImage.lockFocus()
        transform.concat()
        draw(in: imageBounds, from: NSZeroRect, operation: NSCompositingOperation.copy, fraction: 1.0)
        rotatedImage.unlockFocus()

        return rotatedImage
    }
}

extension NSAppleEventDescriptor {
    var listStringValues: [String] {
        let itemCount = numberOfItems
        guard itemCount > 0 else {
            return []
        }

        return (1...itemCount).map { atIndex($0)?.stringValue ?? "" }
    }
}
