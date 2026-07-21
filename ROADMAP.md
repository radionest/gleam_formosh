# Formosh — Roadmap

Roadmap построен так: каждый этап даёт законченную ценность, минимизирует breaking changes для предыдущих, и кладёт фундамент для следующих. Размер — приблизительная оценка (S < 1 нед, M ≈ 1–2 нед, L ≈ 2–4 нед, XL > 1 мес для соло-разработки).

## Статус (июль 2026, v0.8.4)

План ниже писался до выхода v0.7–v0.8, и номера версий разошлись с реальностью:

- **v0.7 UI Schema — сделано** (вышло в v0.7): `ui:*`-ключи, атрибут `ui-schema`, deprecation `x-*`-расширений (удаление намечено на v0.9).
- **v0.8 Widget Registry — не начато.** Линейка 0.8.x ушла на доработки UiSchema, swipe-review, read-only режим и закрытие валидаций.
- Из **v0.9** уже сделано: `pattern` (через `gleam_regexp`, FFI не понадобился), `minItems`/`maxItems`, `multipleOf`, валидация `enum`. Остались: `anyOf`-схемы, `dependencies*`, `additionalProperties`, `not`, RFC-валидация email/url.

## Долги API — из аудита документации (июль 2026)

Найдены при сверке `docs/` с исходниками; из документации эти пункты удалены как несуществующие — здесь они ждут реализации (или осознанного отказа):

- **`formosh-validate` не эмитится.** `component.on_validate` подписывается на событие, которое никто не шлёт (`component.gleam` эмитит только `formosh-ready` / `formosh-change` / `formosh-submitting` / `formosh-submit`). Либо эмитить при смене валидности, либо удалить хелпер.
- **HTTP-заголовки недоступны из веб-компонента.** `with_http_submit` принимает headers, но атрибута (`submit-headers`) нет. Добавить атрибут с JSON-объектом заголовков.
- **`ui:widget: "toggle"` не подключён.** `boolean_field.render_as_toggle` (и части `toggle`, `toggle-wrapper`, `toggle-slider`, `toggle-text`, `data-state`) существуют, но диспетчер всегда рендерит radio. Подключить через dispatcher; системно закрывается widget registry (v0.8).
- **Нет реэкспортов из корневого модуля.** `formosh.StringValue` / `formosh.FormModel` не компилируются — Gleam не умеет реэкспорт конструкторов. Рассмотреть функции-обёртки (`formosh.string_value(...)`) для эргономики.
- **Configurable CSS class prefix** — заявлялся в README, но никогда не был реализован (из README удалён). Решить: реализовать или окончательно отказаться (частично закрывается v0.15 theming).

---

## v0.7 — UI Schema (фундамент)

**Цель.** Развести «данные» и «представление». Без этого все дальнейшие фичи будут тянуть `x-widget`-грязь в JSON Schema.

**Объём:** L. **Breaking:** да (минорный — `x-widget` всё ещё читается, но deprecated).

### Что делаем

- Ввести параллельную структуру `UiSchema` с тем же путём адресации, что и `FieldPath`. Хранить как `Dict(String, UiOptions)` либо как дерево, изоморфное JSON Schema.
- Поддержать минимум: `ui:widget` (имя виджета), `ui:options` (произвольные key/value), `ui:order` (порядок полей в object), `ui:placeholder`, `ui:help`, `ui:autofocus`, `ui:disabled`, `ui:readonly`, `ui:hidden`, `ui:title` (override), `ui:description` (override).
- Парсер `formosh/schema/ui_parser.gleam` — отдельный, не загрязняем `schema/parser.gleam`.
- Конфиг билдер: `formosh.with_ui_schema(json_string)` и `formosh.with_ui_schema_dict(dict)`.
- Web Component: новый атрибут `ui-schema='{...}'`.
- Миграция: `x-widget: "hidden"` → `ui:widget: "hidden"`; парсер ещё 2 версии понимает обе формы, выдаёт console.warn.

