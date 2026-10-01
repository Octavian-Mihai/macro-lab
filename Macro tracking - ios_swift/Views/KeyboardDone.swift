import SwiftUI

extension View {
    /// Adds a "Done" button above the keyboard. Number pads have no return key,
    /// so without this there is no way to close the keyboard.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .bold()
            }
        }
    }
}
