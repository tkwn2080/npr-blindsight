//
//  ContentView.swift
//  NPR Blindsight
//
//  Created by bird on 3/16/23.
//

import SwiftUI
import AVKit

struct ContentView: View {
    var body: some View {
        CameraViewController()
            .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
