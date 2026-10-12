import Testing

@testable import ToggleDeck

struct LowPowerAuthorizationTests {
  @Test
  func approvedExactCommandsDoNotRequestAuthorization() {
    for value in [0, 1] {
      let command = "/usr/bin/pmset -a lowpowermode \(value)"
      var attempted: [String] = []
      var authorized = false
      let result = LowPowerAuthorization.run(
        command, reason: "Change Low Power Mode",
        noninteractive: {
          attempted.append($0)
          return ShellResult(status: 0, out: "applied", err: "notice")
        },
        authorize: { _, _ in
          authorized = true
          return ShellResult(status: 99, out: "unexpected")
        })
      #expect(attempted == ["LC_ALL=C /usr/bin/sudo -n -- \(command)"])
      #expect(!authorized)
      #expect(result.status == 0)
      #expect(result.out == "applied")
      #expect(result.err == "notice")
    }
  }

  @Test
  func deniedExistingPermissionRequestsAuthorizationWithOriginalCommandAndReason() {
    let command = "/usr/bin/pmset -a lowpowermode 1"
    let reason = "ToggleDeck needs authorization to change Low Power Mode."
    for message in [
      "sudo: a password is required",
      "sudo: user is not allowed to execute this command",
      "sudo: user may not run sudo on this host",
      "Sorry, user test is not allowed to execute this command",
    ] {
      var authorized: [(String, String)] = []
      let result = LowPowerAuthorization.run(
        command, reason: reason,
        noninteractive: { _ in ShellResult(status: 1, out: "", err: message) },
        authorize: {
          authorized.append(($0, $1))
          return ShellResult(status: 0, out: "authorized")
        })
      #expect(authorized.count == 1)
      #expect(authorized.first?.0 == command)
      #expect(authorized.first?.1 == reason)
      #expect(result.status == 0)
      #expect(result.out == "authorized")
    }
  }

  @Test
  func cancellationOfFallbackAuthorizationPropagatesUnchanged() {
    var authorizations = 0
    let result = LowPowerAuthorization.run(
      "/usr/bin/pmset -a lowpowermode 0", reason: "Change Low Power Mode",
      noninteractive: { _ in
        ShellResult(status: 1, out: "", err: "sudo: a password is required")
      },
      authorize: { _, _ in
        authorizations += 1
        return ShellResult(status: -3, out: "", err: "cancelled")
      })
    #expect(authorizations == 1)
    #expect(result.status == -3)
    #expect(result.out.isEmpty)
    #expect(result.err == "cancelled")
  }

  @Test
  func modifiedOrInjectedCommandsNeverUseExistingPermissionPath() {
    for command in [
      "/usr/bin/pmset -a lowpowermode 1 -b",
      "/usr/bin/pmset -a lowpowermode 1; /usr/bin/id",
      "/usr/bin/pmset -a lowpowermode 1 && /usr/bin/id",
      "/usr/bin/pmset -a lowpowermode 1\n/usr/bin/id",
      "/usr/bin/pmset -a lowpowermode $(/usr/bin/id)",
      "/usr/bin/pmset -b lowpowermode 1",
      "/usr/bin/pmset -a lowpowermode 2",
      "/usr/bin/pmset -a lowpowermode 1 ",
      "pmset -a lowpowermode 1",
      "/usr/bin/defaults write example enabled -bool true",
    ] {
      var attempts = 0
      var authorized: [String] = []
      let result = LowPowerAuthorization.run(
        command, reason: "Original reason",
        noninteractive: { _ in
          attempts += 1
          return ShellResult(status: 0, out: "unexpected")
        },
        authorize: { receivedCommand, reason in
          authorized.append(receivedCommand)
          #expect(reason == "Original reason")
          return ShellResult(status: -3, out: "", err: "cancelled")
        })
      #expect(attempts == 0)
      #expect(authorized == [command])
      #expect(result.status == -3)
    }
  }

  @Test
  func commandFailuresAndProcessFailuresDoNotTriggerAnotherPrompt() {
    for failure in [
      ShellResult(status: 1, out: "partial output", err: "pmset: setting is not supported"),
      ShellResult(status: 2, out: "", err: "invalid argument"),
      ShellResult(status: -2, out: "", err: "timed out after 20.0s"),
      ShellResult(status: -1, out: "", err: "spawn failed (1)"),
      ShellResult(status: -4, out: "", err: "process terminated"),
    ] {
      var authorized = false
      let result = LowPowerAuthorization.run(
        "/usr/bin/pmset -a lowpowermode 1", reason: "Change Low Power Mode",
        noninteractive: { _ in failure },
        authorize: { _, _ in
          authorized = true
          return ShellResult(status: 0, out: "unexpected")
        })
      #expect(!authorized)
      #expect(result.status == failure.status)
      #expect(result.out == failure.out)
      #expect(result.err == failure.err)
    }
  }

  @Test
  func onlySudoAuthorizationErrorsWithExpectedExitStatusPermitFallback() {
    for failure in [
      ShellResult(status: 1, out: "", err: "pmset: a password is required"),
      ShellResult(status: 1, out: "sudo: a password is required", err: ""),
      ShellResult(status: 1, out: "", err: "sudo: command not found"),
      ShellResult(status: 2, out: "", err: "sudo: a password is required"),
      ShellResult(status: -2, out: "", err: "sudo: a password is required"),
    ] {
      var authorized = false
      let result = LowPowerAuthorization.run(
        "/usr/bin/pmset -a lowpowermode 0", reason: "Change Low Power Mode",
        noninteractive: { _ in failure },
        authorize: { _, _ in
          authorized = true
          return ShellResult(status: 0, out: "unexpected")
        })
      #expect(!authorized)
      #expect(result.status == failure.status)
      #expect(result.out == failure.out)
      #expect(result.err == failure.err)
    }
  }

  @Test
  func lowPowerInterfaceExplainsConditionalAuthorization() throws {
    let spec = try #require(Catalog.all.first { $0.id == "lowPowerMode" })
    #expect(spec.menuSubtitle(showDescriptions: false) == "May request authorization")
    #expect(spec.requires.badges.map(\.0).contains("Administrator access"))
    #expect(spec.menuHelp.contains("Administrator access"))
    #expect(!spec.menuHelp.contains("Password required"))
  }
}
