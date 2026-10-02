import Foundation

/// Builds a terminal environment from an allowlist, so agents never inherit the app's secrets.
public enum AgentEnvironment {
    /// Variables every terminal keeps. A trailing `*` matches a prefix.
    public static let common = [
        "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "TZ", "LANG", "LC_*", "SSH_AUTH_SOCK",
        "__CF_USER_TEXT_ENCODING", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
        "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "no_proxy",
        "all_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS",
    ]

    public static func filtered(_ environment: [String: String], allowing extra: [String]) -> [String: String] {
        let patterns = common + extra
        return environment.filter { key, _ in patterns.contains { matches(key, $0) } }
    }

    static func matches(_ key: String, _ pattern: String) -> Bool {
        pattern.hasSuffix("*") ? key.hasPrefix(pattern.dropLast()) : key == pattern
    }
}
