// Demo: User Registration Form
// Complex example with nested objects and validation

import formosh
import lustre
import gleam/io

pub fn main() {
  // Simplified version of user registration schema
  let schema = "{
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
          },
          \"gender\": {
            \"type\": \"string\",
            \"title\": \"Пол\",
            \"enum\": [\"Мужской\", \"Женский\", \"Не указано\"]
          }
        },
        \"required\": [\"firstName\", \"lastName\", \"birthDate\"]
      },
      \"accountInfo\": {
        \"type\": \"object\",
        \"title\": \"Данные аккаунта\",
        \"properties\": {
          \"username\": {
            \"type\": \"string\",
            \"title\": \"Имя пользователя\",
            \"description\": \"Будет использоваться для входа\",
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
            \"description\": \"Минимум 8 символов\",
            \"minLength\": 8,
            \"maxLength\": 50
          }
        },
        \"required\": [\"username\", \"email\", \"password\"]
      },
      \"address\": {
        \"type\": \"object\",
        \"title\": \"Адрес\",
        \"properties\": {
          \"country\": {
            \"type\": \"string\",
            \"title\": \"Страна\",
            \"enum\": [
              \"Россия\",
              \"Беларусь\",
              \"Казахстан\",
              \"Украина\",
              \"Армения\"
            ]
          },
          \"city\": {
            \"type\": \"string\",
            \"title\": \"Город\",
            \"minLength\": 2,
            \"maxLength\": 100
          }
        },
        \"required\": [\"country\", \"city\"]
      },
      \"agreement\": {
        \"type\": \"object\",
        \"title\": \"Согласия\",
        \"properties\": {
          \"termsAccepted\": {
            \"type\": \"boolean\",
            \"title\": \"Я принимаю условия пользовательского соглашения\",
            \"const\": true
          },
          \"privacyAccepted\": {
            \"type\": \"boolean\",
            \"title\": \"Я согласен с политикой конфиденциальности\",
            \"const\": true
          }
        },
        \"required\": [\"termsAccepted\", \"privacyAccepted\"]
      }
    },
    \"required\": [\"personalInfo\", \"accountInfo\", \"address\", \"agreement\"]
  }"
  
  io.println("Starting User Registration Form Demo...")
  
  case formosh.from_json_string_with_config(
    schema,
    formosh.HttpSubmit(
      url: "https://api.example.com/register",
      method: "POST",
      headers: [
        #("Content-Type", "application/json"),
        #("X-Form-Type", "registration"),
      ],
    ),
  ) {
    Ok(form_app) -> {
      io.println("✓ Registration form created successfully")
      
      let app = formosh.to_lustre_app(form_app)
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> {
          io.println("✓ Form started successfully")
          io.println("👤 Registration form is ready at http://localhost:1234")
        }
        Error(_) -> io.println("Note: Form will only display in browser environment")
      }
    }
    Error(_err) -> {
      io.println("Failed to create registration form")
    }
  }
}