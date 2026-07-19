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

pub fn pattern_mismatch_format_test() {
  messages.format(messages.PatternMismatch)
  |> should.equal("Does not match the required format")
}

pub fn pattern_mismatch_rule_test() {
  messages.rule_of(messages.PatternMismatch)
  |> should.equal("pattern")
}

pub fn min_items_format_test() {
  messages.format(messages.MinItems(2))
  |> should.equal("At least 2 item(s) required")
}

pub fn min_items_rule_test() {
  messages.rule_of(messages.MinItems(2))
  |> should.equal("minItems")
}

pub fn max_items_format_test() {
  messages.format(messages.MaxItems(5))
  |> should.equal("At most 5 item(s) allowed")
}

pub fn max_items_rule_test() {
  messages.rule_of(messages.MaxItems(5))
  |> should.equal("maxItems")
}

pub fn multiple_of_format_test() {
  messages.format(messages.MultipleOf(5.0))
  |> should.equal("Must be a multiple of 5.0")
}

pub fn multiple_of_rule_test() {
  messages.rule_of(messages.MultipleOf(5.0))
  |> should.equal("multipleOf")
}
