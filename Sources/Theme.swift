import SwiftUI

struct MochiCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10)))
    }
}

struct MochiMascot: View {
    var mood: Mood = .happy
    enum Mood { case happy, calm, proud }
    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 36, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 36)
                .fill(.white)
                .frame(width: 76, height: 62)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            HStack(spacing: 20) {
                Circle().fill(.black).frame(width: 6, height: 8)
                Circle().fill(.black).frame(width: 6, height: 8)
            }
            .offset(y: 1)
            if mood != .calm {
                Path { path in
                    path.move(to: CGPoint(x: 33, y: 39))
                    path.addQuadCurve(to: CGPoint(x: 43, y: 39), control: CGPoint(x: 38, y: 45))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            HStack(spacing: 37) {
                Capsule().fill(Color.black.opacity(0.16)).frame(width: 10, height: 4)
                Capsule().fill(Color.black.opacity(0.16)).frame(width: 10, height: 4)
            }
            .offset(y: 15)
        }
        .frame(width: 86, height: 78)
        .accessibilityLabel("Mochi mascot")
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?
    init(_ title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 27, weight: .bold, design: .rounded))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct EmptyMochi: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            MochiMascot(mood: .calm)
            Text(title).font(.headline)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
    }
}

extension View {
    func monochromeButton() -> some View {
        buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).controlSize(.large)
    }
}
