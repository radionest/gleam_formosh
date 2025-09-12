# File Schema Loader - План интеграции отправки форм

## Описание проекта
Пример приложения для загрузки JSON Schema из файлов и отображения динамических форм с использованием компонента Formosh.

## Текущая ситуация
- Компонент `formosh/component.gleam` уже содержит полный механизм отправки форм через HTTP
- Пример в `file_schema_loader.gleam` настроен на отправку на `/api/submit`
- Декодеры событий возвращают пустые словари вместо реальных данных

## План действий для включения отправки форм на localhost:8888

### 1. Изменить URL отправки (ОБЯЗАТЕЛЬНО)
**Файл:** `/home/nest/gleam_formosh/examples/file_schema_loader/src/file_schema_loader.gleam`  
**Строка:** 203  
**Изменение:**
```gleam
// Было:
attribute.attribute("submit-url", "/api/submit"),
// Стало:
attribute.attribute("submit-url", "http://localhost:8888"),
```

### 2. Исправить декодеры событий (РЕКОМЕНДУЕТСЯ)
**Файл:** `/home/nest/gleam_formosh/examples/file_schema_loader/src/file_schema_loader.gleam`  
**Строки:** 260-275

#### Добавить вспомогательную функцию для конвертации значений:
```gleam
import schema/types.{type Value, StringValue, NumberValue, BooleanValue, ObjectValue, ArrayValue}

fn decode_value_to_string(value: Value) -> String {
  case value {
    StringValue(s) -> s
    NumberValue(n) -> float.to_string(n)
    BooleanValue(b) -> bool.to_string(b)
    _ -> "complex_value"
  }
}
```

#### Обновить декодер формы:
```gleam
fn decode_form_submit() -> decode.Decoder(Msg) {
  use event_data <- decode.then(decode.at(["detail"], decode.dynamic))
  
  // Попытаться извлечь статус и данные
  let status = decode.at(["status"], decode.string)
    |> decode.run(event_data)
    |> result.unwrap("unknown")
  
  let values = case status {
    "success" -> {
      // Извлечь данные ответа сервера
      decode.at(["data"], decode.string)
        |> decode.run(event_data)
        |> result.map(fn(data) { dict.from_list([#("response", data)]) })
        |> result.unwrap(dict.new())
    }
    "error" -> {
      // Извлечь сообщение об ошибке
      decode.at(["error"], decode.string)
        |> decode.run(event_data)
        |> result.map(fn(error) { dict.from_list([#("error", error)]) })
        |> result.unwrap(dict.new())
    }
    _ -> dict.new()
  }
  
  decode.success(FormSubmitted(values))
}
```

### 3. Улучшить отображение результата отправки (ОПЦИОНАЛЬНО)
**Файл:** `/home/nest/gleam_formosh/examples/file_schema_loader/src/file_schema_loader.gleam`  
**Строки:** 113-122 и 178-186

#### Обновить обработчик FormSubmitted:
```gleam
FormSubmitted(values) -> {
  let result_message = case dict.get(values, "error") {
    Ok(error) -> "Ошибка отправки: " <> error
    Error(_) -> case dict.get(values, "response") {
      Ok(response) -> "Форма успешно отправлена! Ответ сервера: " <> response
      Error(_) -> "Форма отправлена на http://localhost:8888"
    }
  }
  
  #(
    Model(
      ..model,
      submission_result: option.Some(result_message),
    ),
    effect.none(),
  )
}
```

#### Улучшить отображение в view:
```gleam
// Submission result with styling
case model.submission_result {
  option.Some(result) -> {
    let is_error = string.contains(result, "Ошибка")
    html.div([
      attribute.class(case is_error {
        True -> "form-status error"
        False -> "form-status success"
      })
    ], [
      html.text(result),
      html.button([
        event.on_click(ClearSubmissionResult),
        attribute.class("clear-button"),
      ], [html.text("×")])
    ])
  }
  option.None -> element.none()
}
```

### 4. Добавить очистку результата (ОПЦИОНАЛЬНО)
Добавить новое сообщение в тип Msg:
```gleam
pub type Msg {
  // ... existing messages
  ClearSubmissionResult
}
```

И обработчик:
```gleam
ClearSubmissionResult -> {
  #(Model(..model, submission_result: option.None), effect.none())
}
```

## Как работает механизм отправки

1. **Компонент автоматически отправляет форму:**
   - При нажатии кнопки Submit в форме
   - Компонент сам делает HTTP POST запрос на указанный URL
   - Отправляет JSON с данными формы

2. **Компонент эмитит события:**
   - `formosh-submit` - результат отправки (успех/ошибка)
   - `formosh-change` - при изменении полей формы
   - `formosh-validate` - при валидации

3. **Приложение может слушать события:**
   - Для отображения результата
   - Для дополнительной обработки данных
   - Но это опционально - отправка работает без обработчиков

## Тестирование

### Запуск тестового сервера на localhost:8888
```bash
# Простой echo сервер на Python
python3 -m http.server 8888

# Или с помощью Node.js
npx http-echo-server 8888
```

### Запуск приложения
```bash
# В директории examples/file_schema_loader
gleam run -m lustre/dev start
```

### Проверка отправки
1. Откройте приложение в браузере (обычно http://localhost:1234)
2. Выберите схему (например, contact_form.json)
3. Заполните форму
4. Нажмите Submit
5. Проверьте консоль сервера на localhost:8888 - должен прийти POST запрос с JSON

## Важные замечания

- **Минимальное изменение:** Достаточно только изменить URL в строке 203
- **CORS:** Убедитесь, что сервер на localhost:8888 разрешает CORS запросы
- **Компонент делает всё сам:** Не нужно вручную отправлять формы - компонент это делает автоматически

## Структура отправляемых данных

Компонент отправляет JSON в формате:
```json
{
  "name": "Значение поля name",
  "email": "user@example.com",
  "subject": "Выбранная тема",
  // ... остальные поля формы
}
```

## Разработка

```bash
gleam deps download  # Установка зависимостей
gleam build         # Сборка проекта
gleam test          # Запуск тестов
gleam run -m lustre/dev start  # Запуск dev-сервера
```