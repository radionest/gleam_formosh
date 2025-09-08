// Demo: Contact Form
// Simple example showing a basic contact form

import formosh
import lustre
import gleam/io

pub fn main() {
  let schema = "{
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
  
  io.println("Starting Contact Form Demo...")
  
  case formosh.from_json_string_with_config(
    schema,
    formosh.HttpSubmit(
      url: "https://api.example.com/contact",
      method: "POST",
      headers: [#("Content-Type", "application/json")],
    ),
  ) {
    Ok(form_app) -> {
      io.println("✓ Contact form created successfully")
      
      let app = formosh.to_lustre_app(form_app)
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> {
          io.println("✓ Form started successfully")
          io.println("📋 Contact form is ready at http://localhost:1234")
        }
        Error(_) -> io.println("Note: Form will only display in browser environment")
      }
    }
    Error(_err) -> {
      io.println("Failed to create contact form")
    }
  }
}