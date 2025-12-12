import SwiftUI

// MARK: -- Desert Sands View

/// Фон пустыни с движущимися песчинками
struct DesertSandsView: View {
    let sandCount: Int
    let speed: Double
    
    @State private var sands: [SandGrain] = []
    
    // MARK: -- Sand Grain Model
    
    struct SandGrain: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                ForEach(sands) { sand in
                    Circle()
                        .fill(Color.white)
                        .frame(width: sand.size, height: sand.size)
                        .opacity(sand.opacity)
                        .position(x: sand.x, y: sand.y)
                }
            }
            .onAppear {
                generateSands(in: geometry.size)
                animateSands()
            }
        }
    }
    
    // MARK: - Private Functions
    
    private func generateSands(in size: CGSize) {
        sands = (0..<sandCount).map { _ in
            SandGrain(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 1...3),
                opacity: Double.random(in: 0.3...1.0)
            )
        }
    }
    
    private func animateSands() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.linear(duration: 0.1)) {
                for i in sands.indices {
                    sands[i] = SandGrain(
                        x: sands[i].x + CGFloat(speed),
                        y: sands[i].y,
                        size: sands[i].size,
                        opacity: sands[i].opacity
                    )
                    
                    // Перемещаем песчинки, которые вышли за границы экрана
                    // Используем большое значение для кроссплатформенности
                    if sands[i].x > 1000 {
                        sands[i] = SandGrain(
                            x: -10,
                            y: sands[i].y,
                            size: sands[i].size,
                            opacity: sands[i].opacity
                        )
                    }
                }
            }
        }
    }
}

