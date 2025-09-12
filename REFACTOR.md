# План рефакторинга Formosh

## Анализ соответствия принципам KISS, YAGNI, DRY

### 🔴 Нарушения DRY (Don't Repeat Yourself)

#### 1. Дублирование функций рендеринга label (3 места)

**Проблема:** Три почти идентичные функции для рендеринга label в разных файлах.

**Локации:**
- `src/fields/field_common.gleam:69-93` - `render_label()`
- `src/fields/field_common.gleam:29-54` - `create_field_label()` 
- `src/fields/boolean_field.gleam:246-270` - `render_checkbox_label()`

**Текущий код (пример):**
```gleam
// field_common.gleam:69
pub fn render_label(
  field_name: String,
  property: types.SchemaProperty,
  is_required: Bool,
) -> Element(FormMsg) {
  let label_text = case property.title {
    Some(title) -> title
    None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }
  // ... идентичная логика
}

// field_common.gleam:29
pub fn create_field_label(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  is_required: Bool,
) -> Element(FormMsg) {
  let field_name = path.get_field_name(field_path)
  let label_text = case property.title {
    Some(title) -> title
    None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }
  // ... та же логика
}
```

**Решение:** Оставить только одну функцию `render_label()` в `field_common.gleam`, которая принимает `FieldPath`.

#### 2. Дублирование функций value_to_json (2 места)

**Проблема:** Одинаковая логика конвертации Value в JSON в двух местах.

**Локации:**
- `src/form/update.gleam:356-373` - `value_to_json()`
- `src/formosh/component.gleam:346-363` - `value_to_json()` (идентичная копия)

**Решение:** Вынести в отдельный модуль `src/form/json_utils.gleam`.

#### 3. Дублирование field wrapper функций (2 версии)

**Проблема:** Две функции делают одно и то же с разными сигнатурами.

**Локации:**
- `src/fields/field_common.gleam:130-141` - `field_wrapper()`
- `src/fields/field_common.gleam:157-168` - `field_wrapper_with_path()`

**Решение:** Оставить только `field_wrapper_with_path()`, удалить устаревшую версию.

#### 4. Дублирование from_json_string функций

**Проблема:** Функция `from_json_string_to_html()` полностью дублирует `from_json_string()`.

**Локации:**
- `src/formosh.gleam:210-217` - `from_json_string()`
- `src/formosh.gleam:220-227` - `from_json_string_to_html()` (полный дубликат)

**Решение:** Удалить `from_json_string_to_html()`.

### 🟡 Нарушения YAGNI (You Aren't Gonna Need It)

#### 1. Неиспользуемая система Web Components (384 строки)

**Проблема:** Сложная система Web Components не используется ни в одном примере.

**Локация:** `src/formosh/component.gleam` (весь файл)

**Детали:**
- 384 строки кода для регистрации компонента
- Сложная система обработки атрибутов
- Не используется в `examples/file_schema_loader/`
- Добавляет сложность без реальной пользы

**Решение:** Переместить в отдельный пакет или удалить до появления реальной потребности.

#### 2. Множественные рендереры для boolean (3 варианта)

**Проблема:** Три способа рендеринга boolean полей, используется только один.

**Локации:**
- `src/fields/boolean_field.gleam:36-47` - `render()` (использует radio)
- `src/fields/boolean_field.gleam:130-159` - `render_as_checkbox()` (не используется)
- `src/fields/boolean_field.gleam:184-232` - `render_as_toggle()` (не используется)

**Используется:** Только `render_as_radio()` через основную функцию `render()`.

**Решение:** Оставить только радио-кнопки как основной способ. Альтернативы можно вынести в отдельный модуль-расширение.

#### 3. Избыточный FormConfig builder

**Проблема:** Множество методов конфигурации, большинство не используется.

**Локации в `src/formosh.gleam`:**
- `with_submit_url()` - используется
- `with_http_submit()` - не используется в примерах
- `with_custom_submit()` - не используется
- `with_css_prefix()` - не используется
- `with_show_errors_on_change()` - не используется

**Решение:** Оставить только базовые методы, остальные добавлять по мере необходимости.

#### 4. Сломанные обработчики событий

**Проблема:** Функции с TODO, которые не работают.

**Локация:** Поиск по `on_success` и `on_error` не дал результатов, но есть упоминания в документации.

**Решение:** Либо реализовать, либо удалить упоминания.

### 🔵 Нарушения KISS (Keep It Simple, Stupid)

#### 1. Сложная система path-based полей

**Проблема:** Избыточная сложность для работы с вложенными полями.

**Локации:**
- `src/form/path.gleam` - вся система путей
- `src/form/update.gleam:58-82` - конвертация между форматами

**Анализ:**
```gleam
// Сложная конвертация туда-обратно
fn model_to_root_value(model: FormModel) -> types.Value {
  case dict.to_list(model.values) {
    [] -> types.ObjectValue([])
    values -> types.ObjectValue(values)
  }
}

fn root_value_to_model_values(root_value: types.Value) -> dict.Dict(String, types.Value) {
  case root_value {
    types.ObjectValue(fields) -> dict.from_list(fields)
    _ -> dict.new()
  }
}
```

**Проблема:** Постоянная конвертация между плоским словарем и иерархической структурой добавляет сложность.

**Решение:** Рассмотреть упрощение до плоской структуры с составными ключами типа `"address.street"`.

