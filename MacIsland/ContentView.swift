import SwiftUI
import Foundation
import AppKit
import Combine

struct SpotifyInfo {
    let albumArtPath: String?
    let position: Double
    let duration: Double
    let isPlaying: Bool
    let debugString: String
}

struct ContentView: View {
    @State private var isHovered = false
    @State private var spotifyInfo: SpotifyInfo = SpotifyInfo(albumArtPath: nil, position: 0, duration: 1, isPlaying: false, debugString: "")
    @State private var cancellable: AnyCancellable? = nil

    @MainActor
    func getSpotifyInfo() async -> SpotifyInfo {
        let script = """
        tell application "Spotify"
            if it is running then
                try
                    set pos to player position
                    set dur to duration of current track
                    set playing to player state as string
                    tell application "Image Events"
                        launch
                        set theImage to artwork of current track of application "Spotify"
                        if class of theImage is not equal to missing value then
                            set tempFile to file ((path to temporary items as text) & "spotify_art.jpg")
                            save theImage as JPEG in tempFile
                            set artPath to POSIX path of tempFile
                        else
                            set artPath to ""
                        end if
                    end tell
                    return (pos as string) & "|" & (dur as string) & "|" & artPath & "|" & playing
                on error
                    return "||||"
                end try
            else
                return "||||"
            end if
        end tell
        """
        do {
            let output = try await runOSAScript(script)
            let parts = output.split(separator: "|", maxSplits: 3).map(String.init)
            if parts.count == 4 {
                let position = Double(parts[0]) ?? 0
                let duration = Double(parts[1]) ?? 1
                let pathString = parts[2]
                let playingStr = parts[3]
                let isPlaying = playingStr == "playing"
                let path = pathString.isEmpty ? nil : pathString

                let debugStr = "Output: '\(output)' - Parts: \(parts) - Path: \(pathString)"
                return SpotifyInfo(albumArtPath: path, position: position, duration: duration, isPlaying: isPlaying, debugString: debugStr)
            }
        } catch {
            print("Error getting Spotify info: \(error)")
            return SpotifyInfo(albumArtPath: nil, position: 0, duration: 1, isPlaying: false, debugString: "Error: \(error.localizedDescription)")
        }
        return SpotifyInfo(albumArtPath: nil, position: 0, duration: 1, isPlaying: false, debugString: "No info available")
    }

    @MainActor
    func sendSpotifyCommand(_ command: String) {
        let script = "tell application \"Spotify\" to \(command)"
        Task {
            do {
                _ = try await runOSAScript(script)
            } catch {
                print("Command error: \(error)")
            }
        }
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
        ZStack { // Stack views on top of each other
            // Always visible two small squares
            HStack(spacing: 200) {
                Group {
                    if let path = spotifyInfo.albumArtPath {
                        AsyncImage(url: URL(fileURLWithPath: path)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure(_):
                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.5))
                            @unknown default:
                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                            }
                        }
                        .frame(width: 40, height: 40)
                        .cornerRadius(8)
                        .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 40, height: 40)
                            .cornerRadius(8)
                    }
                }
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            }

            // Big rectangle appears only when hovered
            if isHovered {
                VStack(spacing: 10) {
                    ProgressView(value: spotifyInfo.duration > 0 ? spotifyInfo.position / spotifyInfo.duration : 0)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.green))
                        .frame(height: 4)
                        .padding(.horizontal, 20)

                    HStack(spacing: 40) {
                        Button(action: { sendSpotifyCommand("previous track") }) {
                            Image(systemName: "backward.end.fill")
                                .foregroundColor(.white)
                                .font(.title)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            if spotifyInfo.isPlaying {
                                sendSpotifyCommand("pause")
                            } else {
                                sendSpotifyCommand("play")
                            }
                        }) {
                            Image(systemName: spotifyInfo.isPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { sendSpotifyCommand("next track") }) {
                            Image(systemName: "forward.end.fill")
                                .foregroundColor(.white)
                                .font(.title)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Text(spotifyInfo.debugString)
                        .foregroundColor(.white)
                        .font(.caption)
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .frame(width: 280, height: 140)
                .background(Color.black.opacity(0.9))
                .cornerRadius(12)
                .transition(.scale)
                .offset(x: 0, y: 30)
            }
            
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
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
        .onDisappear {
            cancellable?.cancel()
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 500, height: 250)
        .background(Color.gray.opacity(0.2))
}
