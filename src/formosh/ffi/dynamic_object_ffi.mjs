import { toList } from "../../../prelude.mjs";

export function entries(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return toList([]);
  }
  return toList(Object.entries(value));
}
