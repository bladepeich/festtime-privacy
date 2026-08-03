import SwiftUI

struct EventCardView: View {
    let event: FestivalEvent
    let stageColorHex: String
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(event.hora) h")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(event.artista)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(event.escenario)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: stageColorHex))
                    .textCase(.uppercase)
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(hex: stageColorHex))
                .frame(width: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: shadowColor, radius: colorScheme == .dark ? 0 : 4, x: 0, y: 2)
    }

    private var cardBackground: Color {
        if colorScheme == .dark {
            return Color(.secondarySystemBackground)
        }

        return Color(.systemBackground)
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.18)
        }

        return Color.black.opacity(0.08)
    }

    private var borderWidth: CGFloat {
        colorScheme == .dark ? 1.2 : 1
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return .clear
        }

        return .black.opacity(0.08)
    }
}
