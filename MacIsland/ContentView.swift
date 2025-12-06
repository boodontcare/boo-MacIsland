import SwiftUI
import Foundation
import AppKit
import Combine

enum PlayerState: Equatable {
    case playing
    case stopped

    mutating func toggle() {
        self = self == .playing ? .stopped : .playing
    }
}

struct SpotifyInfo {
    let albumArtURL: String?
    let position: Double
    let duration: Double
    var isPlaying: PlayerState
    let songTitle: String
    let artist: String
    let album: String
    let debugString: String
}

struct ContentView: View {
    @State private var isHovered = false
    @State private var spotifyInfo: SpotifyInfo? = nil
    @State private var cancellable: AnyCancellable? = nil
    @State private var isCommandInProgress = false
    @State private var lastClickTime: Date? = nil
    @State private var hoverTask: Task<Void, Never>? = nil
    @State private var animationPhase = 0.0
    @State private var animationTimer: Timer? = nil

    @MainActor
    func togglePlayback() async {
        // Debounce multiple clicks (minimum 0.5 seconds between clicks)
        let now = Date()
        if let last = lastClickTime, now.timeIntervalSince(last) < 0.5 {
            return
        }
        lastClickTime = now

        guard let current = spotifyInfo, !isCommandInProgress else { return }
        isCommandInProgress = true

        let wasPlaying = current.isPlaying
        let optimisticPlaying = wasPlaying == .playing ? PlayerState.stopped : PlayerState.playing

        // Optimistically update UI immediately
        spotifyInfo = SpotifyInfo(
            albumArtURL: current.albumArtURL,
            position: current.position,
            duration: current.duration,
            isPlaying: optimisticPlaying,
            songTitle: current.songTitle,
            artist: current.artist,
            album: current.album,
            debugString: current.debugString
        )

        // Pause polling during command
        cancellable?.cancel()

        // Send actual command
        do {
            try await sendSpotifyCommand(wasPlaying == .playing ? "pause" : "play")
            // Command succeeded, but we should verify the state by polling immediately
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
            let updatedInfo = await getSpotifyInfo()
            spotifyInfo = updatedInfo
        } catch {
            print("Command error: \(error)")
            // Revert on error
            spotifyInfo = current // Revert to original state
        }

        isCommandInProgress = false

        // Restart polling
        cancellable = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
            .sink { _ in
                Task {
                    spotifyInfo = await getSpotifyInfo()
                }
            }
    }

    @MainActor
    func getSpotifyInfo() async -> SpotifyInfo {
        let script = """
        tell application "Spotify"

        	if player state is not playing and player state is not paused then
        		return "Spotify is not playing anything."
        	end if

        	set trackName to name of current track
        	set artistName to artist of current track
        	set albumName to album of current track
        	set albumArtURL to artwork url of current track
        	set playerState to player state as string

        	set trackDuration to duration of current track -- in milliseconds
        	set trackPosition to player position -- in seconds

        	-- convert duration to seconds so it matches position format
        	set trackDurationSeconds to (trackDuration / 1000)

        	return ¬
        		¬
        			¬
        				¬
        					¬
        						¬
        						{songName:trackName, artistName:artistName, albumName:albumName, albumArtURL:albumArtURL, playerState:playerState, songPosition:trackPosition, songDuration:trackDurationSeconds}

        end tell
        """
        do {
            let output = try await runOSAScript(script)
            if output.trimmingCharacters(in: .whitespacesAndNewlines) == "Spotify is not playing anything." {
                return SpotifyInfo(albumArtURL: nil, position: 0, duration: 1, isPlaying: PlayerState.stopped, songTitle: "", artist: "", album: "", debugString: "Spotify not playing")
            }
            // Parse AppleScript record format like {songName:"Title", artistName:"Artist", ...}
            if let parsed = parseAppleScriptRecord(output) {
                let debugStr = "Parsed: \(parsed)"
                return SpotifyInfo(
                    albumArtURL: parsed["albumArtURL"],
                    position: Double(parsed["songPosition"] ?? "0") ?? 0,
                    duration: Double(parsed["songDuration"] ?? "1") ?? 1,
                    isPlaying: (parsed["playerState"] == "playing") ? PlayerState.playing : PlayerState.stopped,
                    songTitle: parsed["songName"] ?? "",
                    artist: parsed["artistName"] ?? "",
                    album: parsed["albumName"] ?? "",
                    debugString: debugStr
                )
            } else {
                return SpotifyInfo(albumArtURL: nil, position: 0, duration: 1, isPlaying: PlayerState.stopped, songTitle: "", artist: "", album: "", debugString: "Parse error: \(output)")
            }
        } catch {
            print("Error getting Spotify info: \(error)")
            return SpotifyInfo(albumArtURL: nil, position: 0, duration: 1, isPlaying: PlayerState.stopped, songTitle: "", artist: "", album: "", debugString: "Error: \(error.localizedDescription)")
        }
    }

