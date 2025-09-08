// Schema loader utility for example application
// Note: In a real Gleam application, you would need to handle file I/O properly
// This is a simplified example showing the structure

import gleam/result
import gleam/string

/// Schema names available in the schemas directory
pub type SchemaName {
  ContactForm
  UserRegistration
  SurveyForm
}

/// Get the filename for a schema
pub fn get_schema_filename(schema: SchemaName) -> String {
  case schema {
    ContactForm -> "contact_form.json"
    UserRegistration -> "user_registration.json"
    SurveyForm -> "survey_form.json"
  }
}

/// Get the display name for a schema
pub fn get_schema_display_name(schema: SchemaName) -> String {
  case schema {
    ContactForm -> "Контактная форма"
    UserRegistration -> "Регистрация пользователя"
    SurveyForm -> "Опрос клиентов"
  }
}

/// Get all available schemas
pub fn get_available_schemas() -> List(SchemaName) {
  [ContactForm, UserRegistration, SurveyForm]
}

/// Load schema content from embedded strings
/// In a real application, this would read from files
pub fn load_schema(schema: SchemaName) -> String {
  case schema {
    ContactForm -> contact_form_schema
    UserRegistration -> user_registration_schema
    SurveyForm -> survey_form_schema
  }
}

// Embedded schema contents for the example
// In production, these would be loaded from files

const contact_form_schema = "{
  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
  \"$id\": \"https://example.com/schemas/contact-form.json\",
  \"title\": \"Контактная форма\",
  \"description\": \"Форма для связи с нами\",
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"title\": \"Полное имя\",
      \"description\": \"Введите ваше имя и фамилию\",
      \"minLength\": 2,
      \"maxLength\": 100
    },
    \"email\": {
      \"type\": \"string\",
      \"title\": \"Email адрес\",
      \"description\": \"Мы используем его только для ответа на ваш запрос\",
      \"format\": \"email\"
    },
    \"phone\": {
      \"type\": \"string\",
      \"title\": \"Телефон\",
      \"description\": \"Необязательно, но поможет связаться быстрее\",
      \"pattern\": \"^[+]?[0-9\\\\s()-]+$\",
      \"minLength\": 10,
      \"maxLength\": 20
    },
    \"subject\": {
      \"type\": \"string\",
      \"title\": \"Тема обращения\",
      \"enum\": [
        \"Общий вопрос\",
        \"Техническая поддержка\",
        \"Коммерческое предложение\",
        \"Жалоба\",
        \"Другое\"
      ]
    },
    \"message\": {
      \"type\": \"string\",
      \"title\": \"Сообщение\",
      \"description\": \"Опишите ваш вопрос или предложение\",
      \"minLength\": 10,
      \"maxLength\": 1000
    },
    \"subscribe\": {
      \"type\": \"boolean\",
      \"title\": \"Подписаться на новости\",
      \"description\": \"Получать обновления и полезную информацию\"
    }
  },
  \"required\": [\"name\", \"email\", \"subject\", \"message\"]
}"

const user_registration_schema = "{
  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
  \"$id\": \"https://example.com/schemas/user-registration.json\",
  \"title\": \"Регистрация пользователя\",
  \"description\": \"Форма регистрации нового пользователя\",
  \"type\": \"object\",
  \"properties\": {
    \"personalInfo\": {
      \"type\": \"object\",
      \"title\": \"Личная информация\",
      \"properties\": {
        \"firstName\": {
          \"type\": \"string\",
          \"title\": \"Имя\",
          \"minLength\": 2,
          \"maxLength\": 50
        },
        \"lastName\": {
          \"type\": \"string\",
          \"title\": \"Фамилия\",
          \"minLength\": 2,
          \"maxLength\": 50
        },
        \"birthDate\": {
          \"type\": \"string\",
          \"title\": \"Дата рождения\",
          \"format\": \"date\"
        }
      },
      \"required\": [\"firstName\", \"lastName\"]
    },
    \"accountInfo\": {
      \"type\": \"object\",
      \"title\": \"Данные аккаунта\",
      \"properties\": {
        \"username\": {
          \"type\": \"string\",
          \"title\": \"Имя пользователя\",
          \"pattern\": \"^[a-zA-Z0-9_]{3,20}$\",
          \"minLength\": 3,
          \"maxLength\": 20
        },
        \"email\": {
          \"type\": \"string\",
          \"title\": \"Email\",
          \"format\": \"email\"
        },
        \"password\": {
          \"type\": \"string\",
          \"title\": \"Пароль\",
          \"minLength\": 8,
          \"maxLength\": 50
        }
      },
      \"required\": [\"username\", \"email\", \"password\"]
    }
  },
  \"required\": [\"personalInfo\", \"accountInfo\"]
}"

const survey_form_schema = "{
  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
  \"$id\": \"https://example.com/schemas/survey-form.json\",
  \"title\": \"Опрос удовлетворенности\",
  \"description\": \"Помогите улучшить наш сервис\",
  \"type\": \"object\",
  \"properties\": {
    \"rating\": {
      \"type\": \"integer\",
      \"title\": \"Общая оценка (1-10)\",
      \"minimum\": 1,
      \"maximum\": 10
    },
    \"feedback\": {
      \"type\": \"string\",
      \"title\": \"Ваш отзыв\",
      \"maxLength\": 500
    },
    \"recommend\": {
      \"type\": \"boolean\",
      \"title\": \"Порекомендуете ли нас друзьям?\"
    }
  },
  \"required\": [\"rating\"]
}"
