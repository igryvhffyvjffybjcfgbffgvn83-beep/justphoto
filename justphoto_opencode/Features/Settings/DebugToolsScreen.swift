#if DEBUG

import SwiftUI

struct DebugToolsScreen: View {
    var body: some View {
        List {
            Section("Debug Tools") {
                Button("DebugToolsPing") {
                    print("DebugToolsPing")
                }

                Text("Debug-only tools live here")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debug Tools")
    }
}

#Preview {
    NavigationStack { DebugToolsScreen() }
}

#endif
