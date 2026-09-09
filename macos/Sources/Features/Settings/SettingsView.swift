import SwiftUI

struct SettingsView: View {
    // We need access to our app delegate to know if we're quitting or not.
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        HStack(spacing: 20) {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 10) {
                Text("Ghostty Configuration Studio")
                    .font(.headline)

                Text("Browse themes, customize fonts, adjust window appearance, cursor, and terminal behavior interactively.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)

                HStack(spacing: 12) {
                    Button(action: {
                        appDelegate.openConfigStudio(nil)
                    }) {
                        Label("Launch Configuration Studio", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        appDelegate.openConfig(nil)
                    }) {
                        Label("Edit Config File", systemImage: "doc.text")
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 540, maxWidth: 560, minHeight: 160, maxHeight: 180)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
