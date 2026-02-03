//
//  ContentView.swift
//  justphoto_opencode
//
//  Created by 番茄 on 1/2/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraScreen()
    }
}

#Preview {
    ContentView()
        .environmentObject(PromptCenter())
}
