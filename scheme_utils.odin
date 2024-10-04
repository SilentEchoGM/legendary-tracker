package legendary_tracker

import "core:fmt"
import "core:strings"

print_bool :: proc(truthy: bool) -> rune {
	if truthy {
		return '✔'
	} else {
		return ' '
	}
}

capitalize :: proc(str: string) -> string {
	builder := strings.builder_make(context.temp_allocator)

	words := strings.split(str, " ", context.temp_allocator)

	for word in words {
		strings.write_string(&builder, strings.to_pascal_case(word, context.temp_allocator))
		strings.write_string(&builder, " ")
	}

	return strings.to_string(builder)
}

print_scheme :: proc(scheme: Scheme, wins: []Win, name_col_width: int) -> string {
	builder := strings.builder_make()


	strings.write_string(
		&builder,
		strings.center_justify(
			capitalize(scheme.name),
			name_col_width,
			" ",
			context.temp_allocator,
		),
	)

	twist_set: bit_set[0 ..< 4]
	face_set: bit_set[0 ..< 4]

	for win in wins {
		if win.scheme == scheme.id {
			if win.face_card {
				face_set += bit_set[0 ..< 4]{win.extra_twist}
			} else {
				twist_set += bit_set[0 ..< 4]{win.extra_twist}
			}}
	}

	strings.write_string(
		&builder,
		fmt.aprintf(
			"| %v   | %v   | %v   | %v   | %v   | %v   | %v   | %v   |",
			print_bool(0 in twist_set),
			print_bool(1 in twist_set),
			print_bool(2 in twist_set),
			print_bool(3 in twist_set),
			print_bool(0 in face_set),
			print_bool(1 in face_set),
			print_bool(2 in face_set),
			print_bool(3 in face_set),
		),
	)

	return strings.to_string(builder)
}

print_schemes :: proc(schemes: []Scheme, wins: []Win, name_col_width: int) -> string {
	builder := strings.builder_make(context.temp_allocator)

	name_col_string := strings.center_justify("Name", name_col_width, " ", context.temp_allocator)
	strings.write_string(
		&builder,
		fmt.aprintf("%v| +0  | +1  | +2  | +3  | F+0 | F+1 | F+2 | F+3 |\n\n", name_col_string),
	)


	for scheme in schemes {
		strings.write_string(
			&builder,
			fmt.aprintf("%v\n", print_scheme(scheme, wins, name_col_width)),
		)
	}

	return strings.to_string(builder)
}
