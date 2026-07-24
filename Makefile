.PHONY: demo demo-server demo-deps test format build e2e

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

e2e:
	npm run e2e
