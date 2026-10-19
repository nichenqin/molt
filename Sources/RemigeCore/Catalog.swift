import Foundation

public enum LatestTagSource: Hashable, Sendable {
    /// Resolve `github.com/<repo>/releases/latest`; no API token or rate limit.
    case github(RepoRef)
    /// Fetch a small text document and extract the tag with a regex.
    case text(URL, regex: String)
}

/// Curated catalog for tools commonly installed by `curl | sh`, installers or
/// tarballs. Homebrew/npm-owned binaries are skipped at runtime so this never
/// duplicates a managed package.
public struct CLITool: Hashable, Sendable, Identifiable {
    public var name: String
    public var displayName: String
    public var binaryNames: [String]
    public var versionArguments: [String]
    public var versionRegex: String?
    public var latest: LatestTagSource
    public var upgradeArguments: [String]?
    public var homepage: URL?
    public var summary: String?

    public var id: String { name }

    public init(
        name: String,
        displayName: String? = nil,
        binaryNames: [String] = [],
        latest: LatestTagSource,
        versionArguments: [String] = ["--version"],
        versionRegex: String? = nil,
        upgradeArguments: [String]? = nil,
        homepage: URL? = nil,
        summary: String? = nil
    ) {
        self.name = name
        self.displayName = displayName ?? name
        self.binaryNames = binaryNames.isEmpty ? [name] : binaryNames
        self.latest = latest
        self.versionArguments = versionArguments
        self.versionRegex = versionRegex
        self.upgradeArguments = upgradeArguments
        self.homepage = homepage
        self.summary = summary
    }
}

