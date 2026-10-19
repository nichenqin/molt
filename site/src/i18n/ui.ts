export const languages = {
  en: 'English',
  zh: '中文',
} as const;

export type Lang = keyof typeof languages;
export const defaultLang: Lang = 'en';

export type IconName = 'refresh' | 'bolt' | 'notes' | 'terminal' | 'shield' | 'sliders';

export interface StatItem {
  value: string;
  label: string;
}

export interface FeatureItem {
  icon: IconName;
  title: string;
  body: string;
}

export interface SourceItem {
  mark: string;
  title: string;
  body: string;
  tag: string;
}

export interface FaqItem {
  question: string;
  answer: string;
}

export interface Dictionary {
  meta: {
    title: string;
    description: string;
    ogTitle: string;
    ogDescription: string;
    docsTitle: string;
    docsDescription: string;
  };
  header: {
    features: string;
    sources: string;
    install: string;
    docs: string;
    releases: string;
    download: string;
    menu: string;
    github: string;
    language: string;
  };
  hero: {
    versionPrefix: string;
    badgeMeta: string;
    titleTop: string;
    titleBottom: string;
    lede: string;
    download: string;
    docs: string;
    note: string;
    screenshotAlt: string;
    railLabel: string;
  };
  rail: string[];
  stats: StatItem[];
  features: {
    kicker: string;
    title: string;
    body: string;
    items: FeatureItem[];
  };
  sources: {
    kicker: string;
    title: string;
    body: string;
    items: SourceItem[];
    fine: string;
  };
  cli: {
    kicker: string;
    title: string;
    body: string;
    docsLink: string;
    sourceLink: string;
    summary: string;
  };
  install: {
    kicker: string;
    title: string;
    body: string;
    dmg: { title: string; body: string; button: string };
    curl: { title: string; body: string };
    brew: { title: string; body: string };
  };
  faq: {
    kicker: string;
    title: string;
    items: FaqItem[];
  };
  footer: {
    docs: string;
    releases: string;
    github: string;
    license: string;
    copyright: string;
  };
  copy: {
    label: string;
    copied: string;
    prompt: string;
  };
  skip: string;
  notFound: {
    title: string;
    body: string;
    back: string;
  };
}

