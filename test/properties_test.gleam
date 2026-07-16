// Unit tests for formosh/schema/properties — the order-preserving
// key/value wrapper over JSON Schema's `properties` list.

import formosh/schema/properties
import formosh/schema/types.{type SchemaProperty, SchemaProperty, empty_property}
import gleam/option.{None, Some}
import gleeunit/should

fn prop(title: String) -> SchemaProperty {
  SchemaProperty(..empty_property(), title: Some(title))
}

fn entries() -> List(#(String, SchemaProperty)) {
  [#("alpha", prop("a")), #("beta", prop("b")), #("gamma", prop("g"))]
}

// get -------------------------------------------------------------------

pub fn get_existing_returns_some_test() {
  properties.get(entries(), "beta")
  |> should.equal(Some(prop("b")))
}

pub fn get_missing_returns_none_test() {
  properties.get(entries(), "missing") |> should.equal(None)
}

pub fn get_on_empty_returns_none_test() {
  properties.get([], "alpha") |> should.equal(None)
}

// has_key ---------------------------------------------------------------

pub fn has_key_existing_test() {
  properties.has_key(entries(), "alpha") |> should.be_true
}

pub fn has_key_missing_test() {
  properties.has_key(entries(), "missing") |> should.be_false
}

pub fn has_key_on_empty_test() {
  properties.has_key([], "alpha") |> should.be_false
}

// keys ------------------------------------------------------------------

pub fn keys_preserves_declared_order_test() {
  properties.keys(entries()) |> should.equal(["alpha", "beta", "gamma"])
}

pub fn keys_on_empty_test() {
  properties.keys([]) |> should.equal([])
}

// to_list / from_pairs --------------------------------------------------

pub fn to_list_is_identity_test() {
  let xs = entries()
  properties.to_list(xs) |> should.equal(xs)
}

pub fn from_pairs_round_trip_test() {
  let xs = entries()
  xs |> properties.from_pairs |> properties.to_list |> should.equal(xs)
}

// merge -----------------------------------------------------------------

pub fn merge_empty_base_yields_additions_test() {
  let additions = [#("x", prop("x"))]
  properties.merge([], additions) |> should.equal(additions)
}

pub fn merge_empty_additions_yields_base_test() {
  let base = entries()
  properties.merge(base, []) |> should.equal(base)
}

pub fn merge_appends_new_keys_at_end_test() {
  let base = [#("alpha", prop("a")), #("beta", prop("b"))]
  let additions = [#("gamma", prop("g")), #("delta", prop("d"))]
  properties.merge(base, additions)
  |> properties.keys
  |> should.equal(["alpha", "beta", "gamma", "delta"])
}

pub fn merge_override_keeps_position_and_updates_value_test() {
  let base = [
    #("alpha", prop("a")),
    #("beta", prop("b")),
    #("gamma", prop("g")),
  ]
  let additions = [#("beta", prop("B-overridden"))]
  let merged = properties.merge(base, additions)

  merged |> properties.keys |> should.equal(["alpha", "beta", "gamma"])
  properties.get(merged, "beta") |> should.equal(Some(prop("B-overridden")))
}

pub fn merge_dedups_duplicate_keys_in_additions_test() {
  let base = [#("alpha", prop("a"))]
  // Two entries for "x" — dedup must keep the first.
  let additions = [
    #("x", prop("first")),
    #("y", prop("y")),
    #("x", prop("second")),
  ]
  let merged = properties.merge(base, additions)

  merged |> properties.keys |> should.equal(["alpha", "x", "y"])
  properties.get(merged, "x") |> should.equal(Some(prop("first")))
}

pub fn merge_override_with_duplicate_in_additions_test() {
  let base = [#("alpha", prop("a")), #("beta", prop("b"))]
  let additions = [#("beta", prop("first")), #("beta", prop("second"))]
  let merged = properties.merge(base, additions)

  merged |> properties.keys |> should.equal(["alpha", "beta"])
  properties.get(merged, "beta") |> should.equal(Some(prop("first")))
}

// merge_with --------------------------------------------------------------

pub fn merge_with_combines_collisions_test() {
  let base = [
    #(
      "name",
      types.SchemaProperty(..types.empty_property(), title: Some("Base")),
    ),
    #("age", types.empty_property()),
  ]
  let additions = [
    #(
      "name",
      types.SchemaProperty(
        ..types.empty_property(),
        description: Some("from additions"),
      ),
    ),
    #("email", types.empty_property()),
  ]
  let combine = fn(old: types.SchemaProperty, new: types.SchemaProperty) {
    types.SchemaProperty(..old, description: new.description)
  }
  let merged = properties.merge_with(base, additions, combine)

  properties.keys(merged) |> should.equal(["name", "age", "email"])
  let assert Some(name) = properties.get(merged, "name")
  name.title |> should.equal(Some("Base"))
  name.description |> should.equal(Some("from additions"))
}

pub fn merge_with_dedups_additions_test() {
  let additions = [
    #(
      "dup",
      types.SchemaProperty(..types.empty_property(), title: Some("first")),
    ),
    #(
      "dup",
      types.SchemaProperty(..types.empty_property(), title: Some("second")),
    ),
  ]
  let merged = properties.merge_with([], additions, fn(_old, new) { new })
  properties.keys(merged) |> should.equal(["dup"])
  let assert Some(dup) = properties.get(merged, "dup")
  dup.title |> should.equal(Some("first"))
}
