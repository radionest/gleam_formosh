#!/bin/bash

echo "Building project..."
gleam build

echo ""
echo "Starting Formosh file schema loader..."
echo "Open http://localhost:1234/example/file_loader.html in your browser"
echo ""

gleam run -m lustre/dev start