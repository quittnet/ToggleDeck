import SwiftUI

// The macOS 27 SDK also exports a State macro. Name the existing property
// wrapper explicitly so Command Line Tools builds need no SwiftUI macro plugin.
typealias ViewState<Value> = SwiftUI.State<Value>
