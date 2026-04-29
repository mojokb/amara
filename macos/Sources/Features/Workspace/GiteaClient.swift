import Foundation

// MARK: - Credentials (UserDefaults)

struct GiteaCredentials {
    private static let serverKey = "amara.gitea.serverURL"
    private static let tokenKey  = "amara.gitea.token"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: serverKey) }
    }
    static var token: String {
        get { UserDefaults.standard.string(forKey: tokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }
    static var isConfigured: Bool { !serverURL.isEmpty && !token.isEmpty }
}

// MARK: - Gitea API model

private struct GiteaPR: Decodable {
    let number: Int
    let title: String
    let state: String
    let merged: Bool
    let draft: Bool
    let htmlURL: String
    let head: Ref

    struct Ref: Decodable { let ref: String }

    enum CodingKeys: String, CodingKey {
        case number, title, state, merged, draft, head
        case htmlURL = "html_url"
    }

    var prState: PRState {
        if merged           { return .merged }
        if state == "closed"{ return .closed }
        if draft            { return .draft }
        return .open
    }

    var prInfo: PRInfo {
        PRInfo(number: number, title: title,
               state: prState, webURL: htmlURL,
               headBranch: head.ref)
    }
}

// MARK: - Client

actor GiteaClient {
    let baseURL: URL
    private let token: String

    init(serverURL: URL, token: String) {
        self.baseURL = serverURL
        self.token = token
    }

    static func fromCredentials() -> GiteaClient? {
        let s = GiteaCredentials.serverURL
        let t = GiteaCredentials.token
        guard !s.isEmpty, !t.isEmpty, let url = URL(string: s) else { return nil }
        return GiteaClient(serverURL: url, token: t)
    }

    func openPRs(owner: String, repo: String) async throws -> [PRInfo] {
        try await fetchPRs(owner: owner, repo: repo, state: "open")
    }

    func closedPRs(owner: String, repo: String) async throws -> [PRInfo] {
        try await fetchPRs(owner: owner, repo: repo, state: "closed")
    }

    private func fetchPRs(owner: String, repo: String, state: String) async throws -> [PRInfo] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/repos/\(owner)/\(repo)/pulls"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "limit", value: "50"),
        ]
        let prs = try await fetch([GiteaPR].self, from: comps.url!)
        return prs.map(\.prInfo)
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Remote URL helpers

extension GiteaClient {
    /// Run `git remote get-url origin` synchronously (call from a background context).
    nonisolated static func remoteURL(repoPath: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repoPath, "remote", "get-url", "origin"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse (owner, repo) from HTTPS or SSH remote URL.
    static func parseRemote(_ raw: String) -> (owner: String, repo: String)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // HTTPS: https://host/owner/repo.git
        if let u = URL(string: s), u.scheme == "https" || u.scheme == "http" {
            let parts = u.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 {
                return (parts[0], parts[1].replacingOccurrences(of: ".git", with: ""))
            }
        }
        // SSH: git@host:owner/repo.git
        if s.contains(":"), !s.hasPrefix("http") {
            let sides = s.components(separatedBy: ":")
            if sides.count == 2 {
                let parts = sides[1].components(separatedBy: "/")
                if parts.count >= 2 {
                    return (parts[0], parts[1].replacingOccurrences(of: ".git", with: ""))
                }
            }
        }
        return nil
    }
}
