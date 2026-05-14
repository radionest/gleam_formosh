### ⚠️ Обнаруженные проблемы

#### YAGNI (You Aren't Gonna Need It) - нарушения

   - Web Component (`src/formosh/component.gleam`)  часть библиотеки но должен быть сохранен в другом месте.
1. **Излишние абстракции**
   - Разделение на `from_schema` и `from_config` когда можно обойтись одной функцией

#### KISS - нарушения

1. **Переусложнённая навигация по path** (`src/form/model.gleam:412-474`)
   - Рекурсивные функции `traverse_array_path` и `traverse_object_path` слишком сложные
   - Много вложенных case выражений
   - Дублирование логики между функциями

2. **Избыточные конверсии** (`src/form/update.gleam:58-82`)
   - `model_to_root_value` и `root_value_to_model_values` - лишняя промежуточная трансформация
   - Можно работать напрямую с плоской структурой

3. **Сложная логика в resolver** (`src/schema/resolver.gleam:194-217`)
   - Функция `merge_properties` слишком императивна
   - Много условной логики

#### DRY - нарушения

1. **Дублирование проверки required**
   - `src/form/model.gleam:145` - `is_field_required`
   - `src/form/view.gleam:121` - проверка в рендеринге
   - `src/schema/validator.gleam:47` - проверка в валидации
   - Нужна единая функция

2. **Повторяющиеся TODO комментарии**
   - `src/formosh/component.gleam:123` и `:142` - "Properly decode the form values"
   - Признак недоработанного кода

3. **Дублирование извлечения значений**
   - Похожие функции `extract_string_value`, `extract_number_value`, `extract_boolean_value`
   - Можно обобщить через полиморфную функцию

#### Проблемы функционального стиля

1. **Избыточное использование spread оператора**
   ```gleam
   FormModel(..model, values: dict.insert(...), is_dirty: True)
   ```
   - Хоть и иммутабельно, но многословно
   - Отсутствуют lens-подобные функции для обновления вложенных структур

2. **Недостаточная композиция функций**
   - Много промежуточных переменных вместо pipeline
   - Не используются функции высшего порядка где это уместно

## 📋 Детальный план рефакторинга

### Фаза 1: Удаление избыточного кода (YAGNI)

#### 1.1 Упростить FormConfig
**Файл:** `src/formosh.gleam`
**Действия:**
- ✅ `with_css_prefix` удалена; CSS-кастомизация перенесена на `::part()` / `data-*` / adopt_styles
- Удалить функцию `with_show_errors_on_change` (поле остаётся неиспользуемым)
- Оставить только `with_submit_url` как основной способ конфигурации

#### 1.2 Удалить CustomSubmit
**Файлы:** `src/form/model.gleam`, `src/form/update.gleam`
**Действия:**
- Удалить вариант `CustomSubmit` из типа `SubmitConfig`
- Упростить логику в `submit_form_effect`
- Оставить только `HttpSubmit` и `NoSubmit`

#### 1.3 Вынести Web Component
**Файл:** `src/formosh/component.gleam`
**Действия:**
- Переместить в отдельный пакет `formosh_web_component`
- Или удалить если не критично

### Фаза 2: Упрощение сложного кода (KISS)

#### 2.1 Рефакторинг path traversal
**Файл:** `src/form/model.gleam`
**Новая реализация:**
```gleam
pub fn traverse_path(value: Value, path: FieldPath) -> Option(Value) {
  case path, value {
    [], v -> Some(v)
    [PropertySegment(name), ..rest], ObjectValue(fields) ->
      fields
      |> list.find(fn(f) { f.0 == name })
      |> option.map(fn(f) { f.1 })
      |> option.flat_map(traverse_path(_, rest))
    [ArraySegment(i), ..rest], ArrayValue(items) ->
      list.at(items, i)
      |> option.flat_map(traverse_path(_, rest))
    _, _ -> None
  }
}
```

#### 2.2 Упростить конверсии значений
**Файл:** `src/form/update.gleam`
**Действия:**
- Удалить `model_to_root_value` и `root_value_to_model_values`
- Работать напрямую с dict значениями
- Использовать path.set_value_in_dict вместо промежуточных преобразований

### Фаза 3: Устранение дублирования (DRY)

#### 3.1 Централизовать валидацию required
**Новый файл:** `src/validation/rules.gleam`
```gleam
pub fn check_required(
  field_name: String,
  value: Option(Value)
) -> Result(Nil, ValidationError) {
  case value {
    None | Some(NullValue) | Some(StringValue("")) ->
      Error(ValidationError(
        field: field_name,
        message: "This field is required",
        rule: "required"
      ))
    _ -> Ok(Nil)
  }
}
```

