import Foundation
import Testing
import VortexPlatform

@testable import FeatureSecrets

struct KeyCommandTests {
  @Test
  func placeholdersBecomeShellVariablesInTheOrderTheyComeIn() {
    let command = KeyCommand(#"psql "{{Prod-DB}}" -c 'select 1' && curl -H "Authorization: Bearer {{ github }}" x && echo {{prod-db}}"#)
    #expect(command.names == ["prod-db", "github"])
    #expect(command.shellCommand == #"psql "${VORTEX_KEY_1}" -c 'select 1' && curl -H "Authorization: Bearer ${VORTEX_KEY_2}" x && echo ${VORTEX_KEY_1}"#)
    #expect(
      command.environment(values: ["prod-db": "postgres://u:p@h/db", "github": "ghp_x"])
        == ["VORTEX_KEY_1": "postgres://u:p@h/db", "VORTEX_KEY_2": "ghp_x"]
    )
    #expect(KeyCommand("ls -la {{}} {{ two words }}").names.isEmpty)
  }

  @Test
  func valuesAreTakenOutOfTheOutputAlsoEncodedAndThePasswordOnItsOwn() {
    let value = "postgres://admin:hunter2secret@db.example.com:5432/app"
    let base64 = Data(value.utf8).base64EncodedString()
    let text = """
      connecting to \(value)
      password hunter2secret was refused
      in base64 \(base64)
      encoded \(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
      """
    let masked = KeyCommand.masked(text, values: ["prod-db": value])
    #expect(masked.contains("connecting to {{prod-db}}"))
    #expect(masked.contains("password {{prod-db}} was refused"))
    #expect(!masked.contains("hunter2secret"))
    #expect(!masked.contains(base64))
    #expect(!masked.contains("postgres%3A"))
    // Too short to take out without taking out ordinary words.
    #expect(KeyCommand.masked("abc def", values: ["k": "abc"]) == "abc def")
  }

  @Test
  func whatToolsPrintByAccidentIsTakenOutToo() {
    // A connection URL writes the password's signs encoded; tools print it decoded, or encoded again their own way.
    let value = "postgres://admin:p4ss%2Fw%26rd-x_y~z@db.example.com/app"
    let basic = Data("admin:p4ss/w&rd-x_y~z".utf8).base64EncodedString()
    let text = """
      > Authorization: Basic \(basic)
      {"url":"postgres:\\/\\/admin:p4ss%2Fw%26rd-x_y~z@db.example.com\\/app","password":"p4ss\\/w\\u0026rd-x_y~z"}
      password=p4ss%2Fw%26rd-x_y~z
      """
    let masked = KeyCommand.masked(text, values: ["db": value])
    #expect(!masked.contains(basic))
    #expect(!masked.contains("w\\u0026rd"))
    #expect(!masked.contains("p4ss%2Fw"))
    #expect(!masked.contains("db.example.com\\/app"))
    #expect(masked.contains("Authorization: Basic {{db}}"))
  }

  @Test
  func anOutputCutAtTheLimitLosesItsTailSoNoPieceOfAValueIsLeft() {
    let value = "s3cret-value-1234567890"
    let filler = Data(repeating: 46, count: CommandClient.outputLimit - 10)
    let output = CommandClient.Output(exitCode: 0, stdout: filler + Data(value.prefix(10).utf8))
    let report = KeyCommand.report(output, values: ["k": value], timeout: 60, limit: CommandClient.outputLimit * 2)
    #expect(!report.contains("s3cret-val"))
  }

  @Test
  func theReportSaysHowItEndedWithTheValuesTakenOut() {
    let output = CommandClient.Output(exitCode: 2, stdout: Data("rows: s3cretvalue\n".utf8), stderr: Data("warning\n".utf8))
    let report = KeyCommand.report(output, values: ["db": "s3cretvalue"], timeout: 60)
    #expect(report.hasPrefix("exit code 2"))
    #expect(report.contains("rows: {{db}}"))
    #expect(report.contains("--- stderr ---\nwarning"))
    let stopped = KeyCommand.report(CommandClient.Output(exitCode: 143, timedOut: true), values: [:], timeout: 5)
    #expect(stopped.hasPrefix("stopped after 5 s"))
    #expect(stopped.contains("(no output)"))
  }

  @Test
  func longOutputKeepsItsStartAndItsEnd() {
    let text = String(repeating: "a", count: 60) + String(repeating: "z", count: 40)
    let cut = KeyCommand.cut(text, to: 40)
    #expect(cut.hasPrefix(String(repeating: "a", count: 30)))
    #expect(cut.hasSuffix(String(repeating: "z", count: 10)))
    #expect(cut.contains("60 characters left out"))
    #expect(KeyCommand.cut("short", to: 40) == "short")
  }
}

struct KeyKindTests {
  @Test
  func theKindIsToldByHowTheValueStarts() {
    #expect(KeyKind(value: "postgresql://u:p@h/db") == .postgres)
    #expect(KeyKind(value: " mysql://root@localhost/app ") == .mysql)
    #expect(KeyKind(value: "mongodb+srv://u:p@cluster.mongodb.net") == .mongodb)
    #expect(KeyKind(value: "rediss://default:p@host:6379") == .redis)
    #expect(KeyKind(value: "ghp_abcdefghijklmnopqrstuvwxyz0123456789") == .github)
    #expect(KeyKind(value: "sk-ant-api03-xyz") == .anthropic)
    #expect(KeyKind(value: "sk-proj-abc") == .openai)
    #expect(KeyKind(value: "xoxb-123-456") == .slack)
    #expect(KeyKind(value: "AKIAIOSFODNN7EXAMPLE") == .aws)
    #expect(KeyKind(value: "sk_live_abc") == .stripe)
    #expect(KeyKind(value: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln") == .jwt)
    #expect(KeyKind(value: "-----BEGIN OPENSSH PRIVATE KEY-----") == .privateKey)
    #expect(KeyKind(value: "https://user:pass@example.com") == .url)
    #expect(KeyKind(value: "correct horse battery staple") == .secret)
  }

  @Test
  func namesAreWhatPlaceholdersHold() {
    #expect(SecretKey.isValidName("prod-db"))
    #expect(SecretKey.isValidName("api.v2_Token"))
    #expect(!SecretKey.isValidName("prod db"))
    #expect(!SecretKey.isValidName("-db"))
    #expect(!SecretKey.isValidName("{{db}}"))
    #expect(!SecretKey.isValidName(""))
  }
}
