// Tests for JSON Schema $ref and $defs support

import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import schema/parser
import schema/types

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
      should.equal(schema.title, "Person Form")

      // Check that both address properties have been resolved
      case dict.get(schema.properties, "billing_address") {
        Ok(billing) -> {
          // The ref should be resolved and cleared
          should.equal(billing.ref, None)
          should.equal(billing.field_type, Some(types.ObjectType))

          // Check nested properties exist
          case billing.properties {
            Some(props) -> {
              should.equal(dict.size(props), 3)
              case dict.get(props, "street") {
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

      case dict.get(schema.properties, "shipping_address") {
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
      case dict.get(schema.properties, "contact") {
        Ok(contact) -> {
          // Local overrides should take precedence
          should.equal(contact.title, Some("Primary Contact"))
          should.equal(contact.description, Some("Main contact person"))
          // But type info should come from reference
          should.equal(contact.field_type, Some(types.ObjectType))

          case contact.properties {
            Some(props) -> {
              should.equal(dict.size(props), 2)
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
      case dict.get(schema.properties, "members") {
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
                  should.equal(dict.size(props), 2)

                  case dict.get(props, "role") {
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
        parser.UnexpectedValue(msg) -> {
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
      case dict.get(schema.properties, "node") {
        Ok(node) -> {
          should.equal(node.field_type, Some(types.ObjectType))

          case node.properties {
            Some(props) -> {
              case dict.get(props, "child") {
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
        parser.UnexpectedValue(msg) -> {
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
      case dict.get(schema.properties, "person") {
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
