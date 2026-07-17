// Tests for JSON Schema $ref and $defs support

import formosh/schema/parser
import formosh/schema/resolver
import formosh/schema/types
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should

// ---- Test helpers for the conditional/$ref test cases below ----

/// Parse a schema that carries a single top-level `allOf` / `if/then/else`
/// rule and return that rule. Panics if there isn't exactly one.
fn top_level_rule(json: String) -> types.ConditionalRule {
  let assert Ok(schema) = parser.parse_schema(json)
  let assert [rule] = schema.conditionals
  rule
}

/// Look up a property by name inside a conditional branch
/// (`rule.then_schema` / `rule.else_schema`, or `Some(rule.if_schema)`).
/// Asserts that the branch is `Some`, its `properties` is `Some`, and the
/// key is present. Returns the resolved `SchemaProperty`.
fn assert_branch_property(
  branch: Option(types.SchemaProperty),
  key: String,
) -> types.SchemaProperty {
  let assert Some(branch_schema) = branch
  let assert Some(props) = branch_schema.properties
  let assert Ok(prop) = list.key_find(props, key)
  prop
}

/// Test simple $ref to a definition in $defs
pub fn simple_ref_test() {
  let json =
    "{
    \"title\": \"Person Form\",
    \"type\": \"object\",
    \"properties\": {
      \"billing_address\": {
        \"$ref\": \"#/$defs/address\"
      },
      \"shipping_address\": {
        \"$ref\": \"#/$defs/address\"
      }
    },
    \"required\": [\"billing_address\"],
    \"$defs\": {
      \"address\": {
        \"type\": \"object\",
        \"properties\": {
          \"street\": {
            \"type\": \"string\",
            \"minLength\": 1
          },
          \"city\": {
            \"type\": \"string\",
            \"minLength\": 1
          },
          \"zip\": {
            \"type\": \"string\",
            \"pattern\": \"^\\\\d{5}$\"
          }
        },
        \"required\": [\"street\", \"city\", \"zip\"]
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, Some("Person Form"))

      // Check that both address properties have been resolved
      case list.key_find(schema.properties, "billing_address") {
        Ok(billing) -> {
          // The ref should be resolved and cleared
          should.equal(billing.ref, None)
          should.equal(billing.field_type, Some(types.ObjectType))

          // Check nested properties exist
          case billing.properties {
            Some(props) -> {
              should.equal(list.length(props), 3)
              case list.key_find(props, "street") {
                Ok(street) -> {
                  should.equal(street.field_type, Some(types.StringType))
                  case street.string_constraints {
                    Some(constraints) -> {
                      should.equal(constraints.min_length, Some(1))
                    }
                    None -> panic as "Expected string constraints"
                  }
                }
                Error(_) -> panic as "Street property should exist"
              }
            }
            None -> panic as "Billing address should have properties"
          }

          // Check required fields were copied
          should.equal(billing.required, ["street", "city", "zip"])
        }
        Error(_) -> panic as "Billing address should exist"
      }

      case list.key_find(schema.properties, "shipping_address") {
        Ok(shipping) -> {
          should.equal(shipping.ref, None)
          should.equal(shipping.field_type, Some(types.ObjectType))
          should.equal(shipping.required, ["street", "city", "zip"])
        }
        Error(_) -> panic as "Shipping address should exist"
      }
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

/// Test $ref with local overrides
pub fn ref_with_override_test() {
  let json =
    "{
    \"title\": \"Extended Form\",
    \"type\": \"object\",
    \"properties\": {
      \"contact\": {
        \"$ref\": \"#/$defs/person\",
        \"title\": \"Primary Contact\",
        \"description\": \"Main contact person\"
      }
    },
    \"$defs\": {
      \"person\": {
        \"type\": \"object\",
        \"title\": \"Person\",
        \"properties\": {
          \"name\": {
            \"type\": \"string\"
          },
          \"email\": {
            \"type\": \"string\",
            \"format\": \"email\"
          }
        }
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      case list.key_find(schema.properties, "contact") {
        Ok(contact) -> {
          // Local overrides should take precedence
          should.equal(contact.title, Some("Primary Contact"))
          should.equal(contact.description, Some("Main contact person"))
          // But type info should come from reference
          should.equal(contact.field_type, Some(types.ObjectType))

          case contact.properties {
            Some(props) -> {
              should.equal(list.length(props), 2)
            }
            None -> panic as "Contact should have properties"
          }
        }
        Error(_) -> panic as "Contact should exist"
      }
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