public enum ToolCatalog {
    public static let tools: [CLITool] = [
        CLITool(
            name: "uv",
            latest: .github(RepoRef(owner: "astral-sh", name: "uv")),
            upgradeArguments: ["uv", "self", "update"],
            homepage: URL(string: "https://docs.astral.sh/uv/"),
            summary: "Python package and project manager"
        ),
        CLITool(
            name: "claude",
            displayName: "Claude Code",
            latest: .github(RepoRef(owner: "anthropics", name: "claude-code")),
            upgradeArguments: ["claude", "update"],
            homepage: URL(string: "https://claude.com/product/claude-code"),
            summary: "Anthropic's coding agent"
        ),
        CLITool(
            name: "rustup",
            latest: .github(RepoRef(owner: "rust-lang", name: "rustup")),
            versionArguments: ["--version"],
            versionRegex: #"rustup\s+(\d+(?:\.\d+)+)"#,
            upgradeArguments: ["rustup", "update"],
            homepage: URL(string: "https://rustup.rs"),
            summary: "Rust toolchain installer"
        ),
        CLITool(
            name: "bun",
            latest: .github(RepoRef(owner: "oven-sh", name: "bun")),
            versionArguments: ["--version"],
            upgradeArguments: ["bun", "upgrade"],
            homepage: URL(string: "https://bun.sh"),
            summary: "JavaScript runtime and toolkit"
        ),
        CLITool(
            name: "deno",
            latest: .github(RepoRef(owner: "denoland", name: "deno")),
            versionArguments: ["--version"],
            versionRegex: #"deno\s+(\d+(?:\.\d+)+)"#,
            upgradeArguments: ["deno", "upgrade"],
            homepage: URL(string: "https://deno.com"),
            summary: "JavaScript and TypeScript runtime"
        ),
        CLITool(
            name: "mise",
            latest: .github(RepoRef(owner: "jdx", name: "mise")),
            versionArguments: ["--version"],
            upgradeArguments: ["mise", "self-update"],
            homepage: URL(string: "https://mise.jdx.dev"),
            summary: "Dev tools, env vars and task runner"
        ),
        CLITool(
            name: "starship",
            latest: .github(RepoRef(owner: "starship", name: "starship")),
            versionArguments: ["--version"],
            versionRegex: #"starship\s+(\d+(?:\.\d+)+)"#,
            homepage: URL(string: "https://starship.rs"),
            summary: "Cross-shell prompt"
        ),
        CLITool(
            name: "rg",
            displayName: "ripgrep",
            latest: .github(RepoRef(owner: "BurntSushi", name: "ripgrep")),
            homepage: URL(string: "https://github.com/BurntSushi/ripgrep"),
            summary: "Recursive search"
        ),
        CLITool(
            name: "fd",
            latest: .github(RepoRef(owner: "sharkdp", name: "fd")),
            homepage: URL(string: "https://github.com/sharkdp/fd"),
            summary: "Fast find alternative"
        ),
        CLITool(
            name: "bat",
            latest: .github(RepoRef(owner: "sharkdp", name: "bat")),
            homepage: URL(string: "https://github.com/sharkdp/bat"),
            summary: "Cat with syntax highlighting"
        ),
        CLITool(
            name: "eza",
            latest: .github(RepoRef(owner: "eza-community", name: "eza")),
            homepage: URL(string: "https://eza.rocks"),
            summary: "Modern ls replacement"
        ),
        CLITool(
            name: "fzf",
            latest: .github(RepoRef(owner: "junegunn", name: "fzf")),
            homepage: URL(string: "https://github.com/junegunn/fzf"),
            summary: "Command-line fuzzy finder"
        ),
        CLITool(
            name: "jq",
            latest: .github(RepoRef(owner: "jqlang", name: "jq")),
            homepage: URL(string: "https://jqlang.github.io/jq/"),
            summary: "JSON processor"
        ),
        CLITool(
            name: "yq",
            latest: .github(RepoRef(owner: "mikefarah", name: "yq")),
            homepage: URL(string: "https://mikefarah.gitbook.io/yq/"),
            summary: "YAML processor"
        ),
        CLITool(
            name: "gh",
            displayName: "GitHub CLI",
            latest: .github(RepoRef(owner: "cli", name: "cli")),
            homepage: URL(string: "https://cli.github.com"),
            summary: "GitHub from the terminal"
        ),
        CLITool(
            name: "kubectl",
            latest: .github(RepoRef(owner: "kubernetes", name: "kubernetes")),
            versionArguments: ["version", "--client"],
            versionRegex: #"Client Version:\s*v?([0-9]+(?:\.[0-9]+)+)"#,
            homepage: URL(string: "https://kubernetes.io/docs/reference/kubectl/"),
            summary: "Kubernetes command-line tool"
        ),
        CLITool(
            name: "helm",
            latest: .github(RepoRef(owner: "helm", name: "helm")),
            versionArguments: ["version", "--short"],
            homepage: URL(string: "https://helm.sh"),
            summary: "Kubernetes package manager"
        ),
        CLITool(
            name: "k9s",
            latest: .github(RepoRef(owner: "derailed", name: "k9s")),
            versionArguments: ["version", "--short"],
            homepage: URL(string: "https://k9scli.io"),
            summary: "Kubernetes terminal UI"
        ),
        CLITool(
            name: "terraform",
            latest: .github(RepoRef(owner: "hashicorp", name: "terraform")),
            versionArguments: ["version"],
            homepage: URL(string: "https://www.terraform.io"),
            summary: "Infrastructure as code"
        ),
        CLITool(
            name: "hugo",
            latest: .github(RepoRef(owner: "gohugoio", name: "hugo")),
            homepage: URL(string: "https://gohugo.io"),
            summary: "Static site generator"
        ),
        CLITool(
            name: "ollama",
            latest: .github(RepoRef(owner: "ollama", name: "ollama")),
            homepage: URL(string: "https://ollama.com"),
            summary: "Run local language models"
        ),
        CLITool(
            name: "lazygit",
            latest: .github(RepoRef(owner: "jesseduffield", name: "lazygit")),
            versionArguments: ["--version"],
            homepage: URL(string: "https://github.com/jesseduffield/lazygit"),
            summary: "Terminal UI for git"
        ),
        CLITool(
            name: "nvim",
            displayName: "Neovim",
            latest: .github(RepoRef(owner: "neovim", name: "neovim")),
            versionArguments: ["--version"],
            homepage: URL(string: "https://neovim.io"),
            summary: "Vim-fork focused on extensibility"
        ),
        CLITool(
            name: "delta",
            latest: .github(RepoRef(owner: "dandavison", name: "delta")),
            versionArguments: ["--version"],
            homepage: URL(string: "https://github.com/dandavison/delta"),
            summary: "Syntax-highlighting pager for git"
        ),
        CLITool(
            name: "mkcert",
            latest: .github(RepoRef(owner: "FiloSottile", name: "mkcert")),
            versionArguments: ["--version"],
            homepage: URL(string: "https://github.com/FiloSottile/mkcert"),
            summary: "Locally trusted development certificates"
        ),
        CLITool(
            name: "flyctl",
            displayName: "Fly.io CLI",
            latest: .github(RepoRef(owner: "superfly", name: "flyctl")),
            versionArguments: ["version"],
            homepage: URL(string: "https://fly.io/docs/flyctl/"),
            summary: "Deploy apps close to users"
        ),
    ].sorted { $0.name < $1.name }
}
