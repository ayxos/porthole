import Darwin
import Foundation

/// Socket and process enumeration through libproc, the same kernel interface
/// `lsof` uses. Works for every process the current user may inspect, needs
/// no helper binaries and takes a few milliseconds.
enum NativeSocketScanner {
    struct Socket: Hashable {
        let pid: pid_t
        let proto: SocketProtocol
        let host: String
        let port: Int
    }

    static func listeningSockets(includeUDP: Bool) -> [Socket] {
        var sockets: [Socket] = []
        let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
        for pid in allPIDs() {
            guard let fds = socketFileDescriptors(of: pid) else { continue }  // EPERM: another user's process
            for fd in fds {
                var info = socket_fdinfo()
                guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize,
                      let socket = listener(from: info, pid: pid, includeUDP: includeUDP) else { continue }
                sockets.append(socket)
            }
        }
        return sockets
    }

    static func allPIDs() -> [pid_t] {
        let stride = MemoryLayout<pid_t>.stride
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / stride + 64)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * stride))
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled) / stride).filter { $0 > 0 }
    }

    private static func socketFileDescriptors(of pid: pid_t) -> [Int32]? {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return nil }
        var buffer = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 32)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &buffer, Int32(buffer.count * stride))
        guard filled > 0 else { return nil }
        return buffer.prefix(Int(filled) / stride)
            .filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) }
            .map(\.proc_fd)
    }

    private static func listener(from info: socket_fdinfo, pid: pid_t, includeUDP: Bool) -> Socket? {
        let psi = info.psi
        guard psi.soi_family == AF_INET || psi.soi_family == AF_INET6 else { return nil }
        let proto: SocketProtocol
        let inet: in_sockinfo
        switch psi.soi_kind {
        case Int32(SOCKINFO_TCP):
            guard psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { return nil }
            proto = .tcp
            inet = psi.soi_proto.pri_tcp.tcpsi_ini
        case Int32(SOCKINFO_IN):
            guard includeUDP, psi.soi_protocol == IPPROTO_UDP else { return nil }
            inet = psi.soi_proto.pri_in
            guard inet.insi_fport == 0 else { return nil }  // connected UDP socket, not a listener
            proto = .udp
        default:
            return nil
        }
        let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_lport)))
        guard port > 0 else { return nil }
        return Socket(pid: pid, proto: proto, host: hostString(inet), port: port)
    }

    private static func hostString(_ inet: in_sockinfo) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if Int32(inet.insi_vflag) & INI_IPV6 != 0 {
            var address = inet.insi_laddr.ina_6
            inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count))
        } else {
            var address = inet.insi_laddr.ina_46.i46a_addr4
            inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count))
        }
        let text = String(cString: buffer)
        return (text == "0.0.0.0" || text == "::") ? "*" : text
    }
}

/// Per-process metadata (path, name, owner, arguments) through libproc and sysctl.
enum ProcessInspector {
    struct Details {
        var path: String?
        var name: String?
        var uid: uid_t?
        var commandLine: String?
    }

    static func details(for pid: pid_t) -> Details {
        var details = Details()

        var pathBuffer = [CChar](repeating: 0, count: 4096)  // PROC_PIDPATHINFO_MAXSIZE
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            details.path = String(cString: pathBuffer)
        }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
            details.name = String(cString: nameBuffer)
        }

        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
            details.uid = bsdInfo.pbi_uid
        }

        details.commandLine = commandLine(of: pid)
        return details
    }

    /// argv of a process from KERN_PROCARGS2. Only readable for our own processes.
    static func commandLine(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Layout: Int32 argc, executable path, NUL padding, then argc NUL-terminated arguments.
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }

    /// Process name through `ps`, for processes libproc will not describe to us (root daemons).
    static func nameViaPS(_ pid: pid_t) -> String? {
        guard let output = try? Shell.run("/bin/ps", ["-ww", "-o", "comm=", "-p", String(pid)]) else { return nil }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : (path as NSString).lastPathComponent
    }

    static func userName(uid: uid_t) -> String {
        if let entry = getpwuid(uid) { return String(cString: entry.pointee.pw_name) }
        return String(uid)
    }
}

extension ProcessInspector {
    /// Current working directory of a process (own processes only).
    static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// Physical memory footprint and total CPU time, as Activity Monitor reports them.
    static func resourceUsage(of pid: pid_t) -> (memory: UInt64, cpuTime: TimeInterval)? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = usage.ri_user_time &+ usage.ri_system_time
        let nanoseconds = Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
        return (usage.ri_phys_footprint, nanoseconds / 1_000_000_000)
    }
}
