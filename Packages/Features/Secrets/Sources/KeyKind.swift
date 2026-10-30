import Foundation
import SwiftUI

/// What a key is, told by how its value starts: shown next to its name, and given to Claude.
public enum KeyKind: String, Codable, CaseIterable, Sendable {
  case postgres
  case mysql
  case mongodb
  case redis
  case github
  case anthropic
  case openai
  case slack
  case aws
  case stripe
  case jwt
  case privateKey
  case url
  case secret

  public init(value: String) {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = value.lowercased()
    func starts(_ prefixes: String...) -> Bool { prefixes.contains { lower.hasPrefix($0) } }
    func startsExactly(_ prefixes: String...) -> Bool { prefixes.contains { value.hasPrefix($0) } }
    self = if starts("postgres://", "postgresql://") {
      .postgres
    } else if starts("mysql://", "mariadb://") {
      .mysql
    } else if starts("mongodb://", "mongodb+srv://") {
      .mongodb
    } else if starts("redis://", "rediss://") {
      .redis
    } else if startsExactly("ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_") {
      .github
    } else if startsExactly("sk-ant-") {
      .anthropic
    } else if startsExactly("sk-") {
      .openai
    } else if startsExactly("xoxb-", "xoxp-", "xoxa-", "xapp-") {
      .slack
    } else if startsExactly("AKIA", "ASIA"), value.count == 20 {
      .aws
    } else if startsExactly("sk_live_", "sk_test_", "rk_live_", "rk_test_") {
      .stripe
    } else if startsExactly("eyJ"), value.split(separator: ".").count == 3 {
      .jwt
    } else if startsExactly("-----BEGIN") {
      .privateKey
    } else if starts("https://", "http://") {
      .url
    } else {
      .secret
    }
  }

  /// For Claude: what the value is and what reads it, in English.
  var summary: String {
    switch self {
    case .postgres: "PostgreSQL connection URL (psql)"
    case .mysql: "MySQL connection URL (mysql)"
    case .mongodb: "MongoDB connection string (mongosh)"
    case .redis: "Redis URL (redis-cli -u)"
    case .github: "GitHub token (gh, or the API with curl)"
    case .anthropic: "Anthropic API key (x-api-key header)"
    case .openai: "OpenAI API key (Authorization: Bearer)"
    case .slack: "Slack token (Authorization: Bearer)"
    case .aws: "AWS access key id"
    case .stripe: "Stripe API key"
    case .jwt: "JWT (Authorization: Bearer)"
    case .privateKey: "private key (PEM)"
    case .url: "URL with credentials"
    case .secret: "token or password"
    }
  }

  /// A name to offer when the user gives none.
  var suggestedName: String {
    switch self {
    case .postgres: "postgres"
    case .mysql: "mysql"
    case .mongodb: "mongodb"
    case .redis: "redis"
    case .github: "github"
    case .anthropic: "anthropic"
    case .openai: "openai"
    case .slack: "slack"
    case .aws: "aws"
    case .stripe: "stripe"
    case .jwt: "jwt"
    case .privateKey: "private-key"
    case .url: "url"
    case .secret: "key"
    }
  }

  /// For the list: «PostgreSQL», «GitHub token»…
  var title: Text {
    switch self {
    case .postgres: Text(verbatim: "PostgreSQL")
    case .mysql: Text(verbatim: "MySQL")
    case .mongodb: Text(verbatim: "MongoDB")
    case .redis: Text(verbatim: "Redis")
    case .github: Text("GitHub token", bundle: .module)
    case .anthropic: Text("Anthropic API key", bundle: .module)
    case .openai: Text("OpenAI API key", bundle: .module)
    case .slack: Text("Slack token", bundle: .module)
    case .aws: Text("AWS access key", bundle: .module)
    case .stripe: Text("Stripe key", bundle: .module)
    case .jwt: Text(verbatim: "JWT")
    case .privateKey: Text("Private key", bundle: .module)
    case .url: Text("Link with access", bundle: .module)
    case .secret: Text("Token or password", bundle: .module)
    }
  }

  var symbol: String {
    switch self {
    case .postgres, .mysql, .mongodb, .redis: "cylinder.split.1x2"
    case .privateKey: "lock.doc"
    case .url: "link"
    case .jwt: "person.badge.key"
    default: "key.horizontal"
    }
  }
}
