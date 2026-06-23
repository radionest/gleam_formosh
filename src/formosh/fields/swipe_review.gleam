//// Pure burndown logic for the swipe-review widget: flatten region→zone,
//// read answers from the model, compute progress, parse the gesture config
//// from `ui:options`. No Lustre/DOM dependency — the renderer (swipe_review_field)
//// builds on these.

import formosh/form/model.{type FormModel}
import formosh/form/path.{type FieldPath, PropertySegment}
import formosh/schema/types.{type SchemaProperty, type Value}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}

/// One of the three answer choices: storage `code`, display `label`,
/// presentational `tone` (e.g. "danger"/"ok"/"muted").
pub type Choice {
  Choice(code: String, label: String, tone: String)
}

/// Gesture→choice binding read from `ui:options`.
pub type GestureConfig {
  GestureConfig(right: Choice, left: Choice, button: Choice)
}

/// A flattened zone: its region, its full path, its title, and the current
/// answer code (`None` = unanswered).
pub type Zone {
  Zone(
    region_key: String,
    region_title: String,
    path: FieldPath,
    title: String,
    answer: Option(String),
  )
}

/// Flatten the widget property's region→zone tree into declared order,
/// reading each zone's current answer from the model.
pub fn zones(
  base_path: FieldPath,
  property: SchemaProperty,
  model: FormModel,
) -> List(Zone) {
  case property.properties {
    Some(regions) ->
      list.flat_map(regions, fn(region_pair) {
        let #(region_key, region_prop) = region_pair
        let region_title = title_or(region_prop, region_key)
        let region_path = list.append(base_path, [PropertySegment(region_key)])
        case region_prop.properties {
          Some(zone_props) ->
            list.map(zone_props, fn(zone_pair) {
              let #(zone_key, zone_prop) = zone_pair
              let zone_path =
                list.append(region_path, [PropertySegment(zone_key)])
              Zone(
                region_key: region_key,
                region_title: region_title,
                path: zone_path,
                title: title_or(zone_prop, zone_key),
                answer: answer_at(model, zone_path),
              )
            })
          None -> []
        }
      })
    None -> []
  }
}

fn title_or(prop: SchemaProperty, fallback: String) -> String {
  case prop.title {
    Some(t) -> t
    None -> fallback
  }
}

fn answer_at(model: FormModel, zone_path: FieldPath) -> Option(String) {
  case model.get_value_at_path(model, zone_path) {
    Some(types.StringValue(s)) -> Some(s)
    _ -> None
  }
}

fn is_answered(zone: Zone) -> Bool {
  case zone.answer {
    Some(_) -> True
    None -> False
  }
}

/// The first unanswered zone — the top of the burndown stack.
pub fn current(zones: List(Zone)) -> Option(Zone) {
  list.find(zones, fn(z) { !is_answered(z) })
  |> option.from_result()
}

/// How many zones have an answer.
pub fn answered_count(zones: List(Zone)) -> Int {
  list.count(zones, is_answered)
}

/// Path of the last zone (in declared order) that has an answer — the target
/// of an undo. `None` if nothing answered yet.
pub fn last_answered_path(zones: List(Zone)) -> Option(FieldPath) {
  list.filter(zones, is_answered)
  |> list.last()
  |> option.from_result()
  |> option.map(fn(z) { z.path })
}

/// Paths of all unanswered zones — the target set of bulk-finish.
pub fn unanswered_paths(zones: List(Zone)) -> List(FieldPath) {
  list.filter(zones, fn(z) { !is_answered(z) })
  |> list.map(fn(z) { z.path })
}

/// All UNANSWERED zones grouped by region, in declared order; regions with no
/// unanswered zones left are omitted. Each pair is `#(region_title, zones)`.
/// Drives the shrinking "sheet" view — every still-open zone is shown at once,
/// and a region drops out entirely once all its zones are answered.
pub fn unanswered_by_region(zones: List(Zone)) -> List(#(String, List(Zone))) {
  zones
  |> list.filter(fn(z) { !is_answered(z) })
  |> list.fold([], fn(acc, z) {
    case acc {
      [#(key, title, members), ..rest] ->
        case key == z.region_key {
          True -> [#(key, title, [z, ..members]), ..rest]
          False -> [#(z.region_key, z.region_title, [z]), ..acc]
        }
      [] -> [#(z.region_key, z.region_title, [z])]
    }
  })
  |> list.reverse
  |> list.map(fn(group) {
    let #(_key, title, members) = group
    #(title, list.reverse(members))
  })
}

/// Parse the gesture binding from a `ui:options` bag, falling back to generic
/// placeholder labels (`Yes`/`No`/`Skip`) when a key is missing from `ui:options`.
pub fn gesture_config(options: Dict(String, Value)) -> GestureConfig {
  GestureConfig(
    right: choice(options, "swipeRight", "positive", "Yes", "danger"),
    left: choice(options, "swipeLeft", "negative", "No", "ok"),
    button: choice(options, "button", "inaccessible", "Skip", "muted"),
  )
}

fn choice(
  options: Dict(String, Value),
  key: String,
  def_code: String,
  def_label: String,
  def_tone: String,
) -> Choice {
  case dict.get(options, key) {
    Ok(types.ObjectValue(fields)) ->
      Choice(
        code: str_field(fields, "value", def_code),
        label: str_field(fields, "label", def_label),
        tone: str_field(fields, "tone", def_tone),
      )
    _ -> Choice(def_code, def_label, def_tone)
  }
}

fn str_field(
  fields: List(#(String, Value)),
  key: String,
  default: String,
) -> String {
  case list.key_find(fields, key) {
    Ok(types.StringValue(s)) -> s
    _ -> default
  }
}

/// Display label for an answer code, by scanning the three choices.
pub fn label_for(config: GestureConfig, code: String) -> String {
  case code {
    c if c == config.right.code -> config.right.label
    c if c == config.left.code -> config.left.label
    c if c == config.button.code -> config.button.label
    _ -> code
  }
}