### Файлы

- `src/formosh/schema/ui_schema.gleam` (новый) — типы `UiSchema`, `UiOptions`.
- `src/formosh/schema/ui_parser.gleam` (новый).
- `src/formosh/form/model.gleam` — добавить `ui_schema: UiSchema` в `FormModel`.
- `src/formosh/fields/field_dispatcher.gleam` — выбор виджета: сначала `ui:widget`, потом fallback на правила из README.
- `src/formosh/component.gleam` — атрибут `ui-schema`.

### Acceptance

- Та же data-схема + разные `ui:widget: "textarea" | "select"` дают разные виджеты.
- `ui:order` меняет порядок полей в object без правки `properties`.
- `x-widget: "hidden"` продолжает работать (с deprecation warning).

---

## v0.8 — Widget Registry

**Цель.** Дать пользователю зарегистрировать свой виджет без форка библиотеки. Это «второй слой фундамента» вместе с UI Schema.

**Объём:** L. **Breaking:** нет (дополнение API). **Зависит от:** v0.7.

### Что делаем

- Тип `Widget(msg)` — record `{ name: String, render: fn(WidgetContext) -> Element(msg), parse_value: fn(String) -> Value }`.
- `WidgetContext` — record с `path`, `schema_node`, `ui_options`, `current_value`, `errors`, `dispatch: fn(Msg) -> Nil`. Это публичный контракт.
- Builder: `formosh.with_widget(name, widget)`, `formosh.with_widgets(list)`.
- В рантайме: `field_dispatcher` сначала ищет в user registry, потом в default registry. Default registry содержит все встроенные виджеты, тоже выраженные через тот же контракт — съесть собачий корм.
- Lifecycle hooks виджета: `on_mount`, `on_value_change`, `on_blur` (опциональные).

### Файлы

- `src/formosh/widgets/registry.gleam` (новый).
- `src/formosh/widgets/context.gleam` (новый) — `WidgetContext`, `Msg` для виджетов.
- Все `fields/*_field.gleam` переписать как реализации `Widget` (но рендеринг тот же). После этой переделки `field_dispatcher.gleam` ужмётся до dispatch-таблицы.
- Документация: пример `examples/custom_widget` — простой color-picker через FFI к `<input type="color">`.

### Acceptance

- Пользователь регистрирует виджет, в `ui:widget: "my-widget"` он отображается.
- Все встроенные поля используют тот же registry (нет двух путей рендеринга).
- Кастомный виджет получает `dispatch` и может править `FormModel`.

---

## v0.9 — JSON Schema gap-closing

**Цель.** Закрыть базовые keywords стандарта, без которых formosh нельзя называть «JSON Schema form generator» без оговорок.

**Объём:** M. **Breaking:** нет. **Зависит от:** —.

### Что делаем

- **`pattern` (regex).** FFI к `RegExp` через `src/formosh/ffi/regex_ffi.mjs`: `pub fn test_regex(pattern: String, value: String) -> Bool`. Подключить в `validation/field_requirements.gleam`. Тесты — RFC-набор (email через pattern из draft, ИНН, телефон).
- **`minItems` / `maxItems`.** В `array_field` блокировать удаление/добавление по достижению границ, добавить ошибку «нужно минимум N».
- **`anyOf` со схемами (не только const).** Радио-вариант: показать селектор подсхемы, рендерить выбранную. Хранить выбор в отдельном `Dict(FieldPath, Int)`.
- **`dependencies` / `dependentRequired` / `dependentSchemas`.** При изменении ключа A — пересчитать required/подсхему. Логика та же, что у `if/then/else`, переиспользовать `conditional_resolver.gleam`.
- **`additionalProperties: false`** — отбрасывать в `get_values` ключи, не описанные в `properties`. `additionalProperties: { type: ... }` — рендерить key/value-редактор (как dict).
- **`not`** — только в валидации (не в рендеринге). Negate любой проверки.
- **Полноценная email/url валидация.** Через `pattern` из JSON Schema spec.