/// Referencing `x-widget` overrides the one from `$defs` — per-field
/// `option.or` in `merge_render_hints` picks the referencing side.
pub fn ref_widget_referencing_overrides_referenced_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"avatar\": {
        \"$ref\": \"#/$defs/upload_field\",
        \"x-widget\": \"hidden\"
      }
    },
    \"$defs\": {
      \"upload_field\": {
        \"type\": \"array\",
        \"x-widget\": \"image-upload\"
      }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(avatar) = list.key_find(schema.properties, "avatar")
  avatar.render_hints.widget |> should.equal(Some(types.HiddenWidget))
}

/// When the referencing side carries no `x-` extensions, hints from
/// `$defs` pass through untouched (widget AND `upload_config`).
pub fn ref_upload_config_passes_through_from_defs_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"avatar\": {
        \"$ref\": \"#/$defs/upload_field\"
      }
    },
    \"$defs\": {
      \"upload_field\": {
        \"type\": \"array\",
        \"x-widget\": \"image-upload\",
        \"x-accept\": \"image/png\",
        \"x-max-file-size\": 2048
      }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(avatar) = list.key_find(schema.properties, "avatar")
  avatar.render_hints.widget |> should.equal(Some(types.ImageUploadWidget))
  avatar.render_hints.upload_config
  |> should.equal(Some(types.UploadConfig("image/png", Some(2048))))
}

/// Test nested $ref in array items
pub fn ref_in_array_items_test() {
  let json =
    "{
    \"title\": \"Team Form\",
    \"type\": \"object\",
    \"properties\": {
      \"members\": {
        \"type\": \"array\",
        \"items\": {
          \"$ref\": \"#/$defs/member\"
        }
      }
    },
    \"$defs\": {
      \"member\": {
        \"type\": \"object\",
        \"properties\": {
          \"name\": {
            \"type\": \"string\"
          },
          \"role\": {
            \"type\": \"string\",
            \"enum\": [\"Developer\", \"Designer\", \"Manager\"]
          }
        },
        \"required\": [\"name\", \"role\"]
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      case list.key_find(schema.properties, "members") {
        Ok(members) -> {
          should.equal(members.field_type, Some(types.ArrayType))

          case members.items {
            Some(item_schema) -> {
              // Item ref should be resolved
              should.equal(item_schema.ref, None)
              should.equal(item_schema.field_type, Some(types.ObjectType))
              should.equal(item_schema.required, ["name", "role"])

              case item_schema.properties {
                Some(props) -> {
                  should.equal(list.length(props), 2)

                  case list.key_find(props, "role") {
                    Ok(role) -> {
                      case role.enum_values {
                        Some(values) -> {
                          should.equal(list.length(values), 3)
                        }
                        None -> panic as "Role should have enum values"
                      }
                    }
                    Error(_) -> panic as "Role property should exist"
                  }
                }
                None -> panic as "Item should have properties"
              }
            }
            None -> panic as "Members should have items schema"
          }
        }
        Error(_) -> panic as "Members should exist"
      }
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

/// Test error handling for non-existent $ref
pub fn invalid_ref_error_test() {
  let json =
    "{
    \"title\": \"Invalid Ref Form\",
    \"type\": \"object\",
    \"properties\": {
      \"field\": {
        \"$ref\": \"#/$defs/nonexistent\"
      }
    },
    \"$defs\": {}
  }"

  let result = parser.parse_schema(json)
  should.be_error(result)

  case result {
    Error(error) -> {
      case error {
        types.UnexpectedValue(msg) -> {
          should.equal(string.contains(msg, "not found"), True)
        }
        _ -> panic as "Expected UnexpectedValue error"
      }
    }
    Ok(_) -> panic as "Parser should fail for invalid ref"
  }
}

