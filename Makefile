.PHONY: demo demo-server demo-deps test format build

demo:
	cd demo && gleam deps download && gleam run -m lustre/dev start

demo-server:
	cd demo && python3 test_server.py

demo-deps:
	cd demo && gleam deps download

test:
	gleam test

format:
	gleam format

build:
	npm run build
