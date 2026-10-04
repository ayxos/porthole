import Foundation

/// Friendly labels for well-known ports and processes.
enum KnownServices {
    static func hint(for entry: ListeningPort) -> String? {
        if let hint = systemProcesses[entry.processName] { return hint }
        if let hint = scriptHint(for: entry) { return hint }
        if let hint = byPort[entry.port] { return hint }
        if let hint = byProcess[entry.processName] { return hint }
        return nil
    }

    // Shown for interpreters: "node /x/node_modules/.bin/next dev" -> "next"
    private static let interpreters: Set<String> = [
        "node", "bun", "deno", "tsx", "ts-node", "python", "python3", "uv", "uvicorn", "gunicorn",
        "ruby", "java", "php", "perl", "dotnet",
    ]

    private static func scriptHint(for entry: ListeningPort) -> String? {
        let name = entry.processName.lowercased()
        guard interpreters.contains(name) || name.hasPrefix("python"),
              let commandLine = entry.commandLine else { return nil }
        for arg in commandLine.split(separator: " ").dropFirst() where !arg.hasPrefix("-") {
            let base = (String(arg) as NSString).lastPathComponent
            return base.isEmpty ? nil : base
        }
        return nil
    }

    private static let systemProcesses: [String: String] = [
        "ControlCenter": "AirPlay Receiver",
        "rapportd": "Continuity",
        "sharingd": "AirDrop / Sharing",
        "mDNSResponder": "Bonjour",
        "identityservicesd": "iMessage",
        "AirPlayXPCHelper": "AirPlay",
        "screensharingd": "Screen Sharing",
        "smbd": "SMB file sharing",
        "cupsd": "Printing (CUPS)",
        "sshd": "SSH server",
        "remoted": "Device pairing",
    ]

    private static let byPort: [Int: String] = [
        21: "FTP", 22: "SSH", 25: "SMTP", 53: "DNS", 80: "HTTP", 88: "Kerberos", 110: "POP3",
        123: "NTP", 137: "NetBIOS", 143: "IMAP", 389: "LDAP", 443: "HTTPS", 445: "SMB file sharing",
        465: "SMTPS", 500: "IKE / VPN", 548: "AFP file sharing", 587: "SMTP submission",
        631: "Printing (CUPS)", 636: "LDAPS", 993: "IMAPS", 995: "POP3S",
        1080: "SOCKS proxy", 1234: "LM Studio", 1313: "Hugo", 1337: "Strapi", 1420: "Tauri dev",
        1433: "SQL Server", 1521: "Oracle DB", 1883: "MQTT", 1900: "SSDP / UPnP",
        2181: "ZooKeeper", 2375: "Docker API", 2376: "Docker API (TLS)",
        3000: "Dev server", 3001: "Dev server", 3030: "Dev server", 3100: "Loki",
        3283: "Apple Remote Desktop", 3306: "MySQL / MariaDB", 3389: "Remote Desktop", 3478: "STUN / TURN",
        4000: "Phoenix / Jekyll", 4040: "ngrok inspector", 4200: "Angular CLI", 4222: "NATS",
        4321: "Astro", 4500: "IPsec NAT-T",
        5000: "Flask / dev server", 5001: "Flask / Docker registry", 5037: "ADB server", 5060: "SIP",
        5173: "Vite", 5174: "Vite", 5353: "Bonjour (mDNS)", 5432: "PostgreSQL", 5500: "Live Server",
        5555: "ADB", 5601: "Kibana", 5672: "RabbitMQ", 5900: "Screen Sharing (VNC)",
        6006: "Storybook / TensorBoard", 6080: "noVNC", 6379: "Redis", 6443: "Kubernetes API",
        7000: "AirPlay / dev server", 7474: "Neo4j", 7687: "Neo4j Bolt", 7860: "Gradio",
        8000: "HTTP dev server", 8008: "HTTP alt", 8025: "Mailpit / MailHog", 8065: "Mattermost",
        8080: "HTTP alt", 8081: "Metro bundler", 8086: "InfluxDB", 8096: "Jellyfin", 8097: "React DevTools",
        8123: "Home Assistant", 8200: "Vault", 8384: "Syncthing", 8443: "HTTPS alt", 8501: "Streamlit",
        8787: "RStudio", 8888: "Jupyter",
        9000: "PHP-FPM / MinIO / SonarQube", 9001: "MinIO console / Portainer", 9090: "Prometheus",
        9092: "Kafka", 9200: "Elasticsearch", 9229: "Node inspector", 9418: "Git daemon",
        10250: "Kubelet", 11211: "Memcached", 11434: "Ollama", 15672: "RabbitMQ UI",
        19000: "Expo", 19006: "Expo web", 24678: "Vite HMR", 27017: "MongoDB",
        50051: "gRPC", 54321: "Supabase API", 54322: "Supabase DB", 54323: "Supabase Studio",
        62078: "iPhone sync (lockdownd)",
    ]

    private static let byProcess: [String: String] = [
        "com.docker.backend": "Docker Desktop",
        "OrbStack Helper": "OrbStack",
        "ollama": "Ollama",
        "postgres": "PostgreSQL", "redis-server": "Redis", "mongod": "MongoDB",
        "mysqld": "MySQL", "mariadbd": "MariaDB",
        "nginx": "nginx", "httpd": "Apache", "caddy": "Caddy", "traefik": "Traefik",
        "Code Helper (Plugin)": "VS Code extension", "Code Helper": "VS Code",
        "Cursor Helper (Plugin)": "Cursor extension",
        "Unity": "Unity Editor", "UnityShaderCompiler": "Unity shader compiler",
        "Spotify": "Spotify", "Dropbox": "Dropbox", "Steam Helper": "Steam",
        "Figma Helper": "Figma", "Discord Helper": "Discord", "Slack Helper": "Slack",
        "Brave Browser Helper": "Brave", "Google Chrome Helper": "Chrome", "Arc Helper": "Arc",
        "java": "Java", "python": "Python", "python3": "Python", "node": "Node.js",
        "bun": "Bun", "deno": "Deno", "ruby": "Ruby", "php": "PHP", "dotnet": ".NET",
    ]
}
