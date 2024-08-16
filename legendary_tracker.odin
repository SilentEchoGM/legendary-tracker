package legendary_tracker

import "core:crypto"
import "core:encoding/json"
import "core:encoding/uuid"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/windows"

Win :: struct {
	scheme:      uuid.Identifier,
	id:          uuid.Identifier,
	extra_twist: int,
	face_card:   bool,
}

Scheme :: struct {
	id:        uuid.Identifier,
	name:      string,
	expansion: string,
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
			"|  %c  |  %v  |  %v  |  %v  |  %v  |  %v  |  %v  |  %v  |",
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

print_bool :: proc(truthy: bool) -> rune {
	if truthy {
		return '✓'
	} else {
		return 'x'
	}
}

main :: proc() {
	when ODIN_OS == .Windows {
		windows.SetConsoleOutputCP(windows.CODEPAGE.UTF8)
	}

	schemes: [dynamic]Scheme
	wins: [dynamic]Win

	loaded_schemes, schemes_ok := load_schemes()
	if !schemes_ok {
		return
	}

	append(&schemes, ..loaded_schemes)

	if len(schemes) == 0 {
		scheme, add_scheme_ok := add_scheme()
		append(&schemes, scheme)
		save_schemes(schemes[:])
	}

	longest_scheme_name := schemes[0].name
	for scheme in schemes {
		if len(scheme.name) > len(longest_scheme_name) {
			longest_scheme_name = scheme.name
		}
	}

	fmt.printfln("Loaded schemes. Longest scheme name: '%v'", longest_scheme_name)

	loaded_wins, wins_ok := load_wins()
	if !wins_ok {
		return
	}

	append(&wins, ..loaded_wins)

	fmt.printfln("\n\n%v\n\n", print_schemes(schemes[:], wins[:], len(longest_scheme_name) + 2))

	buf: [1024]byte

	fmt.print("Scheme? ")
	n, err := os.read(os.stdin, buf[:])

	if err != 0 {
		fmt.eprintln("Error reading: ", err)
		return
	}

	input_str := strings.to_lower(strings.split_lines(string(buf[:n]))[0])

	fmt.printfln("Searching for: '%v'", input_str)
	closest_schemes := get_closest_schemes(schemes[:], input_str)

	selected_scheme, select_ok := select_scheme(closest_schemes[:])
	if !select_ok {
		return
	}
	fmt.printfln("'%v' selected", selected_scheme.name)

	new_win, add_win_ok := add_win(selected_scheme)
	if (add_win_ok) {
		append(&wins, new_win)
		save_wins(wins[:])
		fmt.println("Wins updated!")
	} else {
		fmt.println("Failed to update wins.")
	}

}

add_win :: proc(scheme: Scheme) -> (win: Win, ok: bool = true) {
	fmt.println("Adding new win.")
	buf: [1024]byte

	context.random_generator = crypto.random_generator()
	win.id = uuid.generate_v4()
	win.scheme = scheme.id

	fmt.print("How many extra twists? ")
	n: int
	err: os.Errno

	n, err = os.read(os.stdin, buf[:])

	if err != 0 {
		fmt.println("Error reading: ", err)
		ok = false
		return
	}

	win.extra_twist = strconv.parse_int(strings.trim_space(string(buf[:n]))) or_else 0

	buf = [1024]byte{}

	fmt.print("Face card defeated (y/n)? ")

	n, err = os.read(os.stdin, buf[:])

	if err != 0 {
		fmt.println("Error reading: ", err)
		ok = false
		return
	}

	face := strings.trim_space(string(buf[:n]))
	if face == "y" {
		win.face_card = true
	} else if face == "n" {
		win.face_card = false
	} else {
		fmt.println("Invalid response")
		ok = false
	}
	return
}

save_wins :: proc(wins: []Win) -> bool {
	data, err := json.marshal(wins, {}, context.temp_allocator)

	if err != nil {
		fmt.println("Unable to marshal wins", err)
		return false
	}
	return os.write_entire_file("wins.json", data)
}

load_wins :: proc() -> (wins: []Win, ok: bool) {
	db_file, err := os.open("wins.json")
	defer os.close(db_file)

	if err != 0 {
		fmt.println("Failed to open wins file", err)

		if err == 2 {
			empty: string = "[]"
			write_ok := os.write_entire_file("wins.json", transmute([]u8)empty)

			if !write_ok {
				ok := false
				return
			}
			return load_wins()
		}
		ok = false
		return
	}

	data, read_ok := os.read_entire_file(db_file, context.temp_allocator)

	if !read_ok {
		fmt.println("Failed to read wins file")
		ok = false
		return
	}

	unmarshall_err := json.unmarshal(data, &wins)

	if unmarshall_err != nil {
		fmt.println("Failed to unmarshall wins file", unmarshall_err)
		ok = false
		return
	}
	ok = true
	return
}

add_scheme :: proc() -> (scheme: Scheme, ok: bool = true) {
	fmt.println("Adding new scheme.")
	buf: [1024]byte

	context.random_generator = crypto.random_generator()
	scheme.id = uuid.generate_v4()

	fmt.print("Scheme name? ")
	n: int
	err: os.Errno

	n, err = os.read(os.stdin, buf[:])

	if err != 0 {
		fmt.eprintln("Error reading: ", err)
		ok = false
		return
	}

	scheme.name = strings.to_lower(strings.split_lines(string(buf[:n]))[0])

	buf = [1024]byte{}

	fmt.print("Expansion? ")
	n, err = os.read(os.stdin, buf[:])

	if err != 0 {
		fmt.eprintln("Error reading: ", err)
		ok = false
		return
	}

	scheme.expansion = strings.to_lower(strings.split_lines(string(buf[:n]))[0])

	return
}

select_scheme :: proc(schemes: []Scheme) -> (selected_scheme: Scheme, ok: bool = true) {
	for scheme, i in schemes {
		fmt.printfln("%v: %v", i, scheme.name)
	}

	new_scheme_opt := len(schemes)

	fmt.printfln("%v: add new scheme", new_scheme_opt)

	buf := [1024]byte{}

	fmt.print("Selection? ")
	n, err := os.read(os.stdin, buf[:])

	if err != 0 {
		fmt.eprintln("Error reading: ", err)
		ok = false
		return
	}

	selection := strings.trim_space(string(buf[:n]))

	for scheme, i in schemes {
		index := fmt.aprintf("%v", i)
		if selection == index {
			selected_scheme = scheme
			return
		}
	}

	if selection == fmt.aprintf("%v", new_scheme_opt) {
		selected_scheme, ok = add_scheme()
		return
	}

	fmt.printfln("Invalid selection: '%v'", selection, new_scheme_opt)

	ok = false
	return
}

save_schemes :: proc(schemes: []Scheme) -> bool {
	data, err := json.marshal(schemes, {}, context.temp_allocator)

	if err != nil {
		fmt.println("Unable to marshal schemes", err)
		return false
	}
	return os.write_entire_file("schemes.json", data)
}

load_schemes :: proc() -> (schemes: []Scheme, ok: bool) {
	db_file, err := os.open("schemes.json")
	defer os.close(db_file)

	if err != 0 {
		fmt.println("Failed to open schemes file", err)

		if err == 2 {
			empty: string = "[]"
			write_ok := os.write_entire_file("schemes.json", transmute([]u8)empty)

			if !write_ok {
				ok := false
				return
			}
			return load_schemes()
		}
		ok = false
		return
	}

	data, read_ok := os.read_entire_file(db_file, context.temp_allocator)

	if !read_ok {
		fmt.println("Failed to read schemes file")
		ok = false
		return
	}

	unmarshall_err := json.unmarshal(data, &schemes)

	if unmarshall_err != nil {
		fmt.println("Failed to unmarshall schemes file", unmarshall_err)
		ok = false
		return
	}
	ok = true
	return
}

get_closest_schemes :: proc(schemes: []Scheme, input_str: string) -> (closest: [dynamic]Scheme) {
	distances: [dynamic]int

	if len(schemes) == 0 {
		return
	}

	for scheme, i in schemes {
		inject_at(&distances, i, strings.levenshtein_distance(input_str, scheme.name))
	}

	ordered_indices: [dynamic]int

	for i in 0 ..< len(schemes) {

		if len(ordered_indices) == 0 {
			append(&ordered_indices, i)
			continue
		}
		if distances[i] < distances[ordered_indices[0]] {
			inject_at(&ordered_indices, 0, i)
		}
	}

	for index in 0 ..< min(5, len(schemes)) {
		append(&closest, schemes[index])
	}

	return
}