### Файлы

- `src/formosh/ffi/regex_ffi.mjs` (новый).
- `src/formosh/validation/field_requirements.gleam` — дописать `validate_pattern`, `validate_min_max_items`.
- `src/formosh/schema/parser.gleam` — поддержать `anyOf`, `dependencies*`, `additionalProperties`, `not`.
- `src/formosh/schema/conditional_resolver.gleam` — обобщить с `if/then/else` на `dependentSchemas`.
- `src/formosh/fields/object_field.gleam` — рендерить `additionalProperties` как dict.

### Acceptance

- Все эти keywords пропускают валидный JSON Schema test suite (минимум — happy path для draft 2020-12).
- README в секции «What's NOT Implemented» уменьшается на 60%.

---

## v0.10 — Layouts

**Цель.** Дать возможность строить формы сложнее «всё подряд сверху вниз».

**Объём:** M. **Breaking:** нет. **Зависит от:** v0.7 (UI Schema).

### Что делаем

- В UI Schema поддержать layout-узлы (как в JSONForms): `{ "type": "VerticalLayout" | "HorizontalLayout" | "Group" | "Categorization", "elements": [...], "label"?: ... }`. Листья — `{ "type": "Control", "scope": "#/properties/foo" }`.
- Если `ui_schema` отсутствует — fallback на текущий линейный рендер (back-compat).
- `Group` — `<fieldset>` с легендой.
- `HorizontalLayout` — CSS grid, равные колонки.
- `Categorization` — табы (без wizard ещё).

### Файлы

- `src/formosh/schema/ui_schema.gleam` — добавить layout union type.
- `src/formosh/fields/layout.gleam` (новый) — рендер `Vertical`, `Horizontal`, `Group`, `Categorization`.
- `src/formosh/form/view.gleam` — точка ветвления: если в `ui_schema` есть root layout — рендерим его, иначе старый flow.

### Acceptance

- Демка: форма с 2 колонками (`HorizontalLayout`), вложенный `Group`, табы поверх 3 секций.
- Без `ui_schema` всё работает как раньше.

---

## v0.11 — Wizard / Multi-step

**Цель.** Длинные формы (анкета, оформление заказа) — пошаговый интерфейс с per-step валидацией.

**Объём:** M. **Breaking:** нет. **Зависит от:** v0.10 (Categorization уже даёт половину).

### Что делаем

- Layout `Wizard` — частный случай `Categorization` с навигацией Prev/Next + Submit на последнем шаге.
- Валидация шага: пользователь не уходит со step N, пока в видимых полях step N есть ошибки.
- Прогресс-бар как отдельный part (`progress`, `progress-step`).
- Опции в UI Schema: `linear: bool` (можно ли прыгать вперёд), `allow_back: bool`.
- State в модели: `current_step: Int`, `visited_steps: Set(Int)`.

### Файлы

- `src/formosh/fields/wizard.gleam` (новый).
- `src/formosh/form/model.gleam` — добавить wizard-state.
- `src/formosh/form/update.gleam` — `NextStep`, `PrevStep`, `GoToStep(Int)`.

### Acceptance

- 3-step демка, ошибки на step 1 блокируют переход.
- Submit запускается только с последнего шага.

---

## v0.12 — Async / server-side validation

**Цель.** «Email уже занят», «инн не найден в ЕГРЮЛ». Без этого нельзя делать регистрации и любые формы со справочниками.

**Объём:** M. **Breaking:** нет.

### Что делаем

- API: `formosh.with_async_validator(field_path, validator)` где `validator: fn(Value) -> Effect(Result(Nil, String))`.
- Debounce: дефолт 500 мс, перенастраивается через `ui:options.debounce_ms`.
- В модели: `pending_validations: Set(FieldPath)`, в view — спиннер на поле.
- Submit ждёт завершения всех pending.
- Ошибка с бэка — отдельный канал `model.async_errors`, мерджится с `model.errors` при отображении.
- Web Component: атрибут `async-validate-url='https://api/validate'`, который шлёт `{ field, value }` и принимает `{ valid: bool, message?: string }`.

