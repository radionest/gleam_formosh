# Детальный план рефакторинга Formosh

## Анализ соответствия принципам YAGNI, KISS, DRY

### 🚫 YAGNI (You Aren't Gonna Need It) - Избыточная инженерия

#### 1. Система конфигурации отправки форм

**Проблема**: Весь механизм `SubmitConfig` не используется, но занимает значительное место в коде.

**Файлы и строки**:
- `src/formosh.gleam:17-24` - определение типа SubmitConfig
- `src/formosh.gleam:87-131` - функции конфигурации (with_submit_url, with_http_submit, with_custom_submit)
- `src/formosh.gleam:266-283` - from_json_string_with_config
- `src/form/update.gleam:284-292` - submit_form_effect всегда возвращает фиктивный успех

**Текущая реализация**:
```gleam
// src/formosh.gleam:17-24
pub type SubmitConfig {
  HttpSubmit(url: String, method: HttpMethod, headers: List(#(String, String)))
  CustomSubmit(handler: fn(dict.Dict(String, JsonValue)) -> Effect(FormMsg))
  NoSubmit
}

// src/form/update.gleam:284-292
fn submit_form_effect(model: FormModel) -> Effect(FormMsg) {
  use _dispatch <- effect.from
  // Симулируем успешную отправку через 500ms
  let _ = timer.set_timeout(500, fn() {
    _dispatch(FormSubmitted(Ok(Nil)))
  })
  Nil
}
```

**Рефакторинг**: Удалить всю систему до реальной реализации:
```gleam
// Удалить из src/formosh.gleam:
// - Тип SubmitConfig (строки 17-24)
// - Тип HttpMethod (строки 11-15)
// - Поле submit_config из FormConfig (строка 36)
// - Все функции with_submit_* (строки 87-131)
// - Функцию from_json_string_with_config (строки 266-283)
// - Параметры submit из всех функций создания

// Упростить src/form/update.gleam:
// Оставить заглушку submit_form_effect до реализации
```

#### 2. Неиспользуемые поля FormConfig

**Проблема**: Поля установлены, но никогда не используются в логике.

**Файлы и строки**:
- `src/formosh.gleam:35` - css_prefix: никогда не используется в view.gleam
- `src/formosh.gleam:37` - show_errors_on_change: никогда не проверяется в update.gleam

**Рефакторинг**:
```gleam
// Удалить из FormConfig:
pub type FormConfig {
  FormConfig(
    // css_prefix: String,  // УДАЛИТЬ
    // show_errors_on_change: Bool,  // УДАЛИТЬ
    submit_config: SubmitConfig,  // Тоже удалить после удаления SubmitConfig
  )
}
```



### 🎯 KISS (Keep It Simple, Stupid) - Излишняя сложность

#### 1. Сложная система преобразования значений

**Проблема**: Преобразование между model values и hierarchical values слишком сложное.

**Файлы и строки**:
- `src/form/update.gleam:51-90` - model_to_root_value и root_value_to_model_values

**Текущая реализация**:
```gleam
fn model_to_root_value(model: FormModel) -> types.FieldValue {
  let root_dict = 
    model.values
    |> dict.to_list
    |> list.fold(dict.new(), fn(acc, entry) {
      let #(path_str, value) = entry
      case path.from_string(path_str) {
        Ok(field_path) -> insert_value_at_path(acc, field_path, value)
        Error(_) -> acc
      }
    })
  types.ObjectValue(root_dict)
}
```

**Упрощение**: Поскольку пути всё равно конвертируются в строки, хранить значения напрямую:
```gleam
// Упростить FormModel:
pub type FormModel {
  FormModel(
    schema: JsonSchema,
    values: dict.Dict(String, FieldValue),  // Путь как строка
    errors: dict.Dict(String, List(String)),
    touched: set.Set(String),
    submitted: Bool,
  )
}

// Убрать сложные преобразования
```

#### 2. Переусложнённые функции обхода путей

**Проблема**: Функции traverse_array_path и traverse_object_path слишком сложны для текущего использования.

**Файлы и строки**:
- `src/form/model.gleam:384-415` - traverse_array_path
- `src/form/model.gleam:427-447` - traverse_object_path

**Упрощение**: Удалить или значительно упростить до реальной необходимости в nested editing.

