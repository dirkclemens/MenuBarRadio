//
//  ClickableURLView.swift
//  MenuBarRadio
//

import Foundation
import SwiftUI

struct ClickableURLView: View {
    let title: String
    let url: String
    
    init(title: String, url: String) {
        self.title = title
        self.url = url
    }
    
    var body: some View {
        Group {
            HStack {
                Text(" (\(url.lowercased()))")
                    .foregroundColor(.blue)
                    .underline()
            }
        }
        .background(
            Link(destination: URL(string: url)!) {
                EmptyView()
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: url) {
                #if os(iOS)
                UIApplication.shared.open(url)
                #elseif os(macOS)
                NSWorkspace.shared.open(url)
                #endif
            }
        }
    }
}
