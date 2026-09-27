import SwiftUI
import PareCore

/// Search field plus Kind and Size menu pickers for the current Disk Analyzer level.
struct DiskFilterBar: View {
    @Binding var search: String
    @Binding var kindFilter: DiskKind?
    @Binding var sizeFloor: DiskSizeFloor
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 12) {
            searchField
            kindPicker
            sizePicker
            Spacer(minLength: 0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textSecondary)
                .font(scale.caption)
            TextField("Search this folder", text: $search)
                .textFieldStyle(.plain)
                .font(scale.body)
                .foregroundStyle(AppTheme.textPrimary)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.Fill.subtle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .frame(maxWidth: 280)
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $kindFilter) {
            Text("Any Kind").tag(DiskKind?.none)
            ForEach(DiskKind.allCases, id: \.self) { kind in
                Text(Self.label(for: kind)).tag(DiskKind?.some(kind))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(scale.caption)
        .fixedSize()
    }

    private var sizePicker: some View {
        Picker("Size", selection: $sizeFloor) {
            ForEach(DiskSizeFloor.allCases, id: \.self) { floor in
                Text(Self.label(for: floor)).tag(floor)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(scale.caption)
        .fixedSize()
    }

    private static func label(for kind: DiskKind) -> String {
        switch kind {
        case .folder: return "Folder"
        case .application: return "Application"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .archive: return "Archive"
        case .diskImage: return "Disk Image"
        case .other: return "Other"
        }
    }

    private static func label(for floor: DiskSizeFloor) -> String {
        switch floor {
        case .any: return "Any Size"
        case .oneMB: return "\u{2265} 1 MB"
        case .oneHundredMB: return "\u{2265} 100 MB"
        case .oneGB: return "\u{2265} 1 GB"
        }
    }
}

#if DEBUG
private struct DiskFilterBarPreviewHost: View {
    @State private var search = ""
    @State private var kindFilter: DiskKind?
    @State private var sizeFloor: DiskSizeFloor = .any

    var body: some View {
        DiskFilterBar(search: $search, kindFilter: $kindFilter, sizeFloor: $sizeFloor)
            .padding(24)
    }
}

struct DiskFilterBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DiskFilterBarPreviewHost()
                .environment(\.colorScheme, .light)
                .background(AppTheme.base)
                .previewDisplayName("Light")
            DiskFilterBarPreviewHost()
                .environment(\.colorScheme, .dark)
                .background(AppTheme.base)
                .previewDisplayName("Dark")
        }
    }
}
#endif
