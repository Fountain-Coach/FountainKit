import SwiftUI

/// Left-hand score pane mock matching the Teatro Possibile reference.
struct TeatroScorePane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Teatro Possibile")
                .font(.system(size: 32, weight: .semibold, design: .serif))
                .foregroundColor(Color(red: 0.20, green: 0.18, blue: 0.16))
                .padding(.top, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color(red: 0.72, green: 0.68, blue: 0.62), lineWidth: 1)
                    .background(Color.clear)

                VStack(spacing: 24) {
                    ForEach(0..<6, id: \.self) { _ in
                        StaffSystemView()
                            .frame(height: 56)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 16)
            }
        }
        .padding(.horizontal, 24)
    }
}

/// One system of five staff lines.
private struct StaffSystemView: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let top = height * 0.15
            let gap = height * 0.12
            Path { path in
                for i in 0..<5 {
                    let y = top + CGFloat(i) * gap
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color(red: 0.55, green: 0.52, blue: 0.48), lineWidth: 0.8)
        }
    }
}

/// Right-hand script card: ACT/Scene strip + screenplay text.
struct TeatroScriptPane: View {
    let title: String
    let bodyText: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.98, green: 0.97, blue: 0.94))
                .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 8)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ACT 1")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.24, green: 0.22, blue: 0.20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.93, green: 0.91, blue: 0.88))
                    Divider()
                    Text("Scene 1")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(red: 0.24, green: 0.22, blue: 0.20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.95, green: 0.93, blue: 0.90))
                    Spacer()
                }
                .frame(width: 96)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black)
                    ScrollView {
                        Text(bodyText)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
    }
}