/// Test circular reference detection
pub fn circular_ref_test() {
  let json =
    "{
    \"title\": \"Circular Ref Form\",
    \"type\": \"object\",
    \"properties\": {
      \"node\": {
        \"$ref\": \"#/$defs/node\"
      }
    },
    \"$defs\": {
      \"node\": {
        \"type\": \"object\",
        \"properties\": {
          \"value\": {
            \"type\": \"string\"
          },
          \"child\": {
            \"$ref\": \"#/$defs/node\"
          }
        }
      }
    }
  }"

  // This should handle the self-reference gracefully
  // The child node will reference back to node definition
  let result = parser.parse_schema(json)

  // This should succeed because we allow recursive structures
  // The resolver should detect the cycle and stop
  case result {
    Ok(schema) -> {
      case list.key_find(schema.properties, "node") {
        Ok(node) -> {
          should.equal(node.field_type, Some(types.ObjectType))

          case node.properties {
            Some(props) -> {
              case list.key_find(props, "child") {
                Ok(child) -> {
                  // The child should still have the ref 
                  // or be resolved to avoid infinite recursion
                  should.equal(child.field_type, Some(types.ObjectType))
                }
                Error(_) -> panic as "Child property should exist"
              }
            }
            None -> panic as "Node should have properties"
          }
        }
        Error(_) -> panic as "Node should exist"
      }
    }
    Error(error) -> {
      // If it errors, it should be a circular reference error
      case error {
        types.UnexpectedValue(msg) -> {
          should.equal(string.contains(msg, "Circular"), True)
        }
        _ -> panic as "Expected circular reference error"
      }
    }
  }
}

/// Test compatibility with #/definitions/ syntax
pub fn definitions_compatibility_test() {
  let json =
    "{
    \"title\": \"Legacy Form\",
    \"type\": \"object\",
    \"properties\": {
      \"person\": {
        \"$ref\": \"#/definitions/person\"
      }
    },
    \"$defs\": {
      \"person\": {
        \"type\": \"object\",
        \"properties\": {
          \"name\": {
            \"type\": \"string\"
          }
        }
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      case list.key_find(schema.properties, "person") {
        Ok(person) -> {
          should.equal(person.ref, None)
          should.equal(person.field_type, Some(types.ObjectType))
        }
        Error(_) -> panic as "Person should exist"
      }
    }
    Error(_) -> panic as "Parser should succeed with #/definitions/ syntax"
  }
}

/// `$ref` inside `allOf[*].then.properties.X` must be expanded — otherwise
/// the conditional merge surfaces a field with `field_type: None` and the
/// dispatcher silently drops it.
pub fn ref_in_then_branch_property_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"flag\": {\"type\": \"boolean\"}
    },
    \"$defs\": {
      \"Side\": {\"type\": \"string\", \"enum\": [\"left\", \"right\"]}
    },
    \"allOf\": [{
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {\"properties\": {\"side\": {\"$ref\": \"#/$defs/Side\"}}}
    }]
  }"

  let side = assert_branch_property(top_level_rule(json).then_schema, "side")
  side.ref |> should.equal(None)
  side.field_type |> should.equal(Some(types.StringType))
  case side.enum_values {
    Some(values) -> list.length(values) |> should.equal(2)
    None -> panic as "Resolved $ref should carry enum_values from $defs"
  }
}

/// `$ref` inside `allOf[*].else.properties.X` must be expanded too —
/// symmetric to the then-branch test.
pub fn ref_in_else_branch_property_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"flag\": {\"type\": \"boolean\"}
    },
    \"$defs\": {
      \"Reason\": {\"type\": \"string\", \"minLength\": 1}
    },
    \"allOf\": [{
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"else\": {\"properties\": {\"reason\": {\"$ref\": \"#/$defs/Reason\"}}}
    }]
  }"

  let reason =
    assert_branch_property(top_level_rule(json).else_schema, "reason")
  reason.ref |> should.equal(None)
  reason.field_type |> should.equal(Some(types.StringType))
  case reason.string_constraints {
    Some(c) -> c.min_length |> should.equal(Some(1))
    None -> panic as "Resolved $ref should carry string_constraints from $defs"
  }
}

/// `$ref` inside `allOf[*].if.properties.X` must be expanded — otherwise
/// `evaluate_condition` cannot inspect `enum_values` of the referenced schema.
pub fn ref_in_if_condition_property_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"status\": {\"type\": \"string\"}
    },
    \"$defs\": {
      \"ActiveStatus\": {\"type\": \"string\", \"enum\": [\"active\"]}
    },
    \"allOf\": [{
      \"if\": {\"properties\": {\"status\": {\"$ref\": \"#/$defs/ActiveStatus\"}}},
      \"then\": {\"properties\": {\"reason\": {\"type\": \"string\"}}}
    }]
  }"

  let status =
    assert_branch_property(Some(top_level_rule(json).if_schema), "status")
  status.ref |> should.equal(None)
  status.field_type |> should.equal(Some(types.StringType))
  case status.enum_values {
    Some([_]) -> Nil
    _ -> panic as "Resolved $ref should expose the const-style enum_values"
  }
}

