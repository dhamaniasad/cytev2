//
//  RippleEffect.swift
//  Cyte
//
//  Created by Shaun Narayan on 14/03/23.
//

import Foundation
import SwiftUI

struct RippleEffectView: View {
    @State private var firstCircle = 1.0
    @State private var secondCircle = 1.0
    @State private var strokeColor = Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0)
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(strokeColor)
                .scaleEffect(firstCircle)
                .opacity(2 - firstCircle)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                        firstCircle = 3
                    }
                }
            
            Circle()
                .stroke(strokeColor)
                .scaleEffect(secondCircle)
                .opacity(2 - secondCircle)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                        secondCircle = 2
                    }
                }
        }
    }
}