#### 3. Ненужные Option обёртки

**Проблема**: Функции возвращают Option там, где ошибка невозможна.

**Файлы и строки**:
- `src/form/converter.gleam:15-25` - json_to_field_value всегда успешна

**Текущая реализация**:
```gleam
pub fn json_to_field_value(json: JsonValue) -> Option(FieldValue) {
  case json {
    json.String(s) -> Some(types.StringValue(s))
    json.Number(n) -> Some(types.NumberValue(n))
    json.Bool(b) -> Some(types.BooleanValue(b))
    json.Array(items) -> Some(types.ArrayValue(...))
    json.Object(obj) -> Some(types.ObjectValue(...))
    json.Null -> None
  }
}
```

**Упрощение**:
```gleam
pub fn json_to_field_value(json: JsonValue) -> FieldValue {
  case json {
    json.String(s) -> types.StringValue(s)
    json.Number(n) -> types.NumberValue(n)
    json.Bool(b) -> types.BooleanValue(b)
    json.Array(items) -> types.ArrayValue(...)
    json.Object(obj) -> types.ObjectValue(...)
    json.Null -> types.NullValue  // Добавить NullValue в FieldValue
  }
}
```

#### 4. Сложная система conditional полей

**Проблема**: conditional_resolver.gleam содержит сложную логику, которая пока не используется полностью.

**Файлы и строки**:
- `src/schema/conditional_resolver.gleam` - весь файл

**Упрощение**: Отложить до реальной необходимости или упростить до базовых if/then условий.

### 📊 Метрики рефакторинга

#### Удаление кода
- **SubmitConfig система**: ~100 строк
- **Неиспользуемые функции**: ~50 строк
- **FormApp тип**: ~200 строк (включая связанные функции)
- **Сложные path функции**: ~80 строк
- **Итого к удалению**: ~430 строк

#### Консолидация
- **Извлечение значений**: 15 дублирований → 3 утилиты
- **Работа с путями**: 10 дублирований → 1 утилита
- **Label создание**: 6 дублирований → 1 функция
- **Итого устранено дублирований**: ~31 → 5 функций

#### Упрощение
- **Path-based хранение**: -40 строк сложности
- **Option обёртки**: -10 строк
- **Итого упрощено**: ~50 строк

### 📝 Приоритезированный план действий

#### Фаза 1: Очистка (1-2 часа)
1. Удалить SubmitConfig и всё связанное
2. Удалить неиспользуемые публичные функции
3. Удалить неиспользуемые поля FormConfig
4. Удалить FormApp и использовать lustre.App напрямую

#### Фаза 2: Консолидация (2-3 часа)
1. Создать утилиты извлечения значений в field_common
2. Создать утилиту работы с путями
3. Создать общую функцию создания label
4. Обновить все field рендереры

#### Фаза 3: Упрощение (2-3 часа)
1. Упростить хранение значений в FormModel
2. Удалить ненужные Option обёртки
3. Упростить или отложить conditional логику
4. Удалить сложные path traversal функции

### ✅ Ожидаемые результаты

- **Размер кодовой базы**: -25% (примерно 500 строк)
- **Дублирование**: -80% (с 31 до 5 паттернов)
- **Сложность**: Значительное снижение когнитивной нагрузки
- **Поддерживаемость**: Улучшение за счёт меньшего количества абстракций
- **Производительность**: Небольшое улучшение за счёт упрощения path handling
- **Тестируемость**: Улучшение за счёт удаления неиспользуемого кода

### 🎯 Финальная архитектура

После рефакторинга публичный API будет выглядеть так:

```gleam
// src/formosh.gleam - весь публичный API
import lustre
import schema/types.{type JsonSchema}
import form/model.{type FormModel, type FormMsg}

/// Создать форму из JSON Schema
pub fn from_schema(schema: JsonSchema) -> lustre.App(Nil, FormModel, FormMsg)

/// Создать форму из JSON строки
pub fn from_json_string(json: String) -> Result(lustre.App(Nil, FormModel, FormMsg), ParseError)

/// Запустить приложение формы
pub fn run(app: lustre.App(Nil, FormModel, FormMsg)) -> Result(Nil, lustre.Error)
```

Всего 3 функции вместо текущих 15+, при этом вся текущая функциональность сохранена.