### Файлы

- `src/formosh/validation/async.gleam` (новый).
- `src/formosh/form/model.gleam` — `pending_validations`, `async_errors`.
- `src/formosh/form/update.gleam` — debounce-логика, обработка ответов.

### Acceptance

- Демка: при вводе email-а через 500 мс улетает запрос, спиннер крутится, потом либо ✓ либо текст ошибки.
- Если поле ещё проверяется — submit ждёт.

---

## v0.13 — Expressions / calculated fields / cross-field rules

**Цель.** Бизнес-логика форм: «итого = цена × количество», «дата окончания не раньше начала», «если выбрана опция А, поле B обязательно».

**Объём:** XL. **Breaking:** нет. **Зависит от:** v0.7 (UI Schema несёт expressions).

### Что делаем

- Мини-DSL выражений (свой парсер, не eval). Грамматика:
  - литералы: число, строка, bool, null;
  - идентификаторы: `$.foo.bar` (путь от корня), `@.sibling` (относительно текущего);
  - операторы: `+ - * / %`, `== != < <= > >=`, `&& ||`, `!`;
  - функции: `iif(cond, a, b)`, `today()`, `sum($.items[*].price)`, `length($.items)`, `contains(str, sub)`.
- Точки приложения в UI Schema:
  - `ui:value_expression: "@.price * @.qty"` — поле вычисляется, ввод запрещён;
  - `ui:visible_if: "$.type == 'company'"` — альтернатива `if/then/else`, проще;
  - `ui:enabled_if`, `ui:required_if`.
- Реактивность: при изменении любого пути собирается список зависимых выражений, они пересчитываются. Граф зависимостей строится один раз при парсинге UI Schema.
- Циклы зависимостей — детектируем при парсинге, бросаем `ParseError`.

### Файлы

- `src/formosh/expr/parser.gleam` (новый) — lexer + recursive descent parser.
- `src/formosh/expr/ast.gleam` (новый) — типы выражений.
- `src/formosh/expr/eval.gleam` (новый) — интерпретатор поверх `FormModel.values`.
- `src/formosh/expr/dependencies.gleam` (новый) — построение графа зависимостей.
- `src/formosh/form/update.gleam` — после каждого `UpdateValue` пересчитываем зависимые поля.
- Тестов отдельно: `test/expr_test.gleam` с матрицей операторов и приоритетов.

### Acceptance

- Демка: order form — qty, price, total (вычисляемый). Меняем qty — total обновляется.
- Cross-field валидация: end_date >= start_date через `required_if` либо явный validator.

---

## v0.14 — Generic file upload + async enum

**Цель.** Унифицировать загрузку файлов (сейчас только image-upload, hardcoded, только верхний уровень). Дать typeahead для справочников.

**Объём:** M. **Breaking:** да — `x-widget: "image-upload"` мигрирует на `ui:widget: "file"` с `ui:options.accept = "image/*"`.

### Что делаем

- **File upload:** виджет `file`, через `WidgetRegistry` (зависит от v0.8). Опции: `accept`, `multiple`, `max_size`, `upload_url`, `headers`. Прогресс через `XMLHttpRequest.upload.onprogress`. Поддержка `format: "data-url"` (base64 inline) и `format: "binary"` (multipart upload).
- **Image-upload** реализуется как пресет `file` + preview. Старый код выпиливается, его поведение покрывается ui-options.
- **Async enum / typeahead:** виджет `autocomplete`, опции `data_source_url`, `query_param` (по дефолту `q`), `value_field`, `label_field`, `min_chars`, `debounce_ms`. Дебаунс — общий с async-validation.
- В JSON Schema — без изменений, enum остаётся пустым, опции тянутся в рантайме.

### Файлы

