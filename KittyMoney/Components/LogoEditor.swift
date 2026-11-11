import SwiftUI
import PhotosUI
import UIKit

/// Form section for setting an item's logo: fetch from a website or pick an image.
struct LogoEditor: View {
    let name: String
    let colorHex: String
    @Binding var logoData: Data?
    @Binding var domain: String
    /// Called when the user sets or removes the logo themselves, so automatic fetching stops overriding it.
    var onManualChange: () -> Void = {}

    @State private var photoItem: PhotosPickerItem?
    @State private var isFetching = false
    @State private var fetchFailed = false

    var body: some View {
        Section {
            HStack(spacing: 14) {
                LogoTile(name: name.isEmpty ? "?" : name, colorHex: colorHex, logoData: logoData, size: 52)
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose image", systemImage: "photo")
                    }
                    .buttonStyle(.borderless)
                    if logoData != nil {
                        Button(role: .destructive) {
                            logoData = nil
                            onManualChange()
                        } label: {
                            Label("Remove logo", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.vertical, 4)

            HStack {
                TextField("Website, e.g. netflix.com", text: $domain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await fetchLogo() }
                } label: {
                    if isFetching {
                        ProgressView()
                    } else {
                        Text("Fetch")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
            }
        } header: {
            Text("Logo")
        } footer: {
            Text(fetchFailed
                 ? "Couldn't find a good logo for that site. Try choosing an image instead."
                 : "Fetch the logo from the website, or choose your own image.")
        }
        .listRowBackground(Theme.card)
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    private func fetchLogo() async {
        isFetching = true
        fetchFailed = false
        let data = await LogoFetcher.fetch(domain: domain, force: true)
        isFetching = false
        if let data {
            logoData = data
            onManualChange()
        } else {
            fetchFailed = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        logoData = image.fitted(in: 256).pngData()
        onManualChange()
    }
}

/// Grid of tile colors to choose from.
struct ColorSwatchPicker: View {
    @Binding var selection: String

    static let palette = [
        "#B8860B", "#1E4FA8", "#A3262B", "#1F4D35", "#5A1A1E",
        "#2D3A55", "#3A3A42", "#6B3FA0", "#0F6E6E", "#8A4B12"
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
            ForEach(Self.palette, id: \.self) { hex in
                Button {
                    selection = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 34, height: 34)
                        .padding(4)
                        .overlay(
                            Circle().strokeBorder(Theme.accentText, lineWidth: selection == hex ? 2.5 : 0)
                        )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Tile color")
                .accessibilityAddTraits(selection == hex ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}
