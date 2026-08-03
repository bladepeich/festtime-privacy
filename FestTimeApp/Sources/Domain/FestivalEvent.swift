import Foundation

struct FestivalEvent: Codable, Identifiable, Hashable {
    let id: String
    let dia: String
    let turno: Shift
    let hora: String
    let artista: String
    let escenario: String

    var searchArtist: String {
        artista.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    var startHourMinute: (hour: Int, minute: Int)? {
        let timeToken = hora
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? hora
        let parts = timeToken.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        return (hour, minute)
    }

    var sortableMinutes: Int {
        guard let startTime = startHourMinute else {
            return Int.max
        }

        let hour = startTime.hour
        let minute = startTime.minute

        // Keep events after midnight ordered at the end of a festival night.
        if hour < 10 {
            return (hour + 24) * 60 + minute
        }

        return hour * 60 + minute
    }
}
