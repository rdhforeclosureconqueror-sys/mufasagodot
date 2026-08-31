class_name WorldRegistry
extends Resource

@export var destinations: Array[Resource] = []

func resolve(destination_id: StringName) -> Resource:
	for destination in destinations:
		if destination != null and destination.id == destination_id:
			return destination
	return null

func enabled_destinations() -> Array[Resource]:
	var result: Array[Resource] = []
	for destination in destinations:
		if destination != null and destination.enabled and destination.is_valid():
			result.append(destination)
	return result

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for index in destinations.size():
		var destination := destinations[index]
		if destination == null:
			errors.append("Destination %d is null" % index)
			continue
		if destination.id.is_empty():
			errors.append("Destination %d has an empty id" % index)
		elif seen.has(destination.id):
			errors.append("Duplicate destination id: %s" % destination.id)
		else:
			seen[destination.id] = true
		if destination.scene == null:
			errors.append("Destination %s has no scene" % destination.id)
	return errors
