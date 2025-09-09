// Demo: Order Form with $ref and $defs
// Example showing how to use JSON Schema references for reusable components

import formosh
import gleam/io
import lustre

pub fn main() {
  let schema =
    "{
    \"title\": \"Заказ товара\",
    \"description\": \"Форма оформления заказа с доставкой\",
    \"type\": \"object\",
    \"properties\": {
      \"customer\": {
        \"$ref\": \"#/$defs/person\",
        \"title\": \"Информация о покупателе\"
      },
      \"billing_address\": {
        \"$ref\": \"#/$defs/address\",
        \"title\": \"Адрес для выставления счета\"
      },
      \"shipping_address\": {
        \"$ref\": \"#/$defs/address\",
        \"title\": \"Адрес доставки\"
      },
      \"items\": {
        \"type\": \"array\",
        \"title\": \"Товары в заказе\",
        \"items\": {
          \"$ref\": \"#/$defs/orderItem\"
        },
        \"minItems\": 1
      },
      \"payment_method\": {
        \"type\": \"string\",
        \"title\": \"Способ оплаты\",
        \"enum\": [\"Кредитная карта\", \"PayPal\", \"Банковский перевод\", \"Наличные при получении\"]
      },
      \"notes\": {
        \"type\": \"string\",
        \"title\": \"Комментарии к заказу\",
        \"maxLength\": 500
      }
    },
    \"required\": [\"customer\", \"billing_address\", \"shipping_address\", \"items\", \"payment_method\"],
    \"$defs\": {
      \"person\": {
        \"type\": \"object\",
        \"properties\": {
          \"first_name\": {
            \"type\": \"string\",
            \"title\": \"Имя\",
            \"minLength\": 1,
            \"maxLength\": 50
          },
          \"last_name\": {
            \"type\": \"string\",
            \"title\": \"Фамилия\",
            \"minLength\": 1,
            \"maxLength\": 50
          },
          \"email\": {
            \"type\": \"string\",
            \"title\": \"Email\",
            \"format\": \"email\"
          },
          \"phone\": {
            \"type\": \"string\",
            \"title\": \"Телефон\",
            \"pattern\": \"^[+]?[0-9\\\\s()-]+$\",
            \"minLength\": 10,
            \"maxLength\": 20
          }
        },
        \"required\": [\"first_name\", \"last_name\", \"email\", \"phone\"]
      },
      \"address\": {
        \"type\": \"object\",
        \"properties\": {
          \"street\": {
            \"type\": \"string\",
            \"title\": \"Улица и номер дома\",
            \"minLength\": 5,
            \"maxLength\": 100
          },
          \"apartment\": {
            \"type\": \"string\",
            \"title\": \"Квартира/Офис\",
            \"maxLength\": 20
          },
          \"city\": {
            \"type\": \"string\",
            \"title\": \"Город\",
            \"minLength\": 2,
            \"maxLength\": 50
          },
          \"state\": {
            \"type\": \"string\",
            \"title\": \"Область/Регион\",
            \"minLength\": 2,
            \"maxLength\": 50
          },
          \"postal_code\": {
            \"type\": \"string\",
            \"title\": \"Почтовый индекс\",
            \"pattern\": \"^[0-9]{5,6}$\"
          },
          \"country\": {
            \"type\": \"string\",
            \"title\": \"Страна\",
            \"enum\": [\"Россия\", \"Беларусь\", \"Казахстан\", \"Украина\", \"Другая\"]
          }
        },
        \"required\": [\"street\", \"city\", \"state\", \"postal_code\", \"country\"]
      },
      \"orderItem\": {
        \"type\": \"object\",
        \"properties\": {
          \"product_name\": {
            \"type\": \"string\",
            \"title\": \"Название товара\",
            \"minLength\": 1,
            \"maxLength\": 100
          },
          \"sku\": {
            \"type\": \"string\",
            \"title\": \"Артикул\",
            \"pattern\": \"^[A-Z0-9-]+$\",
            \"minLength\": 3,
            \"maxLength\": 20
          },
          \"quantity\": {
            \"type\": \"integer\",
            \"title\": \"Количество\",
            \"minimum\": 1,
            \"maximum\": 999
          },
          \"price\": {
            \"type\": \"number\",
            \"title\": \"Цена за единицу\",
            \"minimum\": 0.01,
            \"maximum\": 999999.99
          }
        },
        \"required\": [\"product_name\", \"sku\", \"quantity\", \"price\"]
      }
    }
  }"

  io.println("Starting Order Form Demo with $ref and $defs...")

  case
    formosh.from_json_string_with_config(
      schema,
      formosh.HttpSubmit(
        url: "https://api.example.com/orders",
        method: "POST",
        headers: [#("Content-Type", "application/json")],
      ),
    )
  {
    Ok(form_app) -> {
      io.println("✓ Order form created successfully")
      io.println("✓ References to person, address, and orderItem resolved")

      case lustre.start(form_app, "#app", Nil) {
        Ok(_) -> {
          io.println("✓ Form started successfully")
          io.println(
            "📋 Order form with $ref/$defs is ready at http://localhost:1234",
          )
          io.println("")
          io.println("This form demonstrates:")
          io.println("- Reusable 'person' definition for customer info")
          io.println("- Reusable 'address' definition for billing and shipping")
          io.println("- Reusable 'orderItem' in array for multiple items")
          io.println(
            "- All definitions stored in $defs and referenced via $ref",
          )
        }
        Error(_) ->
          io.println("Note: Form will only display in browser environment")
      }
    }
    Error(_err) -> {
      io.println("Failed to create order form")
    }
  }
}
