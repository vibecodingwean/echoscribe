import UIKit
import UniformTypeIdentifiers
import share_handler_ios_models

final class ShareViewController: UIViewController {
  private let appGroup = "group.de.wean.echoscribe"
  private let shareKey = "ShareKey"
  private let hostURL = URL(string: "ShareMedia-de.wean.echoscribe://de.wean.echoscribe?key=ShareKey")!

  override func viewDidLoad() {
    super.viewDidLoad()
    Task { @MainActor in
      do {
        let media = try await loadSharedMedia()
        try persist(media)
        openHostApp()
      } catch {
        showFailure(error)
      }
    }
  }

  private func loadSharedMedia() async throws -> SharedMedia {
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    var text: [String] = []
    var files: [SharedAttachment] = []
    for item in items {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
          let value = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
          guard let url = value as? URL else { throw ShareError.invalidAttachment }
          let copied = try copyFile(url, suggestedName: provider.suggestedName, type: UTType(filenameExtension: url.pathExtension))
          files.append(SharedAttachment(path: copied.path, type: .file))
        } else if let audioType = provider.registeredTypeIdentifiers.first(where: {
          UTType($0)?.conforms(to: .audio) == true
        }) {
          let copied = try await copyAudio(provider, typeIdentifier: audioType)
          files.append(SharedAttachment(path: copied.path, type: .audio))
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
          if let url = value as? URL {
            text.append(url.absoluteString)
          } else if let string = value as? String {
            text.append(string)
          } else {
            throw ShareError.invalidAttachment
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
          let value = try await provider.loadItem(forTypeIdentifier: UTType.text.identifier)
          if let string = value as? String {
            text.append(string)
          } else if let data = value as? Data, let string = String(data: data, encoding: .utf8) {
            text.append(string)
          } else {
            throw ShareError.invalidAttachment
          }
        }
      }
    }
    guard !text.isEmpty || !files.isEmpty else { throw ShareError.invalidAttachment }
    return SharedMedia(
      attachments: files,
      conversationIdentifier: nil,
      content: text.joined(separator: "\n"),
      speakableGroupName: nil,
      serviceName: nil,
      senderIdentifier: "echoscribe-share-\(UUID().uuidString)",
      imageFilePath: nil
    )
  }

  private func copyAudio(_ provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { temporaryURL, error in
        do {
          if let error { throw error }
          guard let temporaryURL else { throw ShareError.invalidAttachment }
          // The provider owns this temporary URL only until the callback returns.
          let copied = try self.copyFile(
            temporaryURL,
            suggestedName: provider.suggestedName,
            type: UTType(typeIdentifier)
          )
          continuation.resume(returning: copied)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func copyFile(_ source: URL, suggestedName: String?, type: UTType?) throws -> URL {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
      throw ShareError.missingAppGroup
    }
    let suggested = (suggestedName ?? source.lastPathComponent) as NSString
    var name = suggested.lastPathComponent
    if name.isEmpty { name = UUID().uuidString }
    if (name as NSString).pathExtension.isEmpty {
      let fileExtension = type?.preferredFilenameExtension ?? source.pathExtension
      if !fileExtension.isEmpty { name += ".\(fileExtension)" }
    }
    let imports = container.appendingPathComponent("ShareImports", isDirectory: true)
    try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    let destination = imports.appendingPathComponent("\(UUID().uuidString)_\(name)")
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    try FileManager.default.copyItem(at: source, to: destination)
    do {
      // Cleanup uses creationDate; do not inherit an old date from the source.
      try FileManager.default.setAttributes(
        [.creationDate: Date(), .modificationDate: Date()],
        ofItemAtPath: destination.path
      )
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    return destination
  }

  private func persist(_ media: SharedMedia) throws {
    guard let defaults = UserDefaults(suiteName: appGroup) else { throw ShareError.missingAppGroup }
    defaults.set(try JSONEncoder().encode(media), forKey: shareKey)
  }

  private func openHostApp() {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        if #available(iOS 18.0, *) {
          application.open(hostURL, options: [:]) { [weak self] opened in
            DispatchQueue.main.async {
              if opened {
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
              } else {
                self?.showFailure(ShareError.handoffFailed)
              }
            }
          }
        } else {
          _ = application.perform(NSSelectorFromString("openURL:"), with: hostURL)
          extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
        return
      }
      responder = current.next
    }
    showFailure(ShareError.handoffFailed)
  }

  private func showFailure(_ error: Error) {
    let alert = UIAlertController(
      title: "Could not share with EchoScribe",
      message: error.localizedDescription,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Close", style: .cancel) { [weak self] _ in
      self?.extensionContext?.cancelRequest(withError: error)
    })
    present(alert, animated: true)
  }
}

private enum ShareError: LocalizedError {
  case invalidAttachment
  case missingAppGroup
  case handoffFailed

  var errorDescription: String? {
    switch self {
    case .invalidAttachment: return "The shared content could not be read."
    case .missingAppGroup: return "Shared storage is unavailable."
    case .handoffFailed: return "EchoScribe could not be opened."
    }
  }
}
