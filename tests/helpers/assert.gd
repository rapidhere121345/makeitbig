extends RefCounted
## Shared assertion helper for the headless test suites.
##
## Usage in a test script:
##   const Assert := preload("res://tests/helpers/assert.gd")
##   Assert.expect(value == 3, "value is three", failures)
## A failed expectation appends `message` to `failures`; the caller prints the
## list and exits non-zero when it is not empty. Scripts that predate this
## helper keep a one-line `_expect` wrapper that forwards here.


## Records `message` in `failures` when `condition` is false. Nothing is printed
## and nothing is thrown, so a test keeps running and reports every failure.
static func expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