#### 3.2 Обобщить функции извлечения значений
**Файл:** `src/fields/field_common.gleam`
```gleam
pub fn extract_value(value: Option(Value), extractor: fn(Value) -> Option(a), default: a) -> a {
  value
  |> option.flat_map(extractor)
  |> option.unwrap(default)
}

// Использование:
let string_val = extract_value(value, fn(v) {
  case v {
    StringValue(s) -> Some(s)
    _ -> None
  }
}, "")
```

### Фаза 4: Улучшение функционального стиля

#### 4.1 Добавить lens-подобные функции
**Новый файл:** `src/form/lens.gleam`
```gleam
pub type Lens(a, b) {
  Lens(
    get: fn(a) -> b,
    set: fn(a, b) -> a
  )
}

pub fn values_lens() -> Lens(FormModel, Dict(String, Value)) {
  Lens(
    get: fn(model) { model.values },
    set: fn(model, values) { FormModel(..model, values: values) }
  )
}

pub fn compose(lens1: Lens(a, b), lens2: Lens(b, c)) -> Lens(a, c) {
  Lens(
    get: fn(a) { lens2.get(lens1.get(a)) },
    set: fn(a, c) {
      let b = lens1.get(a)
      let new_b = lens2.set(b, c)
      lens1.set(a, new_b)
    }
  )
}
```

#### 4.2 Улучшить композицию в pipeline
**Пример рефакторинга:**
```gleam
// Было:
let validated_model = validate_all_fields(model)
let new_model = FormModel(..validated_model, is_submitting: True)
let submit_effect = submit_form_effect(new_model)

// Стало:
model
|> validate_all_fields
|> set_submitting(True)
|> fn(m) { #(m, submit_form_effect(m)) }
```

### Фаза 5: Исправление TODO

#### 5.1 Реализовать pattern validation
**Файл:** `src/schema/validator.gleam:164`
```gleam
// Добавить библиотеку gleam_regexp или реализовать базовую проверку
pub fn validate_pattern(value: String, pattern: String) -> Bool {
  // Временное решение: проверка на email
  case pattern {
    "^[\\w\\.-]+@[\\w\\.-]+\\.\\w+$" -> is_valid_email(value)
    _ -> True  // Пропускаем неизвестные паттерны
  }
}
```

#### 5.2 Декодирование form values
**Файл:** `src/formosh/component.gleam:123,142`
```gleam
pub fn decode_form_values(dynamic_value: Dynamic) -> Result(Dict(String, Value), List(DecodeError)) {
  decode.dict(decode.string, value_decoder())(dynamic_value)
}

fn value_decoder() -> Decoder(Value) {
  decode.any([
    decode.string |> decode.map(StringValue),
    decode.int |> decode.map(IntegerValue),
    decode.float |> decode.map(NumberValue),
    decode.bool |> decode.map(BooleanValue),
  ])
}
```

## 📊 Приоритеты и оценка времени

| Фаза | Приоритет | Сложность | Время |
|------|-----------|-----------|-------|
| Фаза 1: YAGNI | Высокий | Низкая | 2-3 часа |
| Фаза 2: KISS | Высокий | Средняя | 4-5 часов |
| Фаза 3: DRY | Средний | Низкая | 2-3 часа |
| Фаза 4: FP | Низкий | Высокая | 6-8 часов |
| Фаза 5: TODO | Средний | Средняя | 3-4 часа |

**Общее время:** ~17-23 часа

## 🎯 Ожидаемые результаты

1. **Уменьшение кодовой базы на ~20%** за счёт удаления неиспользуемого кода
2. **Улучшение читаемости** через упрощение сложных функций
3. **Повышение maintainability** через устранение дублирования
4. **Более идиоматичный Gleam код** с правильным функциональным стилем
5. **Устранение технического долга** (TODO комментарии)

## 🚀 Рекомендуемый порядок выполнения

1. Начать с Фазы 1 (YAGNI) - быстрые победы, сразу упрощает кодовую базу
2. Затем Фаза 2 (KISS) - улучшает понимание кода
3. Параллельно можно делать Фазу 3 (DRY) и Фазу 5 (TODO)
4. Фазу 4 (FP) оставить напоследок как "полировку"

## 📝 Дополнительные рекомендации

1. **Добавить тесты** перед рефакторингом критических частей
2. **Использовать feature flags** для постепенного внедрения изменений
3. **Документировать breaking changes** если они появятся
4. **Провести code review** после каждой фазы
5. **Обновить CLAUDE.md** после значительных изменений архитектуры