/// `then` may itself be a bare `$ref` (the whole branch is a referenced
/// definition). The resolver must expand it before downstream consumers see it.
pub fn ref_as_whole_then_branch_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"flag\": {\"type\": \"boolean\"}
    },
    \"$defs\": {
      \"ExtraFields\": {
        \"type\": \"object\",
        \"properties\": {
          \"detail\": {\"type\": \"string\"}
        },
        \"required\": [\"detail\"]
      }
    },
    \"allOf\": [{
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {\"$ref\": \"#/$defs/ExtraFields\"}
    }]
  }"

  let assert Some(then_schema) = top_level_rule(json).then_schema
  then_schema.ref |> should.equal(None)
  then_schema.field_type |> should.equal(Some(types.ObjectType))
  then_schema.required |> should.equal(["detail"])
  let assert Some(then_props) = then_schema.properties
  list.length(then_props) |> should.equal(1)
}

/// `$ref` inside conditionals nested in array `items` (item-level allOf)
/// must be expanded too — this is the original bug report scenario.
pub fn ref_inside_array_items_conditionals_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"lesions\": {
        \"type\": \"array\",
        \"items\": {
          \"type\": \"object\",
          \"properties\": {\"is_resected\": {\"type\": \"boolean\"}},
          \"allOf\": [{
            \"if\": {\"properties\": {\"is_resected\": {\"const\": true}}},
            \"then\": {\"properties\": {\"side\": {\"$ref\": \"#/$defs/Side\"}}}
          }]
        }
      }
    },
    \"$defs\": {
      \"Side\": {\"type\": \"string\", \"enum\": [\"left\", \"right\"]}
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(lesions) = list.key_find(schema.properties, "lesions")
  let assert Some(item_schema) = lesions.items
  let assert [rule] = item_schema.conditionals
  let side = assert_branch_property(rule.then_schema, "side")
  side.ref |> should.equal(None)
  side.field_type |> should.equal(Some(types.StringType))
  case side.enum_values {
    Some(values) -> list.length(values) |> should.equal(2)
    None -> panic as "Resolved $ref should carry enum_values from $defs"
  }
}

/// `$ref` to a `$defs` entry that itself contains `allOf` with a nested
/// `$ref` inside `then`. Exercises the merge path:
/// `resolve_property_ref` → recursive `resolve_property_ref` on the referenced
/// definition → `resolve_nested_refs` resolves its `conditionals` → result is
/// folded back via `merge_properties` (which `list.append`s conditionals).
pub fn ref_to_defs_with_nested_allof_ref_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"item\": {\"$ref\": \"#/$defs/ConditionalShape\"}
    },
    \"$defs\": {
      \"Detail\": {\"type\": \"string\", \"minLength\": 1},
      \"ConditionalShape\": {
        \"type\": \"object\",
        \"properties\": {\"flag\": {\"type\": \"boolean\"}},
        \"allOf\": [{
          \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
          \"then\": {\"properties\": {\"detail\": {\"$ref\": \"#/$defs/Detail\"}}}
        }]
      }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(item) = list.key_find(schema.properties, "item")
  item.ref |> should.equal(None)
  item.field_type |> should.equal(Some(types.ObjectType))

  let assert [rule] = item.conditionals
  let detail = assert_branch_property(rule.then_schema, "detail")
  detail.ref |> should.equal(None)
  detail.field_type |> should.equal(Some(types.StringType))
  case detail.string_constraints {
    Some(c) -> c.min_length |> should.equal(Some(1))
    None ->
      panic as "Resolved $ref inside merged conditional should carry constraints"
  }
}

/// Self-referential `$ref` reachable via `then_schema` must be detected as
/// a cycle (or successfully truncated by `visited`), not loop forever.
pub fn ref_cycle_through_then_branch_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"node\": {\"$ref\": \"#/$defs/Self\"}
    },
    \"$defs\": {
      \"Self\": {
        \"type\": \"object\",
        \"properties\": {\"flag\": {\"type\": \"boolean\"}},
        \"allOf\": [{
          \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
          \"then\": {\"$ref\": \"#/$defs/Self\"}
        }]
      }
    }
  }"

  case parser.parse_schema(json) {
    Ok(_) -> Nil
    Error(types.UnexpectedValue(msg)) ->
      should.equal(string.contains(msg, "Circular"), True)
    Error(_) -> panic as "Expected Ok or a Circular reference error"
  }
}

