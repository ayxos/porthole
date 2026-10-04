import Foundation

/// Human-written explanations of processes that commonly hold ports on a Mac.
struct ProcessKnowledge {
    let summary: String
    let category: String
    let advice: String?

    init(_ summary: String, category: String, advice: String? = nil) {
        self.summary = summary
        self.category = category
        self.advice = advice
    }
}

enum ProcessKnowledgeBase {
    static func lookup(_ entry: ListeningPort) -> ProcessKnowledge? {
        let name = entry.processName
        if let known = byName[name] { return known }
        if name.lowercased().hasPrefix("python") { return byName["Python"] }
        if name.hasPrefix("postgres") { return byName["postgres"] }

        // Chromium / Electron helpers: "Notion Helper (Renderer)" belongs to "Notion".
        if let app = helperAppName(name) {
            if let known = byName[app] {
                return ProcessKnowledge("Helper process of \(app). \(known.summary)",
                                        category: known.category, advice: known.advice)
            }
            return ProcessKnowledge(
                "Helper process of \(app). Chromium and Electron based apps split into several processes; a port here is usually a renderer, an extension host or a local API the app exposes to your browser.",
                category: "App",
                advice: "Quit \(app) from its own menu rather than killing the helper, which the app may just respawn.")
        }
        return nil
    }

    static func helperAppName(_ name: String) -> String? {
        guard let range = name.range(of: " Helper") else { return nil }
        let app = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return app.isEmpty ? nil : app
    }

    private static let launchdRestarts = "Part of macOS. launchd restarts it if you kill it."