#### 2. Избыточная обработка HTTP методов

**Проблема:** Поддержка разных HTTP методов, но реально используется только POST.

**Локация:** `src/form/model.gleam:15` - `HttpSubmit(url: String, method: String, headers: List(#(String, String)))`

**Используется:** Только POST в примерах.

**Решение:** Начать с поддержки только POST, добавить другие методы когда появится потребность.

#### 3. Вложенные Option

**Проблема:** Глубокая вложенность Option усложняет код.

**Пример из `src/form/view.gleam:60-64`:**
```gleam
case model.schema.description {
  Some(desc) ->
    html.p([attribute.class("formosh-description")], [html.text(desc)])
  None -> html.text("")
}
```

**Решение:** Использовать разумные значения по умолчанию вместо Option где возможно.

## План рефакторинга по фазам

### Фаза 1: Быстрые победы (1-2 часа)

1. **Устранить дублирование label функций**
   - Объединить 3 функции в одну `render_label()` в `src/fields/field_common.gleam`
   - Обновить все вызовы

2. **Вынести value_to_json в общий модуль**
   - Создать `src/form/json_utils.gleam`
   - Переместить туда единственную реализацию
   - Обновить импорты в `update.gleam` и `component.gleam`

3. **Удалить дубликат from_json_string_to_html**
   - Просто удалить функцию из `src/formosh.gleam:220-227`

### Фаза 2: Упрощение (4-6 часов)

1. **Изолировать/удалить Web Component систему**
   - Вариант А: Удалить `src/formosh/component.gleam` полностью
   - Вариант Б: Переместить в `src/formosh/experimental/component.gleam`

2. **Упростить boolean рендереры**
   - Оставить только `render_as_radio()` в основном модуле
   - Альтернативные рендереры переместить в `src/fields/boolean_field_variants.gleam`

3. **Сократить FormConfig builder**
   - Оставить только: `config()`, `with_submit_url()`, базовую версию `from_schema()`
   - Удалить неиспользуемые методы

4. **Исправить или удалить сломанные обработчики**
   - Проверить и либо реализовать, либо удалить упоминания

### Фаза 3: Архитектурные улучшения (1-2 дня)

1. **Оценить необходимость path-based системы**
   - Анализ: используется ли реально вложенность?
   - Если нет - упростить до плоских ключей

2. **Упростить HTTP submission**
   - Начать только с POST
   - Добавить другие методы по мере необходимости

3. **Уменьшить вложенность Option**
   - Использовать значения по умолчанию
   - Упростить паттерн-матчинг

## Ожидаемые результаты

### Метрики улучшения:
- **Удаление кода:** ~700 строк (15-20% кодовой базы)
- **Упрощение API:** с 15+ публичных функций до 5-7
- **Снижение сложности:** удаление неиспользуемых путей выполнения
- **Улучшение поддерживаемости:** меньше дублирования, проще тестировать

### Приоритеты:
1. **Критично:** Устранить дублирование (DRY) - влияет на поддержку
2. **Важно:** Удалить неиспользуемое (YAGNI) - уменьшает сложность
3. **Желательно:** Упростить архитектуру (KISS) - улучшает понимание

## Конкретные действия для начала

### Шаг 1: Консолидация label функций
```gleam
// Оставить только эту функцию в field_common.gleam
pub fn render_label(
  field_path: path.FieldPath,
  property: types.SchemaProperty, 
  is_required: Bool,
) -> Element(FormMsg) {
  let field_name = path.get_field_name(field_path)
  let label_text = case property.title {
    Some(title) -> title
    None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }
  
  html.label([
    attribute.for(field_name),
    attribute.class("formosh-label"),
  ], [
    html.text(label_text),
    case is_required {
      True -> html.span([attribute.class("formosh-required")], [html.text(" *")])
      False -> html.text("")
    },
  ])
}
```

### Шаг 2: Создание json_utils.gleam
```gleam
// src/form/json_utils.gleam
import gleam/json
import schema/types.{type Value, StringValue, NumberValue, IntegerValue, 
                       BooleanValue, NullValue, ArrayValue, ObjectValue}

pub fn value_to_json(value: Value) -> json.Json {
  case value {
    StringValue(s) -> json.string(s)
    NumberValue(n) -> json.float(n)
    IntegerValue(i) -> json.int(i)
    BooleanValue(b) -> json.bool(b)
    NullValue -> json.null()
    ArrayValue(items) -> json.array(items, value_to_json)
    ObjectValue(fields) -> 
      json.object(
        fields |> list.map(fn(pair) {
          let #(key, val) = pair
          #(key, value_to_json(val))
        })
      )
  }
}
```

### Шаг 3: Очистка formosh.gleam
Удалить строки 220-227 (функция `from_json_string_to_html`).

## Заключение

Проект Formosh имеет хорошую основу и следует функциональным принципам программирования, но накопил техдолг в виде дублирования кода и неиспользуемых функций. Предложенный рефакторинг позволит:

1. **Снизить объем кода на 15-20%** без потери функциональности
2. **Упростить API** для пользователей библиотеки
3. **Улучшить поддерживаемость** через устранение дублирования
4. **Ускорить разработку** новых функций на чистой кодовой базе

Рекомендуется начать с Фазы 1 (быстрые победы), которая даст немедленный эффект при минимальных усилиях.