// Demo: Customer Survey Form
// Example with ratings, multiple choice, and feedback

import formosh
import gleam/io
import lustre

pub fn main() {
  let schema =
    "{
    \"title\": \"Опрос удовлетворенности клиентов\",
    \"description\": \"Помогите нам улучшить наш сервис\",
    \"type\": \"object\",
    \"properties\": {
      \"respondentInfo\": {
        \"type\": \"object\",
        \"title\": \"О вас\",
        \"properties\": {
          \"name\": {
            \"type\": \"string\",
            \"title\": \"Ваше имя (необязательно)\",
            \"maxLength\": 100
          },
          \"email\": {
            \"type\": \"string\",
            \"title\": \"Email для обратной связи\",
            \"format\": \"email\"
          },
          \"customerType\": {
            \"type\": \"string\",
            \"title\": \"Тип клиента\",
            \"enum\": [
              \"Новый клиент\",
              \"Постоянный клиент\",
              \"VIP клиент\",
              \"Корпоративный клиент\"
            ]
          }
        },
        \"required\": [\"customerType\"]
      },
      \"serviceRating\": {
        \"type\": \"object\",
        \"title\": \"Оценка сервиса\",
        \"properties\": {
          \"overallSatisfaction\": {
            \"type\": \"integer\",
            \"title\": \"Общая удовлетворенность (1-10)\",
            \"minimum\": 1,
            \"maximum\": 10
          },
          \"recommendationLikelihood\": {
            \"type\": \"integer\",
            \"title\": \"Вероятность рекомендации друзьям (1-10)\",
            \"minimum\": 1,
            \"maximum\": 10
          },
          \"supportQuality\": {
            \"type\": \"integer\",
            \"title\": \"Качество поддержки (1-5)\",
            \"minimum\": 1,
            \"maximum\": 5
          },
          \"valueForMoney\": {
            \"type\": \"integer\",
            \"title\": \"Соотношение цена/качество (1-5)\",
            \"minimum\": 1,
            \"maximum\": 5
          }
        },
        \"required\": [\"overallSatisfaction\", \"recommendationLikelihood\"]
      },
      \"feedback\": {
        \"type\": \"object\",
        \"title\": \"Ваш отзыв\",
        \"properties\": {
          \"likes\": {
            \"type\": \"string\",
            \"title\": \"Что вам понравилось?\",
            \"maxLength\": 500
          },
          \"improvements\": {
            \"type\": \"string\",
            \"title\": \"Что можно улучшить?\",
            \"maxLength\": 500
          },
          \"generalComments\": {
            \"type\": \"string\",
            \"title\": \"Дополнительные комментарии\",
            \"maxLength\": 1000
          }
        }
      },
      \"futureEngagement\": {
        \"type\": \"object\",
        \"title\": \"Будущее взаимодействие\",
        \"properties\": {
          \"continuationLikelihood\": {
            \"type\": \"string\",
            \"title\": \"Продолжите ли использовать наш сервис?\",
            \"enum\": [
              \"Определенно да\",
              \"Скорее да\",
              \"Не уверен\",
              \"Скорее нет\",
              \"Определенно нет\"
            ]
          },
          \"interestedInUpdates\": {
            \"type\": \"boolean\",
            \"title\": \"Хотите получать информацию о новинках?\"
          },
          \"participateInBeta\": {
            \"type\": \"boolean\",
            \"title\": \"Готовы тестировать новые функции?\"
          }
        },
        \"required\": [\"continuationLikelihood\"]
      }
    },
    \"required\": [\"respondentInfo\", \"serviceRating\", \"futureEngagement\"]
  }"

  io.println("Starting Customer Survey Form Demo...")

  // Create custom submission handler for survey
  case formosh.from_json_string(schema) {
    Ok(form_app) -> {
      io.println("✓ Survey form created successfully")

      // Note: In a real implementation, you'd use custom handler here
      // For demo, we just use the default form
      case lustre.start(form_app, "#app", Nil) {
        Ok(_) -> {
          io.println("✓ Form started successfully")
          io.println("📊 Survey form is ready at http://localhost:1234")
        }
        Error(_) ->
          io.println("Note: Form will only display in browser environment")
      }
    }
    Error(_err) -> {
      io.println("Failed to create survey form")
    }
  }
}