    static let byName: [String: ProcessKnowledge] = [
        // macOS
        "ControlCenter": .init(
            "macOS Control Center. Its listeners on 5000 and 7000 are the AirPlay Receiver, which lets iPhones, iPads and other Macs stream to this Mac.",
            category: "macOS",
            advice: "Turn it off in System Settings › General › AirDrop & Handoff › AirPlay Receiver instead of killing it."),
        "rapportd": .init(
            "Apple's Continuity daemon (Rapport). It coordinates nearby Apple devices for Handoff, Universal Clipboard, Sidecar, Continuity Camera and Apple Watch unlock.",
            category: "macOS", advice: launchdRestarts),
        "sharingd": .init(
            "macOS Sharing daemon: AirDrop, Handoff discovery and Shared with You.",
            category: "macOS", advice: launchdRestarts),
        "mDNSResponder": .init(
            "Bonjour (multicast DNS) responder. It resolves .local names, advertises services on the LAN and is also the system DNS resolver.",
            category: "macOS", advice: "Killing it briefly breaks DNS for every app. launchd restarts it."),
        "identityservicesd": .init(
            "Identity Services daemon that backs iMessage, FaceTime and Continuity device identity.",
            category: "macOS", advice: launchdRestarts),
        "AirPlayXPCHelper": .init(
            "AirPlay helper used when this Mac streams to or receives from AirPlay devices.",
            category: "macOS", advice: launchdRestarts),
        "remoted": .init(
            "Remote device daemon (RemoteXPC) used for pairing with iPhones, Apple TVs and Xcode device support.",
            category: "macOS", advice: launchdRestarts),
        "launchd": .init(
            "The macOS init process. When launchd holds a port it is keeping it open for an on-demand service such as Remote Login (22) or Screen Sharing (5900) and starts the real server on the first connection.",
            category: "macOS", advice: "Disable the service in System Settings › General › Sharing. Never kill launchd."),
        "cupsd": .init(
            "CUPS printing server. Port 631 serves the printing admin interface at localhost:631.",
            category: "macOS", advice: launchdRestarts),
        "sshd": .init("OpenSSH server (Remote Login in Sharing settings).", category: "macOS",
                      advice: "Turn Remote Login off in System Settings › General › Sharing."),
        "sshd-session": .init("An active OpenSSH login session spawned by sshd.", category: "macOS"),
        "screensharingd": .init("Screen Sharing / Remote Management server (VNC on 5900).", category: "macOS",
                                advice: "Turn Screen Sharing off in System Settings › General › Sharing."),
        "smbd": .init("SMB file sharing server (File Sharing in Sharing settings).", category: "macOS"),
        "netbiosd": .init("NetBIOS name service used alongside Windows file sharing.", category: "macOS"),
        "usbmuxd": .init(
            "USB multiplexer for iOS devices. It proxies connections to attached iPhones and iPads for Finder sync, Xcode and the Simulator.",
            category: "macOS", advice: launchdRestarts),
        "bluetoothd": .init("Bluetooth daemon.", category: "macOS", advice: launchdRestarts),
        "com.apple.WebKit.Networking": .init("Safari's networking process (WebKit).", category: "Browser"),
        "Safari": .init("Safari. Local ports typically come from WebRTC or Web Inspector.", category: "Browser"),
        "Music": .init("Apple Music. Home Sharing and the remote-control service use ports 3689 and 7000.", category: "App"),

        // Browsers
        "Google Chrome": .init(
            "Google Chrome. Listening ports usually come from WebRTC, Cast / mDNS discovery, or a DevTools remote debugging session.",
            category: "Browser"),
        "Brave Browser": .init(
            "Brave browser (Chromium based). Listening ports usually come from WebRTC, Cast / mDNS discovery, or DevTools.",
            category: "Browser"),
        "Microsoft Edge": .init("Microsoft Edge (Chromium based).", category: "Browser"),
        "Arc": .init("Arc browser (Chromium based).", category: "Browser"),
        "firefox": .init("Mozilla Firefox. Ports usually belong to WebRTC or the remote debugging server.", category: "Browser"),

        // Developer tools
        "Code": .init("Visual Studio Code.", category: "Dev tool"),
        "Code Helper (Plugin)": .init(
            "VS Code extension host. Dev servers, language servers and debug adapters started by extensions listen from here, as do Live Server and port-forwarding features.",
            category: "Dev tool", advice: "Reload or quit the VS Code window instead; the editor respawns killed hosts."),
        "Cursor": .init("Cursor editor (a VS Code fork).", category: "Dev tool"),
        "Cursor Helper (Plugin)": .init(
            "Cursor's extension host. Dev servers, language servers and debug adapters started by extensions listen from here.",
            category: "Dev tool", advice: "Reload or quit the Cursor window instead; the editor respawns killed hosts."),
        "Xcode": .init("Xcode. Ports are used by debugging, previews and device services.", category: "Dev tool"),
        "Unity": .init(
            "Unity Editor. Its ports serve the Profiler, the Package Manager and Play Mode connections from devices.",
            category: "Dev tool", advice: "Save your scene before killing it; Unity does not auto-save."),
        "UnityShaderCompiler": .init(
            "Unity's shader compiler worker. It talks to the Editor over a local port and exits with it.",
            category: "Dev tool"),
        "adb": .init("Android Debug Bridge server (5037). It brokers connections to Android devices and emulators.",
                     category: "Dev tool", advice: "Use `adb kill-server`; Android Studio restarts it when needed."),
        "qemu-system-aarch64": .init(
            "QEMU virtual machine, usually an Android emulator or UTM / Lima VM. Local ports forward the guest's console, ADB or SSH.",
            category: "Dev tool"),
        "Electron": .init("An unpackaged Electron app, usually one being developed (`electron .`).", category: "Dev tool"),

        // Runtimes
        "node": .init(
            "Node.js runtime. The command line tells which script or tool it runs: dev servers like Vite, Next.js or Metro, or your own server.",
            category: "Runtime", advice: "Safe to kill if you started it; rerun the npm script to bring it back."),
        "bun": .init("Bun JavaScript runtime and package manager.", category: "Runtime",
                     advice: "Safe to kill if you started it."),
        "deno": .init("Deno JavaScript / TypeScript runtime.", category: "Runtime",
                      advice: "Safe to kill if you started it."),
        "Python": .init(
            "Python interpreter. The command line shows the module or script: Flask, Django, uvicorn, Jupyter, Streamlit, http.server…",
            category: "Runtime", advice: "Safe to kill if you started it."),
        "ruby": .init("Ruby interpreter: Rails / Puma, Jekyll or Sinatra servers, CocoaPods…", category: "Runtime"),
        "java": .init(
            "Java Virtual Machine. Usually a Gradle or Maven daemon, a Spring Boot app, Kafka, Elasticsearch or an IDE service; the command line names the JAR or main class.",
            category: "Runtime", advice: "Gradle daemons respawn on the next build; stop them with `gradle --stop`."),
        "php": .init("PHP built-in web server (`php -S`).", category: "Runtime"),
        "php-fpm": .init("PHP FastCGI process manager, usually behind nginx.", category: "Runtime"),
        "dotnet": .init(".NET runtime. Kestrel web servers listen on 5000 / 5001 by default.", category: "Runtime"),

        // Databases
        "postgres": .init(
            "PostgreSQL server (5432). Seeing several postgres processes is normal: one listener plus background workers.",
            category: "Database",
            advice: "Prefer `brew services stop postgresql` or `pg_ctl stop`; SIGKILL forces crash recovery on the next start."),
        "redis-server": .init("Redis in-memory data store (6379).", category: "Database",
                              advice: "`redis-cli shutdown` persists data before stopping."),
        "mongod": .init("MongoDB server (27017).", category: "Database",
                        advice: "Prefer `brew services stop mongodb-community` or `db.shutdownServer()`."),
        "mysqld": .init("MySQL server (3306).", category: "Database",
                        advice: "Prefer `brew services stop mysql` or `mysqladmin shutdown`."),
        "mariadbd": .init("MariaDB server (3306).", category: "Database",
                          advice: "Prefer `brew services stop mariadb`."),
        "memcached": .init("Memcached cache server (11211).", category: "Database"),

        // Web servers
        "nginx": .init("nginx web server / reverse proxy. The master process spawns the workers; killing the master stops them all.",
                       category: "Server", advice: "`nginx -s quit` or `brew services stop nginx` shuts it down cleanly."),
        "httpd": .init("Apache HTTP server.", category: "Server", advice: "`apachectl stop` shuts it down cleanly."),
        "caddy": .init("Caddy web server with automatic HTTPS. 2019 is its admin API.", category: "Server"),
        "traefik": .init("Traefik reverse proxy. 8080 is its dashboard by default.", category: "Server"),

        // Containers
        "com.docker.backend": .init(
            "Docker Desktop's backend. Ports you publish with `-p` are bound here on the host, so killing it drops every container's port mapping.",
            category: "Containers", advice: "Stop the container (`docker stop`) or quit Docker Desktop from its menu."),
        "Docker Desktop": .init("Docker Desktop's user interface.", category: "Containers"),
        "OrbStack Helper": .init(
            "OrbStack, a lightweight Docker and Linux VM runtime. It binds published container ports on the host.",
            category: "Containers", advice: "Stop the container or quit OrbStack from its menu."),
        "OrbStack": .init("OrbStack's user interface.", category: "Containers"),

        // AI
        "ollama": .init("Ollama local LLM server. 11434 is its HTTP API used by the `ollama` CLI and chat clients.",
                        category: "AI", advice: "Quit the menu bar app or `brew services stop ollama`."),
        "LM Studio": .init("LM Studio. Its local inference server defaults to port 1234.", category: "AI"),

        // Networking
        "ssh": .init(
            "SSH client holding a local port forward (`-L`) or SOCKS proxy (`-D`); traffic to this port is tunnelled to the remote host.",
            category: "Network", advice: "Safe to kill; the tunnel simply closes."),
        "cloudflared": .init("Cloudflare Tunnel connector. 20241 is its metrics endpoint.", category: "Network"),
        "ngrok": .init("ngrok tunnel agent. 4040 is its local inspector UI.", category: "Network"),
        "tailscaled": .init("Tailscale VPN daemon.", category: "Network",
                            advice: "Use the Tailscale menu to disconnect instead."),
        "IPNExtension": .init("Tailscale's network extension.", category: "Network"),
        "syncthing": .init("Syncthing file synchronisation. 8384 is the web UI, 22000 the sync protocol.", category: "Network"),

        // Apps
        "Spotify": .init("Spotify. It listens for Spotify Connect discovery on the local network (4070 range, 57621).", category: "App"),
        "Dropbox": .init("Dropbox client. 17500 is LAN sync discovery; 17600 / 17603 serve the Finder integration.", category: "App"),
        "steam_osx": .init("Steam client. Local ports serve the overlay browser and Remote Play discovery.", category: "App"),
        "Discord": .init("Discord. The 6463–6472 range is its local RPC API for rich presence.", category: "App"),
        "Slack": .init("Slack desktop app.", category: "App"),
        "Figma": .init("Figma desktop app.", category: "App"),
        "figma_agent": .init("Figma's font helper; it serves your local fonts to Figma in the browser (18412 / 44950).",
                             category: "App"),
        "zoom.us": .init("Zoom client. Local ports handle the browser-to-app launch handshake.", category: "App"),
        "Raycast": .init("Raycast launcher.", category: "App"),
        "1Password": .init("1Password. A local port serves the browser extension and SSH agent integration.", category: "App"),
        "Plex Media Server": .init("Plex Media Server. 32400 is the web app and streaming API.", category: "App"),
        "Adobe Desktop Service": .init("Adobe Creative Cloud background service.", category: "App"),
        "Creative Cloud": .init("Adobe Creative Cloud desktop app.", category: "App"),
        "Claude": .init("Claude desktop app.", category: "App"),
    ]
}