/// `$ref` inside a `oneOf` element nested in `then.properties` must also be
/// expanded — exercises the recursion path
/// `resolve_conditional_rule` → `resolve_property_ref` → `resolve_nested_refs`
/// → `resolve_optional(one_of, ...)`.
pub fn ref_inside_oneof_inside_then_branch_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"flag\": {\"type\": \"boolean\"}
    },
    \"$defs\": {
      \"Side\": {\"type\": \"string\", \"enum\": [\"left\", \"right\"]},
      \"Code\": {\"type\": \"integer\"}
    },
    \"allOf\": [{
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {
        \"properties\": {
          \"choice\": {\"oneOf\": [
            {\"$ref\": \"#/$defs/Side\"},
            {\"$ref\": \"#/$defs/Code\"}
          ]}
        }
      }
    }]
  }"

  let choice =
    assert_branch_property(top_level_rule(json).then_schema, "choice")
  let assert Some(variants) = choice.one_of
  let assert [side_variant, code_variant] = variants
  side_variant.ref |> should.equal(None)
  side_variant.field_type |> should.equal(Some(types.StringType))
  code_variant.ref |> should.equal(None)
  code_variant.field_type |> should.equal(Some(types.IntegerType))
}

/// Resolving $ref must preserve the declaration order of nested properties.
pub fn ref_preserves_nested_property_order_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"address\": {\"$ref\": \"#/$defs/address\"}
    },
    \"$defs\": {
      \"address\": {
        \"type\": \"object\",
        \"properties\": {
          \"street\": {\"type\": \"string\"},
          \"apartment\": {\"type\": \"string\"},
          \"city\": {\"type\": \"string\"},
          \"zip\": {\"type\": \"string\"}
        }
      }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(address) = list.key_find(schema.properties, "address")
  let assert Some(nested) = address.properties
  nested
  |> list.map(fn(entry) { entry.0 })
  |> should.equal(["street", "apartment", "city", "zip"])
}

/// `disabled`/`readonly` OR-merge: `Some(False)` on either side must not
/// re-enable a `Some(True)` from the other (the `ui:disabled` contract).
pub fn merge_render_hints_disabled_readonly_or_merge_test() {
  let on =
    types.RenderHints(
      ..types.empty_hints(),
      disabled: Some(True),
      readonly: Some(True),
    )
  let off =
    types.RenderHints(
      ..types.empty_hints(),
      disabled: Some(False),
      readonly: Some(False),
    )

  let merged = resolver.merge_render_hints(off, on)
  merged.disabled |> should.equal(Some(True))
  merged.readonly |> should.equal(Some(True))

  let flipped = resolver.merge_render_hints(on, off)
  flipped.disabled |> should.equal(Some(True))
  flipped.readonly |> should.equal(Some(True))
}

/// A $ref-bearing node's local `items` passes through nested-$ref
/// resolution before the merge — it must not survive it unresolved.
pub fn ref_with_local_items_ref_resolves_test() {
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"arr\": { \"type\": \"array\" }, \"item\": { \"type\": \"string\", \"title\": \"Item\" } }, \"properties\": { \"x\": { \"$ref\": \"#/$defs/arr\", \"items\": { \"$ref\": \"#/$defs/item\" } } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(x) = list.key_find(schema.properties, "x")
  let assert Some(items) = x.items
  items.title |> should.equal(Some("Item"))
  items.ref |> should.equal(None)
}

pub fn resolve_property_standalone_test() {
  let base =
    types.SchemaProperty(
      ..types.empty_property(),
      field_type: option.Some(types.StringType),
    )
  let referencing =
    types.SchemaProperty(
      ..types.empty_property(),
      ref: option.Some("#/$defs/base"),
    )
  let defs = option.Some(dict.from_list([#("base", base)]))
  let assert Ok(resolved) = resolver.resolve_property(referencing, defs)
  resolved.field_type |> should.equal(option.Some(types.StringType))
  resolved.ref |> should.equal(option.None)
}
