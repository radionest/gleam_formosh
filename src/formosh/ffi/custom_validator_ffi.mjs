export function callValidator(jsFn, valuesJson) {
  if (typeof jsFn !== "function") {
    return [];
  }
  let values;
  try {
    values = JSON.parse(valuesJson);
  } catch (e) {
    console.warn("formosh: failed to parse form values for validator:", e);
    return [];
  }
  let result;
  try {
    result = jsFn(values);
  } catch (e) {
    console.warn("formosh: custom validator threw:", e);
    return [];
  }
  if (!Array.isArray(result)) {
    console.warn(
      "formosh: custom validator must return an array, got:",
      typeof result,
    );
    return [];
  }
  return result
    .filter((item) => {
      if (!item || typeof item !== "object") return false;
      if (typeof item.path !== "string" || item.path.length === 0) return false;
      if (typeof item.message !== "string") return false;
      return true;
    })
    .map((item) => ({
      path: item.path,
      message: item.message,
      rule: typeof item.rule === "string" ? item.rule : "custom",
    }));
}
