import SwiftUI
import UIKit

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

public enum BrandColors {
    public static let mediaIndigo = Color(hex: 0x6366F1)
    public static let mediaViolet = Color(hex: 0x8B5CF6)
    public static let mediaCyan = Color(hex: 0x06B6D4)
    public static let mediaSky = Color(hex: 0x38BDF8)
    public static let mediaEmerald = Color(hex: 0x10B981)
    public static let mediaAmber = Color(hex: 0xF59E0B)

    // Platform Signature Colors
    public static let youTubeRed = Color(hex: 0xFF2E4D)
    public static let facebookBlue = Color(hex: 0x1877F2)
    public static let tikTokCyan = Color(hex: 0x00D9D0)

    public static let primaryGradientColors: [Color] = [
        Color(hex: 0x4F46E5),
        Color(hex: 0x7C3AED),
        Color(hex: 0x06B6D4)
    ]

    public static let ultraHdGradientColors: [Color] = [
        Color(hex: 0x6D28D9),
        Color(hex: 0xEC4899),
        Color(hex: 0xF59E0B)
    ]

    public static let hdGradientColors: [Color] = [
        Color(hex: 0x2563EB),
        Color(hex: 0x06B6D4)
    ]

    public static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: primaryGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var horizontalPrimaryGradient: LinearGradient {
        LinearGradient(
            colors: primaryGradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public static var ultraHdGradient: LinearGradient {
        LinearGradient(
            colors: ultraHdGradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public static var hdGradient: LinearGradient {
        LinearGradient(
            colors: hdGradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public static func platformAccent(_ platform: MediaPlatform) -> Color {
        switch platform {
        case .youtube: return youTubeRed
        case .facebook: return facebookBlue
        case .tiktok: return tikTokCyan
        }
    }
}

public struct AppPalette: Equatable, Sendable {
    public let isDark: Bool
    public let background: Color
    public let onBackground: Color
    public let surface: Color
    public let onSurface: Color
    public let surfaceVariant: Color
    public let onSurfaceVariant: Color
    public let outline: Color
    public let primary: Color
    public let onPrimary: Color
    public let primaryContainer: Color
    public let onPrimaryContainer: Color
    public let secondary: Color
    public let error: Color

    public static let dark = AppPalette(
        isDark: true,
        background: Color(hex: 0x0A0D16),
        onBackground: Color(hex: 0xF3F5FA),
        surface: Color(hex: 0x121726),
        onSurface: Color(hex: 0xF3F5FA),
        surfaceVariant: Color(hex: 0x1B2236),
        onSurfaceVariant: Color(hex: 0xA2ACC4),
        outline: Color(hex: 0x2D3753),
        primary: Color(hex: 0x818CF8),
        onPrimary: .white,
        primaryContainer: Color(hex: 0x1E2246),
        onPrimaryContainer: Color(hex: 0xE0E7FF),
        secondary: BrandColors.mediaCyan,
        error: Color(hex: 0xEF4444)
    )

    public static let light = AppPalette(
        isDark: false,
        background: Color(hex: 0xF5F7FC),
        onBackground: Color(hex: 0x0F172A),
        surface: Color(hex: 0xFFFFFF),
        onSurface: Color(hex: 0x0F172A),
        surfaceVariant: Color(hex: 0xEEF2FA),
        onSurfaceVariant: Color(hex: 0x475569),
        outline: Color(hex: 0xCBD5E1),
        primary: Color(hex: 0x4F46E5),
        onPrimary: .white,
        primaryContainer: Color(hex: 0xE0E7FF),
        onPrimaryContainer: Color(hex: 0x1E1B4B),
        secondary: Color(hex: 0x0891B2),
        error: Color(hex: 0xDC2626)
    )
}

private struct AppPaletteKey: EnvironmentKey {
    static let defaultValue: AppPalette = .dark
}

public extension EnvironmentValues {
    var appPalette: AppPalette {
        get { self[AppPaletteKey.self] }
        set { self[AppPaletteKey.self] = newValue }
    }
}