export const ui: Record<Lang, Dictionary> = {
  en: {
    meta: {
      title: 'Remige — Every update on your Mac, in one place',
      description:
        'Remige is a native macOS menu-bar app and CLI that finds updates from Homebrew, npm, pnpm, Bun, Sparkle DMG apps, the Mac App Store, and curl-installed tools. Read changelogs and update in one click.',
      ogTitle: 'Remige — Every update. One place.',
      ogDescription:
        'All your macOS updates in one native window and one CLI. Homebrew, npm, Bun, DMG apps, App Store, and curl tools.',
      docsTitle: 'Remige Docs — Install, CLI, sources, updates',
      docsDescription:
        'Remige documentation: install, CLI reference, update sources, custom tools, self-update, security and build instructions.',
    },
    header: {
      features: 'Features',
      sources: 'Sources',
      install: 'Install',
      docs: 'Docs',
      releases: 'Releases',
      download: 'Download',
      menu: 'Menu',
      github: 'GitHub',
      language: '中文',
    },
    hero: {
      versionPrefix: 'v',
      badgeMeta: 'macOS 14+ · Universal',
      titleTop: 'Every update.',
      titleBottom: 'One place.',
      lede: 'Remige watches Homebrew, npm, pnpm, Bun, Sparkle apps, the Mac App Store, and the command-line tools you installed with curl. One list. Release notes. One click.',
      download: 'Download for macOS',
      docs: 'Read the docs',
      note: 'Free · MIT · No account · No background daemon',
      screenshotAlt: 'Remige showing Homebrew, npm, Bun and app updates in one window',
      railLabel: 'Finds updates in',
    },
    rail: ['Homebrew', 'npm', 'pnpm', 'Bun', 'DMG apps', 'App Store', 'curl tools'],
    stats: [
      { value: '8', label: 'update sources' },
      { value: '≈1 s', label: 'typical scan' },
      { value: '7.4 MB', label: 'universal app' },
      { value: '0', label: 'background daemons' },
    ],
    features: {
      kicker: 'Why Remige',
      title: 'Stop checking eight tools before breakfast.',
      body: 'Updaters are fragmented. Remige runs the native sources in parallel, deduplicates the results, and gives every row a safe, visible next step.',
      items: [
        {
          icon: 'refresh',
          title: 'Native, not another Electron app',
          body: 'A SwiftUI window and menu-bar item sharing one core with the CLI. Small binary, fast launch, no web runtime.',
        },
        {
          icon: 'bolt',
          title: 'One-click where it is safe',
          body: 'Homebrew, npm, pnpm, Bun and <code>mas</code> run their own commands. Download-only apps open the full release, never a silent bundle swap.',
        },
        {
          icon: 'notes',
          title: 'Release notes, not guesswork',
          body: 'GitHub release notes and Sparkle appcast notes are fetched and cached, so you know what changed before you click.',
        },
        {
          icon: 'terminal',
          title: 'A real CLI',
          body: '<code>remige list --json</code>, <code>remige upgrade --all --dry-run</code>, <code>remige changelog iina</code>. Stable IDs for scripts.',
        },
        {
          icon: 'shield',
          title: 'Local-first by design',
          body: 'No account, no analytics, no daemon. The last scan is cached for instant paint; a failed source never blanks the list.',
        },
        {
          icon: 'sliders',
          title: 'Extensible without a plugin runtime',
          body: 'Declare a curl-installed tool with a version command, a GitHub repo and an optional self-update command.',
        },
      ],
    },
    sources: {
      kicker: 'Coverage',
      title: 'Everything you actually install.',
      body: 'If a manager is not installed, its source is skipped automatically.',
      items: [
        {
          mark: 'H',
          title: 'Homebrew',
          body: 'Formulae and casks, including <code>--greedy</code> auto-updating casks and pinned packages.',
          tag: '1-click',
        },
        {
          mark: 'n',
          title: 'npm · pnpm · Bun',
          body: 'Global packages only, with the registry as the source of truth.',
          tag: '1-click',
        },
        {
          mark: 'S',
          title: 'DMG / Sparkle apps',
          body: 'Reads real <code>SUFeedURL</code> appcasts. Honours channels and minimum macOS; ignores delta-only payloads.',
          tag: 'download',
        },
        {
          mark: 'A',
          title: 'Mac App Store',
          body: 'When <code>mas</code> is installed, App Store updates join the same list.',
          tag: '1-click',
        },
        {
          mark: '›_',
          title: 'curl & installer tools',
          body: 'A curated catalog for uv, Claude Code, rustup, ripgrep, gh and more — plus your own declarations.',
          tag: 'self-update',
        },
        {
          mark: '+',
          title: 'App manifests & catalog',
          body: 'Reads Electron Builder <code>app-update.yml</code> (GitHub or HTTPS manifests) and bundle-id catalog entries such as magpie. Homebrew keeps ownership when it installed the app.',
          tag: 'verified',
        },
      ],
      fine: 'Apps with no Sparkle feed, Homebrew cask, recognized Electron manifest, or explicit catalog entry are listed as unchecked, never guessed. That is deliberate: no silent bundle replacement.',
    },
    cli: {
      kicker: 'Same core, both surfaces',
      title: 'Point and click. Or pipe it.',
      body: 'The app and the CLI share every detector, cache and upgrade plan. JSON output is stable; upgrade commands are shown before they run.',
      docsLink: 'CLI reference',
      sourceLink: 'View source',
      summary: '22 updates · 19 one-click · scanned in 0.8s',
    },
    install: {
      kicker: 'Install',
      title: 'Get Remige.',
      body: 'macOS 14 Sonoma or newer. Apple Silicon and Intel are both in the universal build.',
      dmg: {
        title: 'Download the app',
        body: 'The normal route. Drag Remige into Applications.',
        button: 'Download DMG',
      },
      curl: {
        title: 'One-line install',
        body: 'Installs the app and CLI, verifies SHA-256.',
      },
      brew: {
        title: 'Homebrew',
        body: 'Homebrew keeps the CLI and cask up to date.',
      },
    },
    faq: {
      kicker: 'Questions',
      title: 'The honest details.',
      items: [
        {
          question: 'Is Remige signed and notarized?',
          answer:
            'Releases are built and checksummed on GitHub Actions. Developer ID signing and Apple notarization are wired into the release pipeline but require an Apple Developer Program membership; until those credentials are provided, macOS may show a Gatekeeper prompt. The installer clears the quarantine flag for you.',
        },
        {
          question: 'Does Remige install updates silently?',
          answer:
            "No. It runs the package manager's own upgrade command and shows the exact argv first in the CLI. Sparkle apps that are not cask-managed open the full download; Remige never replaces an app bundle behind your back.",
        },
        {
          question: 'Does it need sudo or an account?',
          answer:
            'No account. Remige never injects sudo. If a Homebrew cask or <code>mas</code> needs elevation, the tool reports its own error. Everything runs as your user.',
        },
        {
          question: 'What about apps installed from a DMG without Sparkle?',
          answer:
            'They are checked from standard Electron Builder manifests, a bundle-ID catalog entry, or an <code>appUpdates</code> config entry. Nothing is inferred from the display name. Apps managed by Homebrew are covered by the cask source.',
        },
        {
          question: 'Is there telemetry?',
          answer:
            'No analytics, no accounts, no background daemon. Network requests go only to the package managers, registries, appcast feeds and GitHub release pages needed for the scan.',
        },
      ],
    },
    footer: {
      docs: 'Docs',
      releases: 'Releases',
      github: 'GitHub',
      license: 'MIT',
      copyright: '© 2026 nichenqin. Built for macOS.',
    },
    copy: {
      label: 'Copy',
      copied: 'Copied',
      prompt: 'Copy this command:',
    },
    skip: 'Skip to content',
    notFound: {
      title: 'Not found',
      body: 'That page is not here.',
      back: 'Back to Remige',
    },
  },

  zh: {
    meta: {
      title: 'Remige — 一个窗口，看全 Mac 上的所有更新',
      description:
        'Remige 是原生 macOS 菜单栏应用与 CLI，聚合 Homebrew、npm、pnpm、Bun、Sparkle DMG 应用、Mac App Store 和 curl 安装的命令行工具更新。看更新日志，一键升级。',
      ogTitle: 'Remige — 所有更新，一个地方',
      ogDescription: '原生 macOS 应用 + CLI，聚合 brew、npm、Bun、DMG 应用、App Store 与 curl 工具的更新。',
      docsTitle: 'Remige 文档 — 安装、CLI、来源、更新',
      docsDescription: 'Remige 文档：安装、CLI 参考、更新来源、自定义工具、自更新、安全与构建。',
    },
    header: {
      features: '能力',
      sources: '来源',
      install: '安装',
      docs: '文档',
      releases: '版本',
      download: '下载',
      menu: '菜单',
      github: 'GitHub',
      language: 'English',
    },
    hero: {
      versionPrefix: 'v',
      badgeMeta: 'macOS 14+ · 通用二进制',
      titleTop: '所有更新。',
      titleBottom: '一个地方。',
      lede: 'Remige 盯着 Homebrew、npm、pnpm、Bun、Sparkle 应用、Mac App Store，以及你用 curl 安装的命令行工具。一个列表，先看更新日志，再一键升级。',
      download: '下载 macOS 版',
      docs: '阅读文档',
      note: '免费 · MIT · 无需账号 · 无常驻进程',
      screenshotAlt: 'Remige 在一个窗口中显示 Homebrew、npm、Bun 和应用更新',
      railLabel: '能发现',
    },
    rail: ['Homebrew', 'npm', 'pnpm', 'Bun', 'DMG 应用', 'App Store', 'curl 工具'],
    stats: [
      { value: '8', label: '更新来源' },
      { value: '≈1 秒', label: '典型扫描' },
      { value: '7.4 MB', label: '通用 App' },
      { value: '0', label: '后台进程' },
    ],
    features: {
      kicker: '为什么是 Remige',
      title: '不用在早餐前检查八个工具。',
      body: '更新入口是碎的。Remige 并行运行原生数据源，去重合并，让每一行都有一个安全、明确的操作。',
      items: [
        {
          icon: 'refresh',
          title: '原生，不是又一个 Electron',
          body: 'SwiftUI 窗口 + 菜单栏，和 CLI 共用同一套核心。体积小、启动快，没有 Web 运行时。',
        },
        {
          icon: 'bolt',
          title: '安全的地方才一键',
          body: 'Homebrew、npm、pnpm、Bun、mas 调用各自官方升级命令。只有下载页的应用打开完整安装文件，绝不静默替换 App。',
        },
        {
          icon: 'notes',
          title: '先看 Release Notes',
          body: 'GitHub Releases 与 Sparkle appcast 的更新日志会缓存，点更新前知道改了什么。',
        },
        {
          icon: 'terminal',
          title: '真正的 CLI',
          body: '<code>remige list --json</code>、<code>remige upgrade --all --dry-run</code>、<code>remige changelog iina</code>。稳定 ID，脚本友好。',
        },
        {
          icon: 'shield',
          title: '本地优先',
          body: '无账号、无统计、无守护进程。上次扫描落盘，启动立即显示；单个来源失败不会清空整个列表。',
        },
        {
          icon: 'sliders',
          title: '不用插件运行时也能扩展',
          body: '给 curl 安装的工具声明版本命令、GitHub 仓库和可选自更新命令，就够了。',
        },
      ],
    },
    sources: {
      kicker: '覆盖范围',
      title: '你真正安装的东西。',
      body: '没安装的包管理器会自动跳过，不报错。',
      items: [
        {
          mark: 'H',
          title: 'Homebrew',
          body: 'Formula 与 cask，包含 <code>--greedy</code> 自动更新 cask 和 pinned 包。',
          tag: '一键',
        },
        {
          mark: 'n',
          title: 'npm · pnpm · Bun',
          body: '只查全局包，以 npm registry 为版本依据。',
          tag: '一键',
        },
        {
          mark: 'S',
          title: 'DMG / Sparkle 应用',
          body: '读取真实 <code>SUFeedURL</code> appcast，识别 channel、最低系统版本，忽略 delta 包。',
          tag: '下载',
        },
        {
          mark: 'A',
          title: 'Mac App Store',
          body: '安装 <code>mas</code> 后，App Store 更新进入同一个列表。',
          tag: '一键',
        },
        {
          mark: '›_',
          title: 'curl / 安装脚本工具',
          body: '内置 uv、Claude Code、rustup、ripgrep、gh 等目录，也支持自定义。',
          tag: '自更新',
        },
        {
          mark: '+',
          title: '应用 manifest 与目录',
          body: '读取 Electron Builder <code>app-update.yml</code>（GitHub 或 HTTPS manifest）和 magpie 等 bundle id 目录项。Homebrew 安装的 App 仍由 cask 负责。',
          tag: '已验证',
        },
      ],
      fine: '既没有 Sparkle feed、Homebrew cask、可识别的 Electron manifest，也没有显式目录项的应用会以“未检查”列出，不会被猜测更新。这是刻意的：不静默替换应用包。',
    },
    cli: {
      kicker: '同一个核心，两个界面',
      title: '可以点，也可以管道。',
      body: '应用和 CLI 共用全部检测器、缓存和升级计划。JSON 输出稳定，升级命令执行前可见。',
      docsLink: 'CLI 文档',
      sourceLink: '查看源码',
      summary: '22 个更新 · 19 个可一键 · 0.8 秒',
    },
    install: {
      kicker: '安装',
      title: '拿到 Remige。',
      body: '需要 macOS 14 Sonoma 或更新。通用二进制同时支持 Apple Silicon 与 Intel。',
      dmg: {
        title: '下载 App',
        body: '最直接的方式，拖进 Applications 即可。',
        button: '下载 DMG',
      },
      curl: {
        title: '一行命令',
        body: '安装 App 和 CLI，并校验 SHA-256。',
      },
      brew: {
        title: 'Homebrew',
        body: '由 Homebrew 接管 App 与 CLI 的更新。',
      },
    },
    faq: {
      kicker: '常见问题',
      title: '把话说清楚。',
      items: [
        {
          question: 'Remige 签名和公证了吗？',
          answer:
            'Release 由 GitHub Actions 构建并生成校验和。Developer ID 签名与 Apple 公证已接入发布流水线，但需要 Apple Developer Program 账号；在提供证书之前，macOS 可能显示 Gatekeeper 提示。安装脚本会移除 quarantine 标记。',
        },
        {
          question: '会静默安装更新吗？',
          answer:
            '不会。Remige 调用包管理器自己的升级命令，CLI 会先显示完整 argv。非 cask 管理的 Sparkle 应用只打开完整下载页，绝不静默替换应用包。',
        },
        {
          question: '需要 sudo 或账号吗？',
          answer: '不需要账号，也不会注入 sudo。brew cask 或 mas 需要提权时，会原样返回它们自己的错误。',
        },
        {
          question: '没有 Sparkle 的 DMG 应用呢？',
          answer:
            '优先读取标准 Electron Builder <code>app-update.yml</code>（GitHub 或 HTTPS manifest），也支持按 bundle id 的目录项和 <code>appUpdates</code> 配置。都没有的应用会显示为未检查。Homebrew cask 管理的应用由 cask 来源负责。',
        },
        {
          question: '有遥测吗？',
          answer: '没有统计、没有账号、没有后台守护进程。网络请求只发生在扫描所需的包管理器、registry、appcast 和 GitHub 页面。',
        },
      ],
    },
    footer: {
      docs: '文档',
      releases: '版本',
      github: 'GitHub',
      license: 'MIT',
      copyright: '© 2026 nichenqin. 为 macOS 构建。',
    },
    copy: {
      label: '复制',
      copied: '已复制',
      prompt: '复制这条命令：',
    },
    skip: '跳到正文',
    notFound: {
      title: '页面不存在',
      body: '这个页面不在这里。',
      back: '返回 Remige 首页',
    },
  },
};
