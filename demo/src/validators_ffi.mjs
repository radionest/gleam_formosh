// Demo-only: JS cross-field validators paired with the schemas in
// `demo/schemas/`. Attaches/detaches them on the <formosh-form> element
// via its `validator` JS property (see `component.on_property_change` in
// the library).

const VALIDATORS = {
  budget_split: (values) => {
    const total = Number(values.total_limit ?? 0);
    const categories = Array.isArray(values.categories) ? values.categories : [];
    const sum = categories.reduce(
      (acc, c) => acc + Number(c?.limit ?? 0),
      0,
    );
    if (sum > total) {
      return [{
        path: "total_limit",
        message: `Sum of category limits (${sum}) exceeds total budget (${total})`,
        rule: "x-sum-limit",
      }];
    }
    return [];
  },

  date_range: (values) => {
    if (
      typeof values.start_date === "string"
      && typeof values.end_date === "string"
      && values.start_date !== ""
      && values.end_date !== ""
      && values.start_date > values.end_date
    ) {
      return [{
        path: "end_date",
        message: "End date must be on or after start date",
        rule: "x-date-order",
      }];
    }
    return [];
  },

  password_confirm: (values) => {
    if (
      typeof values.password === "string"
      && typeof values.confirm_password === "string"
      && values.password !== ""
      && values.confirm_password !== ""
      && values.password !== values.confirm_password
    ) {
      return [{
        path: "confirm_password",
        message: "Passwords do not match",
        rule: "x-equality",
      }];
    }
    return [];
  },
};

// Set `element.validator` after Lustre has rendered the form into the DOM.
// `requestAnimationFrame` gives the diff a chance to land before we touch
// the element.
export function attachValidator(elementId, validatorKind) {
  requestAnimationFrame(() => {
    const el = document.getElementById(elementId);
    if (!el) return;
    el.validator = VALIDATORS[validatorKind] ?? null;
  });
}

export function detachValidator(elementId) {
  requestAnimationFrame(() => {
    const el = document.getElementById(elementId);
    if (el) el.validator = null;
  });
}