    func parseAppleScriptRecord(_ recordString: String) -> [String: String]? {
        // Remove { } and split by commas, then parse key:value pairs
        let clean = recordString.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        let pairs = clean.components(separatedBy: ", ")
        var dict = [String: String]()
        for pair in pairs {
            let components = pair.split(separator: ":", maxSplits: 1)
            if components.count == 2 {
                let key = components[0].trimmingCharacters(in: .whitespaces)
                var value = components[1].trimmingCharacters(in: .whitespaces)
                // Remove quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                dict[key] = value
            }
        }
        return dict.isEmpty ? nil : dict
    }

    @MainActor
    func sendSpotifyCommand(_ command: String) async throws {
        let script = "tell application \"Spotify\" to \(command)"
        _ = try await runOSAScript(script)
    }

    func runOSAScript(_ script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OSAScript", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }

    var body: some View {
        Group {
            if let info = spotifyInfo {
                VStack(alignment: .center, spacing: 0) {
                    // Always visible two small squares
                    HStack(spacing: 200) {
                        Group {
                            if let urlString = info.albumArtURL, let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(width: 40, height: 40)
                                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: isHovered ? 0 : 8, bottomTrailingRadius: isHovered ? 0 : 8, topTrailingRadius: 8))
                                    case .success(let image):
                                        ZStack {
                                            Rectangle()
                                                .fill(Color.black)
                                                .frame(width: 40, height: 40)
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 32, height: 32)
                                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: isHovered ? 0 : 6, bottomTrailingRadius: isHovered ? 0 : 6, topTrailingRadius: 6))
                                                .opacity(isHovered ? 0.0 : 1.0)
                                        }
                                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: isHovered ? 0 : 8, bottomTrailingRadius: isHovered ? 0 : 8, topTrailingRadius: 8))
                                    case .failure(_):
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(width: 40, height: 40)
                                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: isHovered ? 0 : 8, bottomTrailingRadius: isHovered ? 0 : 8, topTrailingRadius: 8))
                                    @unknown default:
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(width: 40, height: 40)
                                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: isHovered ? 0 : 8, bottomTrailingRadius: isHovered ? 0 : 8, topTrailingRadius: 8))
                                    }
                                }
                            } else {
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: 40, height: 40)
                                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: isHovered ? 0 : 8, bottomTrailingRadius: isHovered ? 0 : 8, topTrailingRadius: 8))
                            }
                        }
                        ZStack {
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: 40, height: 40)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: isHovered ? 0 : 8, bottomTrailingRadius: isHovered ? 0 : 8, topTrailingRadius: 8))

                            // Sound wave animation overlay
                            if !isHovered {
                                HStack(spacing: 1) {
                                    ForEach(0..<5, id: \.self) { index in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.6))
                                            .frame(width: 2, height: 4 + 8 * (1 + sin(animationPhase + Double(index) * 0.8)))
                                            .clipShape(Capsule())
                                    }
                                }
                                .frame(height: 16)
                                .opacity(isHovered ? 0.0 : 1.0)  // Fade when expanded view opens
                            }
                        }
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: isHovered ? 0 : 8, bottomTrailingRadius: isHovered ? 0 : 8, topTrailingRadius: 8))
                    }

                    // Big rectangle appears only when hovered
                    if isHovered {
                        HStack(spacing: 8) {
                            // Album art on the left side (smaller)
                            Group {
                                if let urlString = info.albumArtURL, let url = URL(string: urlString) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            Rectangle()
                                                .fill(Color.black)
                                                .frame(width: 50, height: 60)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        case .success(let image):
                                            ZStack {
                                                Rectangle()
                                                    .fill(Color.black)
                                                    .frame(width: 50, height: 60)
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 45, height: 45)
                                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        case .failure(_):
                                            Rectangle()
                                                .fill(Color.black)
                                                .frame(width: 50, height: 60)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        @unknown default:
                                            Rectangle()
                                                .fill(Color.black)
                                                .frame(width: 50, height: 60)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                } else {
                                    Rectangle()
                                        .fill(Color.black)
                                        .frame(width: 50, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }

                            // Right side content (compact)
                            VStack(spacing: 4) {
                                VStack(spacing: 2) {
                                    Text(info.songTitle)
                                        .foregroundColor(.white)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(info.artist) - \(info.album)")
                                        .foregroundColor(.white.opacity(0.8))
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                ProgressView(value: info.duration > 0 ? info.position / info.duration : 0)
                                    .progressViewStyle(LinearProgressViewStyle(tint: Color.green))
                                    .frame(height: 3)

                                HStack(spacing: 12) {
                                    Button(action: { Task {
                                        if !isCommandInProgress {
                                            isCommandInProgress = true
                                            do { try await sendSpotifyCommand("previous track") } catch { print(error) }
                                            spotifyInfo = await getSpotifyInfo()
                                            isCommandInProgress = false
                                        }
                                    } }) {
                                        Image(systemName: "backward.end.fill")
                                            .foregroundColor(.white.opacity(isCommandInProgress ? 0.5 : 1.0))
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(isCommandInProgress)
                                    .accessibilityLabel("Previous track")
                                    .accessibilityHint("Go to the previous song in your Spotify playlist")

                                    Button(action: {
                                        Task { await togglePlayback() }
                                    }) {
                                        Image(systemName: info.isPlaying == .playing ? "pause.fill" : "play.fill")
                                            .foregroundColor(.white.opacity(isCommandInProgress ? 0.5 : 1.0))
                                            .font(.system(size: 15))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(isCommandInProgress)
                                    .accessibilityLabel(info.isPlaying == .playing ? "Pause" : "Play")
                                    .accessibilityHint("Toggle playback of the current song")

                                    Button(action: { Task {
                                        if !isCommandInProgress {
                                            isCommandInProgress = true
                                            do { try await sendSpotifyCommand("next track") } catch { print(error) }
                                            spotifyInfo = await getSpotifyInfo()
                                            isCommandInProgress = false
                                        }
                                    } }) {
                                        Image(systemName: "forward.end.fill")
                                            .foregroundColor(.white.opacity(isCommandInProgress ? 0.5 : 1.0))
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(isCommandInProgress)
                                    .accessibilityLabel("Next track")
                                    .accessibilityHint("Go to the next song in your Spotify playlist")
                                }
                            }
                        }
                        .frame(width: 260, height: 70)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.9))
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                }
            } else {
                // Loading view
                VStack(alignment: .center, spacing: 0) {
                    HStack(spacing: 200) {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 40, height: 40)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 8))
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 40, height: 40)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 8))
                    }
                }
            }
        }
        .onHover { hovering in
            if hovering {
                hoverTask?.cancel()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isHovered = true
                }
            } else {
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds delay before hiding
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isHovered = false
                        }
                        hoverTask = nil
                    }
                }
            }
        }
        .onAppear {
            // Initial fetch
            Task {
                spotifyInfo = await getSpotifyInfo()
            }
            // Periodic update every 2 seconds
            cancellable = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
                .sink { _ in
                    Task {
                        spotifyInfo = await getSpotifyInfo()
                    }
                }
        }
        .onChange(of: spotifyInfo?.isPlaying ?? .stopped) {
            updateAnimationTimer()
        }
        .onChange(of: isHovered) {
            updateAnimationTimer()
        }
        .onDisappear {
            cancellable?.cancel()
            hoverTask?.cancel()
            animationTimer?.invalidate()
        }
    }

    private func updateAnimationTimer() {
        // Update animation timer based on playback state and hover state
        if let info = spotifyInfo, !isHovered && info.isPlaying == .playing {
            // Start animation if not already running
            if animationTimer == nil {
                animationTimer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
                    animationPhase += 0.2 // Adjust speed here
                }
            }
        } else {
            // Stop animation
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

}

#Preview {
    ContentView()
        .frame(width: 500, height: 250)
        .background(Color.gray.opacity(0.2))
}
