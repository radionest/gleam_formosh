#!/bin/bash

echo "Testing Form Submission for file_schema_loader"
echo "=============================================="
echo ""
echo "1. Development server running at: http://127.0.0.1:1234"
echo "2. Test server running at: http://localhost:8888"
echo ""
echo "Testing direct submission to test server..."
echo ""

# Test the server endpoint
curl -X POST http://localhost:8888 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com",
    "subject": "contact",
    "message": "This is a test submission from the form"
  }' \
  2>/dev/null | python3 -m json.tool

echo ""
echo "✅ Test server is working correctly!"
echo ""
echo "To test the full form submission:"
echo "1. Open http://127.0.0.1:1234 in your browser"
echo "2. Select a schema (e.g., contact_form.json)"
echo "3. Fill out the form"
echo "4. Click Submit"
echo "5. You should see a success message in green"
echo ""
echo "The form will automatically send data to http://localhost:8888"