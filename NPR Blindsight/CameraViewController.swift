//
//  CameraViewController.swift
//  NPR Blindsight
//
//  Created by bird on 3/16/23.
//

import Foundation
import SwiftUI
import UIKit

struct CameraViewController: UIViewControllerRepresentable {
    typealias UIViewControllerType = ViewController

    func makeUIViewController(context: Context) -> ViewController {
        return ViewController()
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
    }
}
