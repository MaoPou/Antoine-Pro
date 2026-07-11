//
//  UIKitExtensions.swift
//  Antoine
//
//  Created by Serena on 18/01/2023.
//

import UIKit

extension UILabel {
    convenience init(text: String) {
        self.init()
        self.text = text
    }
    
    convenience init(text: String, font: UIFont?, textColor: UIColor?) {
        self.init(text: text)
        self.textColor = textColor
        self.font = font
    }
}

// Support for closure-based addAction / addTarget functions
// for iOS 13
extension UIControl {
    func addAction(for event: UIControl.Event, _ closure: @escaping () -> Void) {
        if #available(iOS 14.0, *) {
            let uiAction = UIAction { _ in closure() }
            addAction(uiAction, for: event)
            return
        }
        
        @objc class ClosureSleeve: NSObject {
            let closure: () -> Void
            init(_ closure: @escaping () -> Void) { self.closure = closure }
            @objc func invoke() { closure() }
        }
        
        let sleeve = ClosureSleeve(closure)
        addTarget(sleeve, action: #selector(ClosureSleeve.invoke), for: event)
        objc_setAssociatedObject(self, UUID().uuidString, sleeve, .OBJC_ASSOCIATION_RETAIN)
    }
}

extension UIViewController {
    func errorAlert(
        title: String,
        description: String?,
        actions: [UIAlertAction] = [UIAlertAction(title: "OK", style: .cancel)]) {
        let alert = UIAlertController(title: title, message: description, preferredStyle: .alert)
        for action in actions {
            alert.addAction(action)
        }
        present(alert, animated: true)
    }
    
    func export(entry: Entry, senderView: UIView, senderRect: CGRect) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            let serialized = try encoder.encode(CodableEntry(streamEntry: entry))
            let docsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Antoine Logs")
            try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true) /* if dir doesn't already exist */
            let fileURL = docsURL
                .appendingPathComponent(
                    "\(entry.process) (\(DateFormatter(dateFormat: "MMM d h:mm a").string(from: entry.timestamp)))"
                )
                .appendingPathExtension("antoinelog")
            
            if FileManager.default.createFile(atPath: fileURL.path, contents: serialized) {
                let vc = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                
                vc.popoverPresentationController?.sourceView = senderView
                vc.popoverPresentationController?.sourceRect = /*sender.frame*/senderRect
                present(vc, animated: true)
            } else {
                errorAlert(title: .localized("Failed to create log file"), description: nil)
            }
        } catch {
            errorAlert(title: .localized("Error creating log file"), description: error.localizedDescription)
        }
    }

    func export(entries: [any Entry], senderView: UIView, senderRect: CGRect) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let date = DateFormatter(dateFormat: "yyyy-MM-dd_HH-mm-ss").string(from: Date())
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Antoine-Logs-\(date)")
                .appendingPathExtension("zip")
            var archive = SimpleZipArchive()

            for (index, entry) in entries.enumerated() {
                let data = try encoder.encode(CodableEntry(streamEntry: entry))
                let process = entry.process.replacingOccurrences(
                    of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
                archive.add(data: data, named: String(format: "%06d-%@.antoinelog", index + 1, process))
            }

            try archive.finalizedData().write(to: fileURL, options: .atomic)
            let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activityController.popoverPresentationController?.sourceView = senderView
            activityController.popoverPresentationController?.sourceRect = senderRect
            present(activityController, animated: true)
        } catch {
            errorAlert(title: .localized("Error creating log archive"), description: error.localizedDescription)
        }
    }
}

/// A small ZIP writer using the uncompressed ZIP format, avoiding an extra dependency.
private struct SimpleZipArchive {
    private struct FileRecord {
        let name: Data
        let crc32: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private(set) var data = Data()
    private var records: [FileRecord] = []

    mutating func add(data fileData: Data, named name: String) {
        let nameData = Data(name.utf8)
        let record = FileRecord(name: nameData, crc32: fileData.crc32,
                                size: UInt32(fileData.count), offset: UInt32(data.count))
        data.appendLittleEndian(UInt32(0x04034b50))
        data.appendLittleEndian(UInt16(20)); data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0)); data.appendLittleEndian(UInt16(0)); data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(record.crc32); data.appendLittleEndian(record.size); data.appendLittleEndian(record.size)
        data.appendLittleEndian(UInt16(nameData.count)); data.appendLittleEndian(UInt16(0))
        data.append(nameData); data.append(fileData)
        records.append(record)
    }

    func finalizedData() -> Data {
        var result = data
        let directoryOffset = result.count
        var directory = Data()
        for record in records {
            directory.appendLittleEndian(UInt32(0x02014b50))
            directory.appendLittleEndian(UInt16(20)); directory.appendLittleEndian(UInt16(20))
            directory.appendLittleEndian(UInt16(0)); directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0)); directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(record.crc32); directory.appendLittleEndian(record.size); directory.appendLittleEndian(record.size)
            directory.appendLittleEndian(UInt16(record.name.count)); directory.appendLittleEndian(UInt16(0)); directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0)); directory.appendLittleEndian(UInt16(0)); directory.appendLittleEndian(UInt32(0))
            directory.appendLittleEndian(record.offset); directory.append(record.name)
        }
        result.append(directory)
        result.appendLittleEndian(UInt32(0x06054b50)); result.appendLittleEndian(UInt16(0)); result.appendLittleEndian(UInt16(0))
        result.appendLittleEndian(UInt16(records.count)); result.appendLittleEndian(UInt16(records.count))
        result.appendLittleEndian(UInt32(directory.count)); result.appendLittleEndian(UInt32(directoryOffset))
        result.appendLittleEndian(UInt16(0))
        return result
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    var crc32: UInt32 {
        var crc = UInt32.max
        for byte in self {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB88320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}

extension NSDiffableDataSourceSnapshot {
    mutating func reloadItems(inSection section: SectionIdentifierType, rebuildWith newItems: [ItemIdentifierType]) {
        deleteItems(itemIdentifiers(inSection: section))
        appendItems(newItems, toSection: section)
    }
}

extension UITableViewCell {
    func addChoiceButton(
        text: String,
        image: UIImage?,
        buttonHandler: (UIButton) -> Void) {
        let button: UIButton
        let buttonTrailingAnchor: NSLayoutXAxisAnchor
        
        if #available(iOS 15.0, *) {
            var conf: UIButton.Configuration = .plain()
            conf.image = image
            conf.title = text
            conf.imagePadding = 5
            
            button = UIButton(configuration: conf)
            
            buttonTrailingAnchor = contentView.trailingAnchor
        } else {
            button = UIButton(type: .system)
            button.setTitle(text, for: .normal)
            button.setImage(image, for: .normal)
            button.imageEdgeInsets.left = -10
            
            buttonTrailingAnchor = contentView
                .layoutMarginsGuide
                .trailingAnchor
        }
        
        button.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(button)
        
        buttonHandler(button)
        
        // on iOS 15, when using button configurations, it's somehow automatically aligned to the inner side
        // without using a margins guide
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: buttonTrailingAnchor),
            button.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor)
        ])
    }
}

extension UIBarButtonItem {
    static func space(_ type: Space) -> UIBarButtonItem {
        switch type {
        case .flexible:
            return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        case .fixed(let width):
            let item = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
            item.width = width
            return item
        }
    }
    
    enum Space: Hashable {
        case flexible
        case fixed(CGFloat)
    }
}