- `src/formosh/widgets/file.gleam` (новый).
- `src/formosh/widgets/autocomplete.gleam` (новый).
- `src/formosh/ffi/upload_ffi.mjs` — XHR с прогрессом.
- Удалить `src/formosh/fields/image_field.gleam`, мигрировать пример.

### Acceptance

- File-upload работает на любой глубине (внутри array/object).
- Typeahead-демка: поиск города из списка из 10k записей через `/api/cities?q=...`.

---

## v0.15 — Theming pack (Tailwind)

**Цель.** «Работает красиво из коробки», без необходимости писать CSS с нуля.

**Объём:** M. **Breaking:** нет.

### Что делаем

- Отдельный hex-пакет `formosh_theme_tailwind` (либо `formosh/themes/tailwind.gleam` внутри основного — но лучше отдельно, не тащить CSS в core).
- Готовый CSS (или Tailwind preset) для всех `::part()`-имён.
- Документация: «как подключить тему за 3 строки».
- В перспективе — пакеты под Bootstrap, DaisyUI (можно потом, силами комьюнити).

### Acceptance

- Один `import` + один `<link>` — форма выглядит как production-ready форма, без ручного CSS.

---

## v0.16 — i18n

**Цель.** Переводы лейблов и сообщений об ошибках.

**Объём:** S. **Breaking:** нет.

### Что делаем

- `formosh.with_locale("ru")` — переключает встроенный словарь ошибок.
- `formosh.with_messages(dict)` — кастомные переопределения.
- Поддержать `errorMessage` keyword (Ajv-extension): прямо в schema можно положить `{ "errorMessage": { "minLength": "Слишком коротко" } }`.
- Локали в репозитории: en (дефолт), ru. Остальные — PR-ами от комьюнити.

### Файлы

- `src/formosh/i18n/locales.gleam` (новый) — словари.
- `src/formosh/validation/error.gleam` — пропускать через словарь.

### Acceptance

- Все встроенные ошибки переводятся одной строкой конфига.
- `errorMessage` из schema перекрывает дефолт.

---

## Сквозные задачи (не отдельные релизы)

- **JSON Schema test suite** — подключить официальный набор JSON Schema Test Suite как submodule, прогонять часть «structural validation» в CI. Сразу будет видно, какие keywords мы реально поддерживаем.
- **Accessibility audit** — пройтись axe-core по каждому виджету, расставить ARIA. Лучше делать на этапе v0.8 (когда виджеты переписываем под registry — заодно и a11y).
- **Performance benchmarks** — отдельная папка `bench/`, замер времени рендера на форме из 100/500/1000 полей. Нужно сейчас, до v0.13 (expressions добавят пересчёты — нужно baseline).
- **CHANGELOG.md и SemVer** — пора. После v0.7 каждый breaking — мажорный bump.

---

## Чего НЕ делаем в этом roadmap (и почему)

- **Visual form builder** в стиле SurveyJS Creator — это отдельный продукт на порядок больше core. Если делать — отдельным проектом `formosh-builder`.
- **OpenAPI integration** — пользователь конвертит OpenAPI → JSON Schema чужими средствами; для нас это не приоритет.
- **Markdown rich text widget, signature pad, geo-picker** — оставляем на comminuty через widget registry (для этого v0.8 и нужен).
- **Server-side rendering** — Lustre его поддерживает; если будет запрос — отдельная итерация, но не в основном roadmap.

---

## Критический путь

`v0.7 (UI Schema)` → `v0.8 (Widget Registry)` — это **обязательная двойка**, всё остальное опирается на них. Если делать одно без другого, в v0.13 (expressions) выяснится, что значения из UI Schema некому передавать в кастомные виджеты, и придётся ломать API повторно.

Дальше две независимые ветки, которые можно делать параллельно:
- **«Стандарт»:** v0.9 (JSON Schema closing) → v0.16 (i18n).
- **«UX»:** v0.10 (Layouts) → v0.11 (Wizard) → v0.13 (Expressions).

v0.12 (async) и v0.14 (files) — самостоятельные, можно вклинить когда удобно.
