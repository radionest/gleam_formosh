import formosh/validation/messages
import gleeunit/should

pub fn required_format_test() {
  messages.format(messages.Required)
  |> should.equal("This field is required")
}

pub fn required_rule_test() {
  messages.rule_of(messages.Required)
  |> should.equal("required")
}

pub fn min_length_format_test() {
  messages.format(messages.MinLength(3))
  |> should.equal("Must be at least 3 characters")
}

pub fn min_length_rule_test() {
  messages.rule_of(messages.MinLength(3))
  |> should.equal("minLength")
}

pub fn invalid_email_format_test() {
  messages.format(messages.InvalidEmail)
  |> should.equal("Invalid email address")
}

pub fn invalid_type_string_format_test() {
  messages.format(messages.InvalidType("string"))
  |> should.equal("Must be a string")
}

pub fn invalid_type_number_format_test() {
  messages.format(messages.InvalidType("number"))
  |> should.equal("Must be a number")
}

pub fn invalid_type_rule_test() {
  messages.rule_of(messages.InvalidType("string"))
  |> should.equal("type")
}

pub fn minimum_format_test() {
  messages.format(messages.Minimum(5.0))
  |> should.equal("Must be at least 5.0")
}

pub fn minimum_rule_test() {
  messages.rule_of(messages.Minimum(5.0))
  |> should.equal("minimum")
}
