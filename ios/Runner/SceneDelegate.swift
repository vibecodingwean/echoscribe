import Flutter
import UIKit
import share_handler_ios

class SceneDelegate: FlutterSceneDelegate {
  private let shareScheme = "ShareMedia-de.wean.echoscribe"

  private func isShareScheme(_ url: URL) -> Bool {
    url.scheme?.caseInsensitiveCompare(shareScheme) == .orderedSame
  }

  private func isValidShareURL(_ url: URL) -> Bool {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return false
    }
    return parts.scheme == shareScheme &&
      parts.host == "de.wean.echoscribe" &&
      parts.path.isEmpty &&
      parts.fragment == nil &&
      url.query == "key=ShareKey" &&
      parts.queryItems?.count == 1 &&
      parts.queryItems?.first?.name == "key" &&
      parts.queryItems?.first?.value == "ShareKey"
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Flutter forwards cold-start URL contexts to legacy plugins. The local
    // share-handler package validates the scheme before it parses the query.
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    removeExpiredShareImports()
    if let url = connectionOptions.urlContexts.first?.url, isValidShareURL(url) {
      _ = SwiftShareHandlerIosPlatform.instance.application(
        UIApplication.shared,
        didFinishLaunchingWithOptions: [UIApplication.LaunchOptionsKey.url: url]
      )
    }
  }

  private func removeExpiredShareImports() {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.de.wean.echoscribe"
    ) else { return }
    let directory = container.appendingPathComponent("ShareImports", isDirectory: true)
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.creationDateKey],
      options: [.skipsHiddenFiles]
    ) else { return }
    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
    for file in files {
      guard let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
            created < cutoff else { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let otherContexts = Set(URLContexts.filter { !isShareScheme($0.url) })
    if !otherContexts.isEmpty {
      super.scene(scene, openURLContexts: otherContexts)
    }
    for context in URLContexts {
      guard isValidShareURL(context.url) else { continue }
      _ = SwiftShareHandlerIosPlatform.instance.application(
        UIApplication.shared,
        open: context.url,
        options: [:]
      )
    }
  }
}
