import Foundation
import SwiftData
import UIKit

/// Downloads a website's icon to use as a logo. Free, no account needed.
/// Every logo is saved on the phone, so each website is only downloaded once.
enum LogoFetcher {
    /// Returns PNG data for the site's icon, or nil if there isn't a usable one.
    /// `force` skips the "recently failed" check, for when you tap Fetch yourself.
    static func fetch(domain: String, force: Bool = false) async -> Data? {
        let host = normalize(domain)
        guard !host.isEmpty else { return nil }
        if let cached = LogoCache.data(for: host) { return cached }
        if !force && LogoCache.recentlyMissed(host) { return nil }

        let sources = [
            "https://www.google.com/s2/favicons?domain=\(host)&sz=256",
            "https://icons.duckduckgo.com/ip3/\(host).ico"
        ]
        for source in sources {
            guard let url = URL(string: source) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = UIImage(data: data),
                      image.size.width * image.scale >= 32,
                      let png = image.fitted(in: 256).pngData() else { continue }
                LogoCache.store(png, for: host)
                return png
            } catch {
                continue
            }
        }
        LogoCache.markMissed(host)
        return nil
    }

    /// Finds a logo from an item's name, e.g. "iCloud+ 200GB" → icloud.com.
    static func fetch(forName name: String) async -> (domain: String, data: Data)? {
        for domain in guessDomains(for: name) {
            if let data = await fetch(domain: domain) {
                return (domain, data)
            }
        }
        return nil
    }

    /// Likely websites for a subscription name: a known brand first, then name.com and name.lk.
    static func guessDomains(for name: String) -> [String] {
        let lower = name.lowercased()
        var domains: [String] = []
        for key in knownDomains.keys.sorted(by: { $0.count > $1.count }) where lower.contains(key) {
            if let domain = knownDomains[key] { domains.append(domain) }
            break
        }
        let slug = lower.filter { $0.isLetter || $0.isNumber }
        if slug.count >= 3 {
            for candidate in [slug + ".com", slug + ".lk"] where !domains.contains(candidate) {
                domains.append(candidate)
            }
        }
        return domains
    }

    /// Names that don't simply map to name.com.
    private static let knownDomains: [String: String] = [
        "netflix": "netflix.com",
        "spotify": "spotify.com",
        "icloud": "icloud.com",
        "apple music": "apple.com",
        "apple tv": "apple.com",
        "apple one": "apple.com",
        "apple arcade": "apple.com",
        "youtube": "youtube.com",
        "google one": "one.google.com",
        "google": "google.com",
        "claude": "claude.ai",
        "anthropic": "anthropic.com",
        "chatgpt": "openai.com",
        "openai": "openai.com",
        "perplexity": "perplexity.ai",
        "midjourney": "midjourney.com",
        "cursor": "cursor.com",
        "github": "github.com",
        "adobe": "adobe.com",
        "creative cloud": "adobe.com",
        "lightroom": "adobe.com",
        "photoshop": "adobe.com",
        "premiere": "adobe.com",
        "after effects": "adobe.com",
        "canva": "canva.com",
        "figma": "figma.com",
        "notion": "notion.so",
        "capcut": "capcut.com",
        "envato": "envato.com",
        "motion array": "motionarray.com",
        "artlist": "artlist.io",
        "epidemic sound": "epidemicsound.com",
        "microsoft": "microsoft.com",
        "office 365": "microsoft.com",
        "xbox": "xbox.com",
        "playstation": "playstation.com",
        "amazon prime": "primevideo.com",
        "prime video": "primevideo.com",
        "disney": "disneyplus.com",
        "hbo": "max.com",
        "dropbox": "dropbox.com",
        "duolingo": "duolingo.com",
        "linkedin": "linkedin.com",
        "grammarly": "grammarly.com",
        "x premium": "x.com",
        "twitter": "x.com",
        "telegram": "telegram.org",
        "discord": "discord.com",
        "steam": "steampowered.com",
        "patreon": "patreon.com",
        "medium": "medium.com",
        "audible": "audible.com",
        "dialog": "dialog.lk",
        "mobitel": "mobitel.lk",
        "hutch": "hutch.lk",
        "peo tv": "slt.lk",
        "slt": "slt.lk",
        "pickme": "pickme.lk",
        "uber": "uber.com"
    ]

    /// "https://www.Netflix.com/lk" → "netflix.com"
    static func normalize(_ input: String) -> String {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        return host
    }
}

/// Logos saved on the phone, one PNG per website.
enum LogoCache {
    private static let missesKey = "logoMisses"

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func fileURL(for host: String) -> URL {
        folder.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    static func data(for host: String) -> Data? {
        try? Data(contentsOf: fileURL(for: host))
    }

    static func store(_ data: Data, for host: String) {
        try? data.write(to: fileURL(for: host), options: .atomic)
        var misses = UserDefaults.standard.dictionary(forKey: missesKey) as? [String: Date] ?? [:]
        misses[host] = nil
        UserDefaults.standard.set(misses, forKey: missesKey)
    }

    /// Sites that had no usable logo are not retried automatically for 3 days.
    static func recentlyMissed(_ host: String) -> Bool {
        let misses = UserDefaults.standard.dictionary(forKey: missesKey) as? [String: Date] ?? [:]
        guard let date = misses[host] else { return false }
        return Date().timeIntervalSince(date) < 3 * 86_400
    }

    static func markMissed(_ host: String) {
        var misses = UserDefaults.standard.dictionary(forKey: missesKey) as? [String: Date] ?? [:]
        misses[host] = Date()
        UserDefaults.standard.set(misses, forKey: missesKey)
    }
}

/// Fills in logos that haven't been downloaded yet. Runs at launch and after adding items.
enum LogoSync {
    @MainActor
    static func fillMissing(in context: ModelContext) async {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for account in accounts where account.logoData == nil {
            guard let domain = account.logoDomain, !domain.isEmpty else { continue }
            if let data = await LogoFetcher.fetch(domain: domain) {
                account.logoData = data
            }
        }

        let subscriptions = (try? context.fetch(FetchDescriptor<SubscriptionPlan>())) ?? []
        for subscription in subscriptions where subscription.logoData == nil {
            if let domain = subscription.logoDomain, !domain.isEmpty {
                subscription.logoData = await LogoFetcher.fetch(domain: domain)
            } else if let found = await LogoFetcher.fetch(forName: subscription.name) {
                subscription.logoData = found.data
                subscription.logoDomain = found.domain
            }
        }

        // Koko and Mintpay logos are downloaded once and reused for every plan.
        for provider in InstallmentProvider.allCases where provider.bundledLogo == nil {
            if let domain = provider.domain {
                _ = await LogoFetcher.fetch(domain: domain)
            }
        }

        let plans = (try? context.fetch(FetchDescriptor<InstallmentPlan>())) ?? []
        for plan in plans {
            // Bundled logos (Koko) replace whatever was there; others only fill gaps.
            if let bundled = plan.provider.bundledLogo {
                if plan.logoData != bundled { plan.logoData = bundled }
            } else if plan.logoData == nil {
                plan.logoData = plan.provider.cachedLogo
            }
        }

        try? context.save()
    }
}

extension UIImage {
    /// Scales the image down so its longest side is at most `side` points.
    func fitted(in side: CGFloat) -> UIImage {
        let scale = min(1, side / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
