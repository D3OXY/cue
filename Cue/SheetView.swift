import SwiftUI

/// Placeholder sheet content. Layout per SPEC (search top, list, composer bottom)
/// and Liquid Glass treatment land with ticket 5.
struct SheetView: View {
    var body: some View {
        VStack {
            Text("Cue")
                .font(.title2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(8)
    }
}
