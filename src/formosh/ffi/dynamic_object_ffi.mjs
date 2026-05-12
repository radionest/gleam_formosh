import { Ok, Error, toList } from "../../../prelude.mjs";

export function entries(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return new Error(undefined);
  }
  return new Ok(toList(Object.entries(value)));
}
