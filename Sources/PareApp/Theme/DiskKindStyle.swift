import SwiftUI
import PareCore

/// Tile swatch and symbol for a Disk Analyzer `DiskKind`.
///
/// Folder uses `accentDeep` (plain `accent`'s dark-mode seafoam is too light for a white
/// glyph, ~2:1); every other kind reuses a `CategoryStyle` hue so the palette stays one system.
enum DiskKindStyle {
    // MARK: - Swatch (light/dark tile fill)

    static func swatch(for kind: DiskKind) -> ThemeSwatch {
        switch kind {
        case .folder:
            return AppTheme.Swatch.accentDeep
        case .application:
            return CategoryStyle.swatch(for: .applications)
        case .image:
            return CategoryStyle.swatch(for: .designerCaches)
        case .video:
            return CategoryStyle.swatch(for: .videoBuilderCaches)
        case .audio:
            return CategoryStyle.swatch(for: .aiToolCaches)
        case .document:
            return CategoryStyle.swatch(for: .productivityCaches)
        case .archive:
            return CategoryStyle.swatch(for: .developerPackageCaches)
        case .diskImage:
            return CategoryStyle.swatch(for: .deviceBackups)
        case .other:
            return CategoryStyle.swatch(for: .launchAgents)
        }
    }

    // MARK: - Symbol

    static func symbol(for kind: DiskKind) -> String {
        switch kind {
        case .folder: return "folder.fill"
        case .application: return "app.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "waveform"
        case .document: return "doc.text.fill"
        case .archive: return "doc.zipper"
        case .diskImage: return "externaldrive.fill"
        case .other: return "doc.fill"
        }
    }

    // MARK: - Tint

    /// Tint for a `DiskKind` — convenience for callers that only need the resolved `Color`.
    static func tint(for kind: DiskKind) -> Color {
        swatch(for: kind).color
    }

    // MARK: - Combined (for closure-typed call sites, e.g. `DiskAnalyzerTable.kindStyle`)

    static func style(for kind: DiskKind) -> (symbol: String, swatch: ThemeSwatch) {
        (symbol(for: kind), swatch(for: kind))
    }
}
