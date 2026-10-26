extends RefCounted

## Small collection helpers shared by the application and route layers.


## Strings in values that are not in excluded, de-duplicated, in first-seen
## order. Entries are coerced with String(); a non-Array argument counts as empty.
static func string_array_difference(values: Variant, excluded: Variant) -> Array[String]:
	var excluded_set := {}
	if excluded is Array:
		for entry in excluded:
			excluded_set[String(entry)] = true
	var difference: Array[String] = []
	var seen := {}
	if values is Array:
		for entry in values:
			var text := String(entry)
			if excluded_set.has(text) or seen.has(text):
				continue
			seen[text] = true
			difference.append(text)
	return difference


## Same set as string_array_difference, sorted ascending instead of first-seen.
static func sorted_string_array_difference(values: Variant, excluded: Variant) -> Array[String]:
	var difference := string_array_difference(values, excluded)
	difference.sort()
	return difference
