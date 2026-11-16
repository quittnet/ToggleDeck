import Testing

@testable import ToggleDeck

struct DarkModeTests {
  @Test
  func automationDenialIsRecognizedOnEitherOutputStream() {
    let guidance =
      "Grant ToggleDeck permission to control System Events under Privacy & Security → Automation."
    for result in [
      ShellResult(status: 1, out: "", err: "Not authorized to send Apple events. (-1743)"),
      ShellResult(status: 1, out: "Not allowed to send Apple events."),
      ShellResult(status: 1, out: "partial output", err: "execution error: (-1743)"),
    ] {
      #expect(Bridges.darkModeError(result) == guidance)
    }
  }

  @Test
  func otherFailuresPreserveShellDiagnostics() {
    #expect(
      Bridges.darkModeError(ShellResult(status: 1, out: "", err: "System Events is unavailable"))
        == "System Events is unavailable")
    #expect(
      Bridges.darkModeError(ShellResult(status: 1, out: "Unexpected response"))
        == "Unexpected response")
    #expect(
      Bridges.darkModeError(ShellResult(status: 1, out: "")) == "Appearance change failed.")
  }

  @Test
  func timeoutPointsAtTheAutomationPrompt() {
    #expect(
      Bridges.darkModeError(ShellResult(status: -2, out: "", err: "timed out after 120.0s"))
        == "macOS did not answer in time. If an Automation prompt is open, choose Allow, then try again."
    )
  }

  @Test
  func successfulChangeIgnoresIncidentalDiagnostics() {
    #expect(Bridges.darkModeError(ShellResult(status: 0, out: "", err: "notice")) == nil)
  }
}
